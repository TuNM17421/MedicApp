import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { normalizeInviteCode } from '../src/family/api.js';
import { localIso } from '../src/clinic/time.js';
import { openDatabase } from '../src/db/index.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { config, mockExtractor } from './helpers.js';

let server;
let base;
let db;
const lines = [];

before(async () => {
  db = openDatabase();
  server = createApp({
    config: config(), extractor: mockExtractor, stt: unavailableStt, db,
    log: (e, f) => lines.push(JSON.stringify({ event: e, ...f })),
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => new Promise((r) => server.close(r)));

const req = async (path, { method = 'GET', body, token } = {}) => {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
};

const MOTHER = { name: 'Phạm Thị Lan', relationship: 'Mẹ', birthYear: 1948, gender: 'Nữ' };

async function linked({ shareMissed } = {}) {
  server.clinic.family.resetLimits();
  const made = await req('/v1/family/links', { method: 'POST', body: { ownerName: 'Phạm Văn Hòa', profile: MOTHER } });
  assert.equal(made.status, 201);
  const claim = await req('/v1/family/claim', {
    method: 'POST', body: { code: made.body.invite.code, memberName: 'Phạm Thị Lan', shareMissed },
  });
  assert.equal(claim.status, 200);
  return { id: made.body.link.id, owner: made.body.token, member: claim.body.token };
}

const minutesAgo = (n) => localIso(Date.now() - n * 60_000);

test('the owner makes a code; the member claims it once and both see the link', async () => {
  const made = await req('/v1/family/links', { method: 'POST', body: { ownerName: 'Phạm Văn Hòa', profile: MOTHER } });
  assert.equal(made.status, 201);
  assert.equal(made.body.link.status, 'pending');
  assert.match(made.body.invite.code, /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  const id = made.body.link.id;

  // Lower case and without the dash still works.
  const code = made.body.invite.code.toLowerCase().replace('-', '');
  assert.equal(normalizeInviteCode(code), made.body.invite.code.replace('-', ''));
  const claim = await req('/v1/family/claim', { method: 'POST', body: { code, memberName: 'Phạm Thị Lan' } });
  assert.equal(claim.status, 200);
  assert.equal(claim.body.link.role, 'member');
  assert.equal(claim.body.link.ownerName, 'Phạm Văn Hòa');
  assert.deepEqual(claim.body.link.profile, MOTHER);
  assert.equal(claim.body.link.shareMissed, true);

  const again = await req('/v1/family/claim', { method: 'POST', body: { code, memberName: 'Người khác' } });
  assert.equal(again.status, 404);
  assert.equal(again.body.error.code, 'bad_code');

  const seen = await req(`/v1/family/links/${id}`, { token: made.body.token });
  assert.equal(seen.body.status, 'linked');
  assert.equal(seen.body.memberName, 'Phạm Thị Lan');
  const events = await req(`/v1/family/links/${id}/events`, { token: made.body.token });
  assert.deepEqual(events.body.events.map((e) => e.kind), ['link.claimed']);

  assert.equal((await req(`/v1/family/links/${id}`, { token: 'x'.repeat(43) })).status, 401);
  assert.equal((await req(`/v1/family/links/${id}`)).status, 401);
  // Logs never carry names or codes.
  assert.ok(lines.every((l) => !l.includes('Lan') && !l.includes(made.body.invite.code)));
});

test('a code expires and a bad body is refused', async () => {
  const made = await req('/v1/family/links', { method: 'POST', body: { ownerName: 'Hòa', profile: MOTHER } });
  db.prepare("UPDATE family_invite SET expires_at = '2000-01-01T00:00:00+07:00' WHERE link_id = ?").run(made.body.link.id);
  server.clinic.family.resetLimits();
  const late = await req('/v1/family/claim', { method: 'POST', body: { code: made.body.invite.code, memberName: 'Lan' } });
  assert.equal(late.status, 404);
  const fresh = await req(`/v1/family/links/${made.body.link.id}/invite`, { method: 'POST', token: made.body.token });
  assert.equal(fresh.status, 200);
  assert.notEqual(fresh.body.invite.code, made.body.invite.code);

  const bad = await req('/v1/family/links', { method: 'POST', body: { ownerName: '', profile: { name: 'x' } } });
  assert.equal(bad.status, 400);
  assert.deepEqual(bad.body.error.fields, ['profile', 'ownerName']);
});

test('claims are rate limited per address', async () => {
  server.clinic.family.resetLimits();
  let last;
  for (let i = 0; i < 11; i++) {
    last = await req('/v1/family/claim', { method: 'POST', body: { code: 'AAAA-AAAA', memberName: 'Lan' } });
  }
  assert.equal(last.status, 429);
  server.clinic.family.resetLimits();
});

test('appointments go both ways; prescriptions only from owner to member', async () => {
  const { id, owner, member } = await linked();
  const visit = { id: 'v-1', body: { visit: { id: 'v-1', date: '2026-10-20' } } };
  assert.equal((await req(`/v1/family/links/${id}/events`, {
    method: 'POST', token: owner,
    body: { events: [{ kind: 'appointment.upsert', ...visit }, { kind: 'result.upsert', id: 'v-0', body: { visitId: 'v-0' } }] },
  })).status, 200);
  assert.equal((await req(`/v1/family/links/${id}/events`, {
    method: 'POST', token: member, body: { events: [{ kind: 'appointment.upsert', id: 'v-2', body: {} }] },
  })).status, 200);
  const sneaky = await req(`/v1/family/links/${id}/events`, {
    method: 'POST', token: member, body: { events: [{ kind: 'result.upsert', id: 'v-9', body: {} }] },
  });
  assert.equal(sneaky.status, 403);

  const toMember = await req(`/v1/family/links/${id}/events?after=0`, { token: member });
  assert.deepEqual(toMember.body.events.map((e) => [e.kind, e.id]), [['appointment.upsert', 'v-1'], ['result.upsert', 'v-0']]);
  assert.equal(toMember.body.events[0].body.visit.date, '2026-10-20');
  const later = await req(`/v1/family/links/${id}/events?after=${toMember.body.cursor}`, { token: member });
  assert.deepEqual(later.body.events, []);
  assert.equal(later.body.cursor, toMember.body.cursor);

  const toOwner = await req(`/v1/family/links/${id}/events`, { token: owner });
  assert.deepEqual(toOwner.body.events.map((e) => e.kind), ['link.claimed', 'appointment.upsert']);
});

test('the owner hears of missed and skipped doses, and of a late dose taken', async () => {
  const { id, owner, member } = await linked();
  const dose = (key, at) => ({ key, at, label: '07:00', meds: ['Allopurinol 300mg'] });
  const put = (body, token = member) => req(`/v1/family/links/${id}/doses`, { method: 'PUT', token, body });

  assert.equal((await put({ doses: [] }, owner)).status, 403);
  assert.equal((await put({
    doses: [dose('m|2026-10-14|morning', minutesAgo(90)), dose('m|2026-10-14|noon', minutesAgo(30)),
      dose('m|2026-10-14|evening', minutesAgo(80))],
    marks: [{ key: 'm|2026-10-14|evening', mark: 'skipped', reason: 'unwell', at: minutesAgo(75) }],
  })).status, 200);

  const first = await req(`/v1/family/links/${id}/events`, { token: owner });
  const alerts = first.body.events.filter((e) => e.kind.startsWith('dose.'));
  assert.deepEqual(alerts.map((e) => [e.kind, e.id]), [
    ['dose.skipped', 'm|2026-10-14|evening'],
    ['dose.missed', 'm|2026-10-14|morning'],
  ]);
  assert.equal(alerts[0].body.reason, 'unwell');
  assert.deepEqual(alerts[1].body.meds, ['Allopurinol 300mg']);
  // Told once; the 30-minute-old dose is not missed yet.
  const second = await req(`/v1/family/links/${id}/events?after=${first.body.cursor}`, { token: owner });
  assert.deepEqual(second.body.events, []);

  await put({ marks: [{ key: 'm|2026-10-14|morning', mark: 'taken', at: minutesAgo(1) }], doses: [] });
  const third = await req(`/v1/family/links/${id}/events?after=${first.body.cursor}`, { token: owner });
  assert.deepEqual(third.body.events.map((e) => e.kind), ['dose.taken']);
});

test('the member can stop sharing missed doses', async () => {
  const { id, owner, member } = await linked({ shareMissed: false });
  await req(`/v1/family/links/${id}/doses`, {
    method: 'PUT', token: member, body: { doses: [{ key: 'k', at: minutesAgo(120), label: '07:00', meds: [] }] },
  });
  const quiet = await req(`/v1/family/links/${id}/events`, { token: owner });
  assert.deepEqual(quiet.body.events.map((e) => e.kind), ['link.claimed']);

  const on = await req(`/v1/family/links/${id}/settings`, { method: 'PUT', token: member, body: { shareMissed: true } });
  assert.equal(on.body.shareMissed, true);
  const told = await req(`/v1/family/links/${id}/events?after=${quiet.body.cursor}`, { token: owner });
  assert.deepEqual(told.body.events.map((e) => e.kind), ['link.settings', 'dose.missed']);
});

test('either side can end the link; nothing more goes through', async () => {
  const { id, owner, member } = await linked();
  const gone = await req(`/v1/family/links/${id}`, { method: 'DELETE', token: member });
  assert.equal(gone.body.status, 'ended');
  const events = await req(`/v1/family/links/${id}/events`, { token: owner });
  assert.equal(events.body.status, 'ended');
  assert.equal(events.body.events.at(-1).kind, 'link.ended');
  const after = await req(`/v1/family/links/${id}/events`, {
    method: 'POST', token: owner, body: { events: [{ kind: 'appointment.upsert', id: 'v', body: {} }] },
  });
  assert.equal(after.status, 409);
  assert.equal(after.body.error.code, 'link_ended');
});
