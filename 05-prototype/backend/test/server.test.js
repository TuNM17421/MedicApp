import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import WebSocket from 'ws';

import { describe as describeConfig, readConfig } from '../src/config.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { PROFILES, TODAY, config, mockExtractor } from './helpers.js';

const lines = [];
let server;
let base;

before(async () => {
  server = createApp({ config: config(), extractor: mockExtractor, stt: unavailableStt, log: (e, f) => lines.push(JSON.stringify({ e, ...f })) });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => new Promise((r) => server.close(r)));

const post = (path, body, token) =>
  fetch(base + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { 'x-session-token': token } : {}) },
    body: JSON.stringify(body),
  });
const start = async (known) => (await post('/v1/smart/sessions', { today: TODAY, profiles: PROFILES, known })).json();

test('health reports mode without exposing the key', async () => {
  const cfg = readConfig({ OPENAI_API_KEY: 'sk-secret-123' });
  assert.equal(cfg.mode, 'openai');
  assert.ok(!JSON.stringify(cfg).includes('sk-secret'));
  assert.ok(!JSON.stringify(describeConfig(cfg)).includes('sk-secret'));
  const body = await (await fetch(`${base}/health`)).json();
  assert.equal(body.mode, 'mock');
  assert.equal(body.key_configured, false);
});

test('config refuses non-local hosts and openai mode without a key', () => {
  assert.throws(() => readConfig({ HOST: '0.0.0.0' }), /localhost/);
  assert.throws(() => readConfig({ SMART_MODE: 'openai' }), /OPENAI_API_KEY/);
});

test('session lifecycle: create, turn, choice, delete', async () => {
  const created = await start({ patient_id: 'self' });
  assert.equal(created.mode, 'mock');
  assert.equal(created.voice_available, false);
  assert.equal(created.reply.question.field, 'type');
  const { session_id: id, token } = created;
  let r = await (await post(`/v1/smart/sessions/${id}/turns`, { kind: 'text', text: 'khám dịch vụ, đau họng, ở Hòa Lạc, sớm nhất', client_turn_id: 't1' }, token)).json();
  assert.equal(r.status, 'ready');
  assert.equal(r.turn_id, 't1');
  r = await (await post(`/v1/smart/sessions/${id}/turns`, { kind: 'edit', field: 'doctorId', value: 'hoalac-ent-1' }, token)).json();
  assert.equal(r.fields.doctor_id, 'hoalac-ent-1');
  const bad = await post(`/v1/smart/sessions/${id}/turns`, { kind: 'choice', field: 'facilityId', value: 'x' }, token);
  assert.equal(bad.status, 400);
  const del = await fetch(`${base}/v1/smart/sessions/${id}`, { method: 'DELETE', headers: { 'x-session-token': token } });
  assert.equal(del.status, 204);
  const gone = await post(`/v1/smart/sessions/${id}/turns`, { kind: 'text', text: 'a' }, token);
  assert.equal(gone.status, 404);
});

test('wrong token and malformed context are refused without details', async () => {
  const { session_id: id } = await start();
  const r = await post(`/v1/smart/sessions/${id}/turns`, { kind: 'text', text: 'a' }, 'nope');
  assert.equal(r.status, 404);
  const bad = await post('/v1/smart/sessions', { today: 'x', profiles: [] });
  assert.equal(bad.status, 400);
  const body = await bad.json();
  assert.equal(body.error.code, 'bad_context');
  assert.ok(!('stack' in body.error));
});

test('profiles carry no names to the server', async () => {
  const res = await post('/v1/smart/sessions', { today: TODAY, profiles: [{ id: 'a', relationship: 'Mẹ', age: 70, name: 'Phạm Thị Lan' }] });
  const body = await res.json();
  assert.ok(!JSON.stringify(body).includes('Lan'));
});

test('mock mode tells the app voice is unavailable instead of faking it', async () => {
  const { session_id: id, token } = await start();
  const ws = new WebSocket(`${base.replace('http', 'ws')}/v1/smart/sessions/${id}/audio?token=${token}`);
  const message = await new Promise((resolve, reject) => {
    ws.once('message', (d) => resolve(JSON.parse(d.toString())));
    ws.once('error', reject);
  });
  assert.equal(message.type, 'session.error');
  assert.equal(message.code, 'stt_unavailable');
  ws.close();
});

test('logs contain no transcript text', () => {
  assert.ok(!lines.join('\n').includes('đau họng'));
});
