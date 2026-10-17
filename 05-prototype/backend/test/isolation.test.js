// Bước 18, plan §8 "Bảo mật": a doctor of clinic A never reaches clinic B,
// a patient token only reaches its own phone's visits, and data whose
// sharing was revoked (or expired) never comes back.
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { hashPassword } from '../src/clinic/auth.js';
import { ADMIN_EMAIL, DEMO_EMAIL, DEMO_PASSWORD, seedClinic } from '../src/clinic/seed.js';
import { addDays, at, localIso, today as clinicToday } from '../src/clinic/time.js';
import { openDatabase } from '../src/db/index.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { config, mockExtractor } from './helpers.js';

const B_PHONE = '0933000777';
let server;
let base;
let db;
let ids;
const as = {};

before(async () => {
  db = openDatabase();
  ids = await seedClinic(db, { today: clinicToday() });
  // Clinic B: a doctor, an admin and one patient with everything shared and a sent result.
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const hash = await hashPassword('mat-khau-phong-kham-b');
  run("INSERT INTO clinic (id, name, phone) VALUES ('c-b', 'Phòng khám B', '0922')");
  const staff = `INSERT INTO practitioner (id, clinic_id, full_name, title, role, email, password_hash, created_at)
    VALUES (?, 'c-b', ?, ?, ?, ?, ?, '2026-01-01T08:00:00+07:00')`;
  run(staff, 'pr-b', 'Bác Sĩ B', 'BS.', 'doctor', 'bs@b.test', hash);
  run(staff, 'pr-b-admin', 'Quản trị B', '', 'admin', 'quantri@b.test', hash);
  run(`INSERT INTO patient (id, clinic_id, code, full_name, birth_date, gender, phone)
    VALUES ('p-b', 'c-b', '777001', 'Người Bệnh B', '1960-05-05', 'Nữ', ?)`, B_PHONE);
  const day = ids.today;
  run(`INSERT INTO appointment (id, clinic_id, patient_id, practitioner_id, starts_at, status, claim_code, claim_expires_at)
    VALUES ('a-b', 'c-b', 'p-b', 'pr-b', ?, 'in_progress', 'BBBBBBBBBB', ?)`, at(day, '09:00'), at(addDays(day, 30), '09:00'));
  run(`INSERT INTO appointment (id, clinic_id, patient_id, starts_at, status) VALUES ('a-b2', 'c-b', 'p-b', ?, 'booked')`, at(day, '15:00'));
  run(`INSERT INTO consent (id, appointment_id, scope, wording_version, granted_at, expires_at)
    VALUES ('cs-b', 'a-b', '["intake","dose_log","self_meds"]', 1, ?, ?)`, at(day, '07:00'), at(addDays(day, 30), '07:00'));
  run(`INSERT INTO intake_answer (id, appointment_id, channel, question, answer, answered_at)
    VALUES ('i-b', 'a-b', 'booking', '', 'Bí mật phòng khám B', ?)`, at(day, '07:05'));
  run(`INSERT INTO visit_summary (id, appointment_id, sections, flags, mode, prompt_version, created_at)
    VALUES ('s-b', 'a-b', '[{"key":"chief","text":"Bí mật B","sources":["i-b"]}]', '[]', 'mock', 'seed', ?)`, at(day, '07:06'));
  run(`INSERT INTO visit_result (id, appointment_id, version, status, diagnosis, items, advice, signed_by, signed_at, updated_at)
    VALUES ('r-b', 'a-b', 1, 'sent', '[["I10","Tăng huyết áp"]]', '[]', 'Bí mật B', 'pr-b', ?, ?)`, at(day, '09:20'), at(day, '09:20'));
  run(`INSERT INTO audit_event (at, actor, action, patient_id, appointment_id) VALUES (?, 'pr-b', 'chart.view', 'p-b', 'a-b')`, at(day, '09:01'));

  server = createApp({ config: config(), extractor: mockExtractor, stt: unavailableStt, log: () => {}, db });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
  as.doctorA = await login(DEMO_EMAIL, DEMO_PASSWORD);
  as.adminA = await login(ADMIN_EMAIL, DEMO_PASSWORD);
  as.doctorB = await login('bs@b.test', 'mat-khau-phong-kham-b');
  as.adminB = await login('quantri@b.test', 'mat-khau-phong-kham-b');
});
after(() => new Promise((r) => server.close(r)));

const req = (path, { method = 'GET', body, cookie, token } = {}) => fetch(base + path, {
  method,
  headers: {
    ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
    ...(cookie ? { cookie } : {}),
    ...(token ? { authorization: `Bearer ${token}` } : {}),
  },
  body: body !== undefined ? JSON.stringify(body) : undefined,
});

async function login(email, password) {
  const res = await req('/v1/staff/login', { method: 'POST', body: { email, password } });
  assert.equal(res.status, 200, email);
  return res.headers.get('set-cookie').split(';')[0];
}

async function patientToken(phone) {
  server.clinic.patient.resetLimits();
  const { devCode } = await (await req('/v1/patient/otp', { method: 'POST', body: { phone } })).json();
  const res = await req('/v1/patient/session', { method: 'POST', body: { phone, code: devCode } });
  assert.equal(res.status, 200);
  return (await res.json()).token;
}

/** Every clinic resource of the other clinic, as [method, path, body]. */
const resources = (appt, patient, code, summary) => [
  ['GET', `/v1/appointments/${appt}/chart`],
  ['GET', `/v1/appointments/${appt}/result`],
  ['PUT', `/v1/appointments/${appt}/result-draft`, { diagnosis: [['I10', 'x']] }],
  ['POST', `/v1/appointments/${appt}/result/send`],
  ['POST', `/v1/appointments/${appt}/result/amend`, { reason: 'thử' }],
  ['POST', `/v1/appointments/${appt}/arrive`],
  ['POST', `/v1/appointments/${appt}/start`],
  ['GET', `/v1/patients/${patient}/history`],
  ['GET', `/v1/patients/${patient}/access-log`],
  ['GET', `/v1/clinic/access-log?patientCode=${code}`],
  ['POST', `/v1/summaries/${summary}/feedback`, { value: 'down' }],
];

async function expect404(cookie, list) {
  for (const [method, path, body] of list) {
    const res = await req(path, { method, body, cookie });
    const text = await res.text();
    assert.equal(res.status, 404, `${method} ${path}`);
    assert.equal(JSON.parse(text).error.code, 'not_found', path);
    assert.ok(!text.includes('Bí mật'), path);
  }
}

test('bác sĩ phòng khám A nhận 404 với mọi tài nguyên của phòng khám B, và ngược lại', async () => {
  await expect404(as.doctorA, resources('a-b', 'p-b', '777001', 's-b'));
  await expect404(as.doctorB, resources(ids.appointments.p2, 'p2', '000482', ids.summaries.p2));
  // Nothing changed in clinic B.
  assert.equal(db.prepare("SELECT status FROM appointment WHERE id = 'a-b'").get().status, 'in_progress');
  assert.equal(db.prepare("SELECT count(*) n FROM visit_result WHERE appointment_id = 'a-b'").get().n, 1);
  assert.equal(db.prepare("SELECT feedback FROM visit_summary WHERE id = 's-b'").get().feedback, null);

  const a = await (await req('/v1/clinic/worklist', { cookie: as.doctorA })).json();
  assert.ok(a.items.every((i) => i.appointmentId.startsWith('a-p')));
  const b = await (await req('/v1/clinic/worklist', { cookie: as.doctorB })).json();
  assert.deepEqual(b.items.map((i) => i.appointmentId), ['a-b', 'a-b2']);
});

test('quản trị phòng khám A không thấy, không khóa, không đặt lại tài khoản phòng khám B', async () => {
  for (const action of ['deactivate', 'reactivate', 'reset-password']) {
    const res = await req(`/v1/clinic/staff/pr-b/${action}`, { method: 'POST', cookie: as.adminA });
    assert.equal(res.status, 404, action);
  }
  const list = await (await req('/v1/clinic/staff', { cookie: as.adminA })).json();
  assert.ok(list.every((s) => !s.email.endsWith('@b.test')));
  const listB = await (await req('/v1/clinic/staff', { cookie: as.adminB })).json();
  assert.deepEqual(listB.map((s) => s.email).sort(), ['bs@b.test', 'quantri@b.test']);
  assert.equal((await req(`/v1/clinic/staff/${ids.doctorId}/deactivate`, { method: 'POST', cookie: as.adminB })).status, 404);
  assert.equal(db.prepare("SELECT active FROM practitioner WHERE id = 'pr-b'").get().active, 1);
  // Clinic B's access log by code is not reachable from A, and A's metrics hold only A's visits.
  assert.equal((await req('/v1/clinic/access-log?patientCode=777001', { cookie: as.adminA })).status, 404);
  const m = await (await req('/v1/clinic/pilot-metrics', { cookie: as.adminA })).json();
  assert.equal(m.totals.visits, 6);
  const mb = await (await req('/v1/clinic/pilot-metrics', { cookie: as.adminB })).json();
  assert.equal(mb.totals.visits, 2);
  assert.equal(mb.totals.withSummary, 1);
  // Clinic A's log has none of B's events.
  const log = await (await req('/v1/patients/p2/access-log?limit=100', { cookie: as.doctorA })).json();
  assert.ok(log.items.every((e) => e.appointmentId === null || e.appointmentId.startsWith('a-p')));
});

test('token người bệnh chỉ thấy lượt khám của số điện thoại mình', async () => {
  const lan = await patientToken(ids.phones.p2);
  const list = await (await req('/v1/patient/appointments', { token: lan })).json();
  assert.ok(list.length > 0);
  assert.ok(list.every((a) => a.id.startsWith('a-p2-')));
  const others = [ids.appointments.p1, ids.appointments.p4, 'a-b'];
  for (const id of others) {
    for (const [method, path, body] of [
      ['GET', `/v1/patient/appointments/${id}/result`],
      ['PUT', `/v1/patient/appointments/${id}/consent`, { scope: ['intake'], wordingVersion: 1 }],
      ['DELETE', `/v1/patient/appointments/${id}/consent`],
      ['PUT', `/v1/patient/appointments/${id}/intake`, { answers: [] }],
      ['PUT', `/v1/patient/appointments/${id}/self-meds`, { items: [] }],
    ]) {
      const res = await req(path, { method, body, token: lan });
      assert.equal(res.status, 404, `${method} ${path}`);
    }
  }
  // Dose events for another person's course are ignored, never stored.
  const dose = await req('/v1/patient/dose-events', {
    method: 'POST', token: lan,
    body: { events: [{ courseId: `${ids.historyAppointments.p1}#1`, day: ids.today, slot: 'morning', mark: 'taken', at: localIso() }] },
  });
  assert.deepEqual((await dose.json()).ignored, [`${ids.historyAppointments.p1}#1`]);
  assert.equal(db.prepare("SELECT count(*) n FROM dose_event WHERE patient_id = 'p1' AND day = ?").get(ids.today).n, 0);

  const b = await patientToken(B_PHONE);
  const bList = await (await req('/v1/patient/appointments', { token: b })).json();
  assert.deepEqual(bList.map((a) => a.id), ['a-b2', 'a-b']);
  assert.equal((await req(`/v1/patient/appointments/${ids.appointments.p1}/result`, { token: b })).status, 404);
  // A staff cookie is not a patient token, and a patient token is not a staff session.
  assert.equal((await req('/v1/patient/appointments', { cookie: as.doctorA })).status, 401);
  assert.equal((await req('/v1/clinic/worklist', { token: lan })).status, 401);
});

test('dữ liệu đã rút đồng ý (hoặc hết hạn) không bao giờ trả về', async () => {
  const lan = await patientToken(ids.phones.p2);
  const appt = ids.appointments.p2;
  const before = await (await req(`/v1/appointments/${appt}/chart`, { cookie: as.doctorA })).json();
  assert.ok(before.summary && before.intake.length && before.doseLog.length && before.selfMeds.length);
  const secrets = [...before.intake.map((i) => i.answer), before.selfMeds[0].name, before.summary.sections[0].text];

  assert.equal((await req(`/v1/patient/appointments/${appt}/consent`, { method: 'DELETE', token: lan })).status, 200);

  const check = async () => {
    const res = await req(`/v1/appointments/${appt}/chart`, { cookie: as.doctorA });
    const text = await res.text();
    const c = JSON.parse(text);
    assert.equal(c.consent.state, 'declined');
    assert.equal(c.summary, null);
    assert.deepEqual([c.intake, c.courses, c.doseLog, c.selfMeds], [[], [], [], []]);
    for (const s of secrets) assert.ok(!text.includes(s), s);
    const wl = await (await req('/v1/clinic/worklist', { cookie: as.doctorA })).text();
    const item = JSON.parse(wl).items.find((i) => i.appointmentId === appt);
    assert.equal(item.hasSummary, false);
    assert.equal(item.chiefComplaint, null);
    assert.equal(item.flagged, false);
    assert.ok(!('courses' in item) && !('doseLog' in item));
    for (const s of secrets) assert.ok(!wl.includes(s), s);
    assert.equal((await req(`/v1/summaries/${ids.summaries.p2}/feedback`, { method: 'POST', body: { value: 'up' }, cookie: as.doctorA })).status, 404);
    const log = await (await req('/v1/patients/p2/access-log?limit=100', { cookie: as.doctorA })).text();
    for (const s of secrets) assert.ok(!log.includes(s), s);
  };
  await check();
  // The app cannot push new data either.
  const up = await req(`/v1/patient/appointments/${appt}/intake`, {
    method: 'PUT', token: lan,
    body: { answers: [{ id: 'x', channel: 'pre_visit', question: '', answer: 'mới', answeredAt: localIso() }] },
  });
  assert.equal(up.status, 403);
  assert.equal((await up.json()).error.code, 'consent_required');

  // Expiry hides in the same way.
  const p6 = ids.appointments.p6;
  db.prepare('UPDATE consent SET expires_at = ? WHERE appointment_id = ?').run(localIso(Date.now() - 1000), p6);
  const c6 = await (await req(`/v1/appointments/${p6}/chart`, { cookie: as.doctorA })).json();
  assert.equal(c6.consent.reason, 'expired');
  assert.equal(c6.summary, null);
  assert.deepEqual(c6.selfMeds, []);
  assert.equal((await req(`/v1/summaries/${ids.summaries.p6}/feedback`, { method: 'POST', body: { value: 'up' }, cookie: as.doctorA })).status, 404);
});
