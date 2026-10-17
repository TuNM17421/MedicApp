import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { normalizePhone } from '../src/clinic/patient.js';
import { DEMO_EMAIL, DEMO_PASSWORD, seedClinic } from '../src/clinic/seed.js';
import { addDays, at, localIso, today as clinicToday } from '../src/clinic/time.js';
import { readConfig } from '../src/config.js';
import { openDatabase } from '../src/db/index.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { config, mockExtractor } from './helpers.js';

const CLAIM = 'K7MQ-4XR2-9D';
const STRANGER = '0987654321';
const lines = [];
let server;
let base;
let db;
let ids;
let staff;
const servers = [];

async function start(env = {}, log = () => {}) {
  const s = createApp({ config: config(env), extractor: mockExtractor, stt: unavailableStt, log, db });
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  servers.push(s);
  return { s, url: `http://127.0.0.1:${s.address().port}` };
}

before(async () => {
  db = openDatabase();
  ids = await seedClinic(db, { today: clinicToday(), claimCode: CLAIM });
  // Lan also goes to another clinic with the same phone; a stranger has her own phone.
  db.prepare("INSERT INTO clinic (id, name, phone) VALUES ('c-other', 'Phòng khám Khác', '0911')").run();
  db.prepare(`INSERT INTO patient (id, clinic_id, code, full_name, birth_date, gender, phone)
    VALUES ('p-lan2', 'c-other', '000009', 'Phạm Thị Lan', '1948-03-02', 'Nữ', ?)`).run(ids.phones.p2);
  db.prepare(`INSERT INTO appointment (id, clinic_id, patient_id, starts_at, specialty, kind, status)
    VALUES ('a-lan2', 'c-other', 'p-lan2', ?, 'Cơ xương khớp', 'Khám dịch vụ', 'booked')`).run(at(addDays(ids.today, 3), '14:00'));
  db.prepare(`INSERT INTO patient (id, clinic_id, code, full_name, birth_date, gender, phone)
    VALUES ('p-x', 'c-anbinh', '000999', 'Người Lạ', '1980-01-01', 'Nam', ?)`).run(STRANGER);
  db.prepare(`INSERT INTO appointment (id, clinic_id, patient_id, starts_at, status)
    VALUES ('a-x', 'c-anbinh', 'p-x', ?, 'booked')`).run(at(ids.today, '11:00'));
  ({ s: server, url: base } = await start({}, (e, f) => lines.push(JSON.stringify({ event: e, ...f }))));
  const res = await fetch(`${base}/v1/staff/login`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
  });
  staff = res.headers.get('set-cookie').split(';')[0];
});
after(() => Promise.all(servers.map((s) => new Promise((r) => s.close(r)))));

const reset = () => server.clinic.patient.resetLimits();
const req = (path, { method = 'GET', body, token, cookie, url = base } = {}) => fetch(url + path, {
  method,
  headers: {
    ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    ...(cookie ? { cookie } : {}),
  },
  body: body !== undefined ? JSON.stringify(body) : undefined,
});
const err = async (res) => (await res.json()).error;

async function signIn(phone, url = base) {
  const otp = await req('/v1/patient/otp', { method: 'POST', body: { phone }, url });
  assert.equal(otp.status, 202);
  const { devCode } = await otp.json();
  const res = await req('/v1/patient/session', { method: 'POST', body: { phone, code: devCode }, url });
  assert.equal(res.status, 200);
  return (await res.json()).token;
}

const chart = async (id) => (await req(`/v1/appointments/${id}/chart`, { cookie: staff })).json();
const worklistItem = async (id) => (await (await req('/v1/clinic/worklist', { cookie: staff })).json()).items.find((i) => i.appointmentId === id);

test('chuẩn hóa số điện thoại', () => {
  assert.equal(normalizePhone('0912 000 482'), '0912000482');
  assert.equal(normalizePhone('0912.000.482'), '0912000482');
  assert.equal(normalizePhone('0912-000-482'), '0912000482');
  assert.equal(normalizePhone('+84 912 000 482'), '0912000482');
  assert.equal(normalizePhone('84912000482'), '0912000482');
  for (const bad of ['912000482', '09120004821', '+8409120004', 'abc', '', null, 912000482, '0912_000_482', '+1 912 000 482']) {
    assert.equal(normalizePhone(bad), null, String(bad));
  }
});

test('cấu hình mã xác nhận', () => {
  assert.equal(readConfig({}).patientOtpMode, 'dev');
  assert.equal(readConfig({}).demoOtp, null);
  assert.equal(readConfig({ DEMO_OTP: '000000' }).demoOtp, '000000');
  assert.equal(readConfig({ DEMO_OTP: '000000', PATIENT_OTP_MODE: 'off' }).demoOtp, null);
  assert.equal(readConfig({ NODE_ENV: 'production', PATIENT_OTP_PEPPER: 'x' }).patientOtpMode, 'off');
  assert.throws(() => readConfig({ NODE_ENV: 'production' }), /PATIENT_OTP_PEPPER/);
  assert.throws(() => readConfig({ PATIENT_OTP_MODE: 'sms' }), /PATIENT_OTP_MODE/);
  assert.throws(() => readConfig({ DEMO_OTP: '12345' }), /DEMO_OTP/);
  assert.ok(!JSON.stringify(readConfig({ PATIENT_OTP_PEPPER: 'secret-pepper' })).includes('secret-pepper'));
});

test('xin mã: số sai 422, số lạ và số quen cùng một câu trả lời, mã lưu dạng băm', async () => {
  reset();
  let res = await req('/v1/patient/otp', { method: 'POST', body: { phone: '12345' } });
  assert.equal(res.status, 422);
  assert.deepEqual(await err(res), { code: 'bad_phone', message: 'Số điện thoại không hợp lệ.', fields: ['phone'] });

  res = await req('/v1/patient/otp', { method: 'POST', body: { phone: '+84 912 000 482' } });
  assert.equal(res.status, 202);
  const known = await res.json();
  assert.equal(known.expiresIn, 300);
  assert.match(known.devCode, /^\d{6}$/);
  const row = db.prepare('SELECT * FROM patient_otp WHERE phone = ?').get(ids.phones.p2);
  assert.ok(row.code_hash && !row.code_hash.includes(known.devCode));
  assert.equal(row.attempts, 0);
  assert.equal(row.expires_at.slice(0, 10), clinicToday());

  res = await req('/v1/patient/otp', { method: 'POST', body: { phone: '0900000001' } });
  assert.equal(res.status, 202);
  assert.deepEqual(Object.keys(await res.json()), Object.keys(known));
  assert.equal(db.prepare("SELECT count(*) n FROM patient_otp WHERE phone = '0900000001'").get().n, 0);
  // An unknown phone cannot sign in, whatever the code.
  res = await req('/v1/patient/session', { method: 'POST', body: { phone: '0900000001', code: '123456' } });
  assert.equal(res.status, 401);
  assert.equal((await err(res)).code, 'bad_code');

  const log = lines.filter((l) => l.includes('"patient_otp"')).at(-2);
  assert.deepEqual(JSON.parse(log), { event: 'patient_otp', phone: '09•••••482', code: known.devCode });
  assert.ok(!lines.some((l) => l.includes(ids.phones.p2) || l.includes('0900000001')));
});

test('đăng nhập: sai mã, tối đa 5 lần, hết hạn, mã chỉ dùng một lần', async () => {
  reset();
  const phone = ids.phones.p4;
  const ask = async () => (await (await req('/v1/patient/otp', { method: 'POST', body: { phone } })).json()).devCode;
  const verify = (code, p = phone) => req('/v1/patient/session', { method: 'POST', body: { phone: p, code } });
  let code = await ask();
  const wrong = code === '111111' ? '222222' : '111111';
  for (let i = 0; i < 4; i++) {
    const res = await verify(wrong);
    assert.equal(res.status, 401);
    assert.equal((await err(res)).code, 'bad_code');
  }
  assert.equal((await verify('abc')).status, 401); // 5th attempt
  assert.equal((await verify(code)).status, 401); // locked out: needs a new code
  assert.equal(db.prepare('SELECT count(*) n FROM patient_otp WHERE phone = ?').get(phone).n, 0);

  code = await ask();
  db.prepare('UPDATE patient_otp SET expires_at = ? WHERE phone = ?').run(localIso(Date.now() - 1000), phone);
  assert.equal((await verify(code)).status, 401);

  code = await ask();
  assert.equal((await verify(code, 'abc')).status, 422);
  const res = await verify(code, '0912-000-501');
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.match(body.token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(body.patient.phone, phone);
  assert.equal(body.patient.name, 'Lê Thị Mai');
  assert.match(body.expiresAt, /\+07:00$/);
  assert.equal(body.expiresAt.slice(0, 10), addDays(clinicToday(), 30));
  const session = db.prepare('SELECT * FROM patient_session WHERE phone = ?').get(phone);
  assert.notEqual(session.token_hash, body.token);
  assert.equal((await verify(code)).status, 401); // used
  assert.ok(!lines.some((l) => l.includes(body.token)));
});

test('giới hạn: 3 lần xin mã/10 phút mỗi số, 10 lần mỗi IP', async () => {
  reset();
  const phone = ids.phones.p6;
  for (let i = 0; i < 3; i++) assert.equal((await req('/v1/patient/otp', { method: 'POST', body: { phone } })).status, 202);
  let res = await req('/v1/patient/otp', { method: 'POST', body: { phone: '+84912000519' } });
  assert.equal(res.status, 429);
  assert.equal((await err(res)).code, 'rate_limited');
  // An unknown phone is limited the same way (no enumeration).
  reset();
  for (let i = 0; i < 3; i++) await req('/v1/patient/otp', { method: 'POST', body: { phone: '0900000002' } });
  assert.equal((await req('/v1/patient/otp', { method: 'POST', body: { phone: '0900000002' } })).status, 429);

  reset();
  const statuses = [];
  for (let i = 0; i < 11; i++) {
    statuses.push((await req('/v1/patient/otp', { method: 'POST', body: { phone: `09000001${String(i).padStart(2, '0')}` } })).status);
  }
  assert.deepEqual(statuses, [...Array(10).fill(202), 429]);
  reset();
});

test('PATIENT_OTP_MODE=off: 503 otp_unavailable; DEMO_OTP cố định mã', async () => {
  const off = await start({ PATIENT_OTP_MODE: 'off' });
  const res = await req('/v1/patient/otp', { method: 'POST', body: { phone: ids.phones.p1 }, url: off.url });
  assert.equal(res.status, 503);
  assert.equal((await err(res)).code, 'otp_unavailable');

  const demo = await start({ DEMO_OTP: '000000' });
  const otp = await req('/v1/patient/otp', { method: 'POST', body: { phone: ids.phones.p1 }, url: demo.url });
  assert.equal((await otp.json()).devCode, '000000');
  const session = await req('/v1/patient/session', { method: 'POST', body: { phone: ids.phones.p1, code: '000000' }, url: demo.url });
  assert.equal(session.status, 200);
  assert.equal((await session.json()).patient.name, 'Trần Văn Minh');
});

test('Bearer: thiếu, sai, hết hạn, đã đăng xuất đều 401', async () => {
  reset();
  for (const token of [null, 'nonsense-token-that-is-long-enough', 'a b']) {
    const res = await req('/v1/patient/appointments', { token });
    assert.equal(res.status, 401);
    assert.equal((await err(res)).code, 'unauthenticated');
  }
  const cookieOnly = await req('/v1/patient/appointments', { cookie: staff });
  assert.equal(cookieOnly.status, 401);

  let token = await signIn(ids.phones.p3);
  assert.equal((await req('/v1/patient/appointments', { token })).status, 200);
  const out = await req('/v1/patient/session', { method: 'DELETE', token });
  assert.equal(out.status, 204);
  assert.equal((await req('/v1/patient/appointments', { token })).status, 401);
  assert.equal((await req('/v1/patient/session', { method: 'DELETE' })).status, 204);

  token = await signIn(ids.phones.p3);
  db.prepare("UPDATE patient_session SET expires_at = ? WHERE phone = ? AND revoked_at IS NULL")
    .run(localIso(Date.now() - 1000), ids.phones.p3);
  assert.equal((await req('/v1/patient/appointments', { token })).status, 401);
});

test('lịch khám: chỉ của số điện thoại này, ở mọi phòng khám, mới nhất trước', async () => {
  reset();
  const token = await signIn(ids.phones.p2);
  const res = await req('/v1/patient/appointments', { token });
  assert.equal(res.status, 200);
  const list = await res.json();
  assert.deepEqual(list.map((a) => a.id), ['a-lan2', ids.appointments.p2, ids.historyAppointments.p2]);
  const today = list[1];
  assert.deepEqual(Object.keys(today).sort(), ['clinic', 'consent', 'id', 'intakeCount', 'kind', 'resultStatus', 'selfMeds', 'specialty',
    'startsAt', 'status', 'time'].sort());
  assert.deepEqual(today.clinic, { id: 'c-anbinh', name: 'Phòng khám Đa khoa An Bình', phone: '0900 000 000' });
  assert.equal(today.time, '08:30');
  assert.equal(today.status, 'arrived');
  assert.equal(today.consent.state, 'shared');
  assert.deepEqual(today.consent.scope, ['intake', 'dose_log', 'self_meds']);
  assert.equal(today.consent.revokedAt, null);
  assert.equal(today.intakeCount, 4);
  assert.deepEqual(today.selfMeds, [{ name: 'Paracetamol 500mg', how: '1 viên khi đau, khoảng 2 lần/ngày trong 2 ngày qua' }]);
  assert.equal(list[2].resultStatus, 'sent');
  assert.equal(list[0].consent, null);
  assert.equal(list[0].clinic.name, 'Phòng khám Khác');

  // A draft is not shown to the patient.
  db.prepare(`INSERT INTO visit_result (id, appointment_id, version, status, updated_at) VALUES ('r-draft', ?, 1, 'draft', ?)`)
    .run(ids.appointments.p2, localIso());
  const again = await (await req('/v1/patient/appointments', { token })).json();
  assert.equal(again[1].resultStatus, 'none');
  db.prepare("DELETE FROM visit_result WHERE id = 'r-draft'").run();

  const other = await (await req('/v1/patient/appointments', { token: await signIn(STRANGER) })).json();
  assert.deepEqual(other.map((a) => a.id), ['a-x']);
});

test('xem kết quả: giống mã nhận kết quả, ghi audit, 404 khi chưa có hoặc không phải của mình', async () => {
  reset();
  const token = await signIn(ids.phones.p1);
  const res = await req(`/v1/patient/appointments/${ids.appointments.p1}/result`, { token });
  assert.equal(res.status, 200);
  const mine = await res.json();
  const claimed = await (await fetch(`${base}/v1/results/claim/${CLAIM}`)).json();
  assert.deepEqual(mine, claimed);
  const audit = db.prepare("SELECT * FROM audit_event WHERE action = 'result.view' ORDER BY id DESC").get();
  assert.deepEqual([audit.actor, audit.patient_id, audit.appointment_id], ['patient', 'p1', ids.appointments.p1]);

  assert.equal((await req(`/v1/patient/appointments/${ids.appointments.p2}/result`, { token })).status, 404);
  const lan = await signIn(ids.phones.p2);
  assert.equal((await req(`/v1/patient/appointments/${ids.appointments.p2}/result`, { token: lan })).status, 404);
  assert.equal((await req('/v1/patient/appointments/nope/result', { token })).status, 404);
});

test('đồng ý chia sẻ: kiểm tra, cấp, cấp lại, rút; lượt đã hủy 409', async () => {
  reset();
  const token = await signIn(ids.phones.p5);
  const a = ids.appointments.p5;
  const put = (body, id = a) => req(`/v1/patient/appointments/${id}/consent`, { method: 'PUT', body, token });
  for (const [body, fields] of [[{ scope: [], wordingVersion: 1 }, ['scope']], [{ scope: ['intake', 'photos'], wordingVersion: 1 }, ['scope']],
    [{ scope: ['intake', 'intake'], wordingVersion: 1 }, ['scope']], [{ scope: ['intake'] }, ['wordingVersion']]]) {
    const res = await put(body);
    assert.equal(res.status, 422);
    assert.deepEqual(await err(res), { code: 'bad_consent', message: 'Phạm vi chia sẻ không hợp lệ.', fields });
  }
  assert.equal((await req(`/v1/patient/appointments/${a}/consent`, { method: 'DELETE', token })).status, 404);

  let res = await put({ scope: ['self_meds', 'intake'], wordingVersion: 1 });
  assert.equal(res.status, 200);
  const first = await res.json();
  assert.equal(first.state, 'shared');
  assert.deepEqual(first.scope, ['intake', 'self_meds']);
  assert.equal(first.expiresAt, at(addDays(ids.today, 30), '10:00'));
  assert.equal(first.revokedAt, null);
  assert.equal((await chart(a)).consent.state, 'shared');

  res = await put({ scope: ['intake', 'dose_log', 'self_meds'], wordingVersion: 1 });
  assert.deepEqual((await res.json()).scope, ['intake', 'dose_log', 'self_meds']);
  const rows = db.prepare('SELECT revoked_at FROM consent WHERE appointment_id = ? ORDER BY rowid').all(a);
  assert.equal(rows.length, 2);
  assert.ok(rows[0].revoked_at && rows[1].revoked_at === null);
  assert.deepEqual((await chart(a)).consent.scope, ['intake', 'dose_log', 'self_meds']);
  assert.ok(db.prepare("SELECT 1 FROM audit_event WHERE action = 'consent.grant' AND actor = 'patient' AND appointment_id = ?").get(a));

  // Someone else's visit, and a cancelled one.
  assert.equal((await put({ scope: ['intake'], wordingVersion: 1 }, ids.appointments.p2)).status, 404);
  const mai = await signIn(ids.phones.p4);
  db.prepare("UPDATE appointment SET status = 'cancelled' WHERE id = ?").run(ids.appointments.p4);
  res = await req(`/v1/patient/appointments/${ids.appointments.p4}/consent`, { method: 'PUT', body: { scope: ['intake'], wordingVersion: 1 }, token: mai });
  db.prepare("UPDATE appointment SET status = 'booked' WHERE id = ?").run(ids.appointments.p4);
  assert.equal(res.status, 409);
  assert.equal((await err(res)).code, 'bad_state');
});

test('đồng ý cho lượt khám đã qua: hết hạn sau 30 ngày kể từ bây giờ', async () => {
  reset();
  db.prepare(`INSERT INTO appointment (id, clinic_id, patient_id, starts_at, status) VALUES ('a-p5-old', 'c-anbinh', 'p5', ?, 'done')`)
    .run(at(addDays(ids.today, -60), '09:00'));
  const token = await signIn(ids.phones.p5);
  const res = await req('/v1/patient/appointments/a-p5-old/consent', { method: 'PUT', body: { scope: ['dose_log'], wordingVersion: 1 }, token });
  const view = await res.json();
  const days = (Date.parse(view.expiresAt) - Date.now()) / 86_400_000;
  assert.ok(days > 29.9 && days <= 30, String(days));
});

test('câu trả lời trước khám: cần đồng ý, ghi đè theo id, giới hạn', async () => {
  reset();
  const hoa = await signIn(ids.phones.p3);
  const answer = (over = {}) => ({ id: 'q1', channel: 'pre_visit', question: 'Đau ở đâu?', answer: 'Đau lưng', answeredAt: '2026-10-15T20:00:00+07:00', ...over });
  let res = await req(`/v1/patient/appointments/${ids.appointments.p3}/intake`, { method: 'PUT', body: { answers: [answer()] }, token: hoa });
  assert.equal(res.status, 403);
  assert.equal((await err(res)).code, 'consent_required');

  const token = await signIn(ids.phones.p5);
  const a = ids.appointments.p5;
  const put = (answers) => req(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', body: { answers }, token });
  res = await put([answer(), answer({ id: 'q2', channel: 'booking', question: '', answer: 'Khám lưng', answeredAt: '2026-10-14T12:00:00Z' })]);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { count: 2 });
  res = await put([answer({ answer: 'Đau thắt lưng bên trái' })]);
  assert.deepEqual(await res.json(), { count: 2 });
  const c = await chart(a);
  assert.deepEqual(c.intake.map((i) => [i.id, i.answer, i.answeredAt]), [
    [`${a}/q2`, 'Khám lưng', '2026-10-14T19:00:00+07:00'],
    [`${a}/q1`, 'Đau thắt lưng bên trái', '2026-10-15T20:00:00+07:00'],
  ]);
  // The same client id on another visit is another row.
  assert.ok(db.prepare("SELECT 1 FROM intake_answer WHERE id = ? AND appointment_id = ?").get(`${a}/q1`, a));

  res = await put([answer({ id: 'x'.repeat(65), channel: 'chat', answer: '', answeredAt: 'hôm qua', question: 'q'.repeat(301) })]);
  assert.equal(res.status, 400);
  assert.deepEqual((await err(res)).fields, ['answers[0].id', 'answers[0].channel', 'answers[0].question', 'answers[0].answer', 'answers[0].answeredAt']);
  assert.equal((await put(Array.from({ length: 51 }, (_, i) => answer({ id: `q${i}` })))).status, 400);
  assert.equal((await put(Array.from({ length: 50 }, (_, i) => answer({ id: `q${i}`, answer: 'đ'.repeat(2000) })))).status, 200);
  assert.equal((await put('x')).status, 400);
});

test('thuốc tự dùng: cần phạm vi self_meds, thay toàn bộ, giới hạn', async () => {
  reset();
  const token = await signIn(ids.phones.p5);
  const a = 'a-p5-old'; // consent covers dose_log only
  let res = await req(`/v1/patient/appointments/${a}/self-meds`, { method: 'PUT', body: { items: [{ name: 'Panadol', how: '' }] }, token });
  assert.equal(res.status, 403);
  assert.equal((await err(res)).code, 'consent_required');

  const put = (items) => req(`/v1/patient/appointments/${ids.appointments.p5}/self-meds`, { method: 'PUT', body: { items }, token });
  res = await put([{ name: 'Panadol 500mg', how: '1 viên khi đau' }, { name: 'Salonpas' }]);
  assert.deepEqual(await res.json(), { count: 2 });
  res = await put([{ name: ' Berberin ', how: '2 viên' }]);
  assert.deepEqual(await res.json(), { count: 1 });
  assert.deepEqual((await chart(ids.appointments.p5)).selfMeds, [{ name: 'Berberin', how: '2 viên' }]);
  res = await put([{ name: '', how: 'x'.repeat(201) }]);
  assert.deepEqual((await err(res)).fields, ['items[0].name', 'items[0].how']);
  assert.equal((await put(Array.from({ length: 31 }, () => ({ name: 'A' })))).status, 400);
});

test('gửi kết quả tạo med_course; sửa kết quả thay thuốc; app ghi liều được', async () => {
  reset();
  const a = ids.appointments.p5;
  const item = (name, days) => ({ name, strength: '10mg', form: 'viên', quantity: days, route: 'Uống', doses: [{ slot: 'morning', amount: 1 }], meal: 'any', days, note: '' });
  const draft = { diagnosis: [['M54.5', 'Đau thắt lưng']], items: [item('Meloxicam', 7), item('Omeprazol', 14)], advice: 'Nghỉ ngơi.' };
  const staffReq = (path, method, body) => req(path, { method, body, cookie: staff });
  assert.equal((await staffReq(`/v1/appointments/${a}/result-draft`, 'PUT', draft)).status, 200);
  const sent = await (await staffReq(`/v1/appointments/${a}/result/send`, 'POST')).json();
  let rows = db.prepare('SELECT * FROM med_course WHERE patient_id = ? AND id LIKE ? ORDER BY id').all('p5', `${a}#%`);
  assert.deepEqual(rows.map((r) => [r.id, JSON.parse(r.item).name, r.prescribed_at]), [
    [`${a}#1`, 'Meloxicam', sent.signedAt], [`${a}#2`, 'Omeprazol', sent.signedAt]]);

  assert.equal((await staffReq(`/v1/appointments/${a}/result/amend`, 'POST', { reason: 'Bỏ Omeprazol' })).status, 201);
  await staffReq(`/v1/appointments/${a}/result-draft`, 'PUT', { ...draft, items: [item('Meloxicam', 5)] });
  await new Promise((r) => setTimeout(r, 1100)); // a later signing time
  const v2 = await (await staffReq(`/v1/appointments/${a}/result/send`, 'POST')).json();
  assert.notEqual(v2.signedAt, sent.signedAt);
  rows = db.prepare('SELECT * FROM med_course WHERE patient_id = ? AND id LIKE ? ORDER BY id').all('p5', `${a}#%`);
  assert.deepEqual(rows.map((r) => [r.id, JSON.parse(r.item).days, r.prescribed_at]), [[`${a}#1`, 5, sent.signedAt]]);

  const token = await signIn(ids.phones.p5);
  const res = await req('/v1/patient/dose-events', {
    method: 'POST', token, body: { events: [{ courseId: `${a}#1`, day: ids.today, slot: 'morning', mark: 'taken', reason: null, at: localIso() }] },
  });
  assert.deepEqual(await res.json(), { accepted: 1, ignored: [] });
  const view = await (await req(`/v1/patient/appointments/${a}/result`, { token })).json();
  assert.equal(view.version, 2);
  assert.equal(view.items[0].days, 5);
});

test('nhật ký liều: cần dose_log, ghi đè theo liều, bỏ qua đợt thuốc không thuộc mình', async () => {
  reset();
  const hoa = await signIn(ids.phones.p3);
  const ev = (over = {}) => ({ courseId: `${ids.appointments.p1}#1`, day: ids.today, slot: 'morning', mark: 'taken', reason: null, at: '2026-10-16T07:05:00+07:00', ...over });
  let res = await req('/v1/patient/dose-events', { method: 'POST', body: { events: [ev()] }, token: hoa });
  assert.equal(res.status, 403);
  assert.equal((await err(res)).code, 'consent_required');

  const token = await signIn(ids.phones.p1);
  const post = (events) => req('/v1/patient/dose-events', { method: 'POST', body: { events }, token });
  const history = `${ids.historyAppointments.p1}#1`;
  const lanCourse = `${ids.historyAppointments.p2}#1`;
  res = await post([ev(), ev({ courseId: history, day: ids.historyDay, mark: 'skipped', reason: 'unwell' }), ev({ courseId: 'v-unknown#1' }),
    ev({ courseId: lanCourse }), ev({ courseId: 'v-unknown#1', slot: 'evening' })]);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { accepted: 2, ignored: ['v-unknown#1', lanCourse] });
  const count = () => db.prepare('SELECT count(*) n FROM dose_event WHERE patient_id = ?').get('p1').n;
  const n = count();
  res = await post([ev({ mark: 'skipped', reason: 'forgot' }), ev({ mark: 'skipped', reason: 'forgot' })]);
  assert.deepEqual(await res.json(), { accepted: 2, ignored: [] });
  assert.equal(count(), n);
  const row = db.prepare('SELECT * FROM dose_event WHERE patient_id = ? AND course_id = ? AND day = ?').get('p1', `${ids.appointments.p1}#1`, ids.today);
  assert.deepEqual([row.mark, row.reason, row.recorded_at], ['skipped', 'forgot', '2026-10-16T07:05:00+07:00']);
  // A reason only goes with a skipped dose.
  await post([ev({ mark: 'taken', reason: 'forgot' })]);
  assert.equal(db.prepare('SELECT reason FROM dose_event WHERE patient_id = ? AND course_id = ? AND day = ?').get('p1', `${ids.appointments.p1}#1`, ids.today).reason, null);

  res = await post([ev({ courseId: '', day: '2026-02-30', slot: 'night', mark: 'maybe', reason: 'lazy', at: 'now' })]);
  assert.equal(res.status, 400);
  assert.deepEqual((await err(res)).fields, ['events[0].courseId', 'events[0].day', 'events[0].slot', 'events[0].mark', 'events[0].reason', 'events[0].at']);
  // 500 events (well over the 16 KiB of other bodies) pass; 501 do not.
  const many = Array.from({ length: 500 }, (_, i) => ev({ courseId: history, day: addDays(ids.historyDay, i % 30), slot: ['morning', 'noon', 'afternoon', 'evening'][Math.floor(i / 30) % 4] }));
  res = await post(many);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).accepted, 500);
  assert.equal((await post([...many, ev()])).status, 400);
  assert.deepEqual(await (await post([])).json(), { accepted: 0, ignored: [] });

  // Withdrawing the only dose_log consent stops uploads.
  assert.equal((await req(`/v1/patient/appointments/${ids.appointments.p1}/consent`, { method: 'DELETE', token })).status, 200);
  res = await post([ev()]);
  assert.equal(res.status, 403);
});

test('giới hạn 60 lần gửi dữ liệu mỗi phút mỗi phiên', async () => {
  reset();
  const token = await signIn(ids.phones.p5);
  const statuses = [];
  for (let i = 0; i < 61; i++) {
    statuses.push((await req(`/v1/patient/appointments/${ids.appointments.p5}/self-meds`, { method: 'PUT', body: { items: [] }, token })).status);
  }
  assert.deepEqual(statuses, [...Array(60).fill(200), 429]);
  reset();
});

test('rút đồng ý hoặc hết hạn: hồ sơ và hàng chờ ẩn dữ liệu chia sẻ, giữ lịch sử', async () => {
  reset();
  const token = await signIn(ids.phones.p2);
  const a = ids.appointments.p2;
  let c = await chart(a);
  assert.equal(c.consent.state, 'shared');
  assert.deepEqual([c.consent.reason, c.consent.revokedAt], [null, null]);
  assert.ok(c.summary && c.intake.length && c.courses.length && c.doseLog.length && c.selfMeds.length);

  const res = await req(`/v1/patient/appointments/${a}/consent`, { method: 'DELETE', token });
  assert.equal(res.status, 200);
  const view = await res.json();
  assert.equal(view.state, 'revoked');
  assert.match(view.revokedAt, /\+07:00$/);
  assert.ok(db.prepare("SELECT 1 FROM audit_event WHERE action = 'consent.revoke' AND appointment_id = ?").get(a));
  // Revoking again changes nothing.
  assert.equal((await (await req(`/v1/patient/appointments/${a}/consent`, { method: 'DELETE', token })).json()).revokedAt, view.revokedAt);

  c = await chart(a);
  assert.equal(c.consent.state, 'declined');
  assert.deepEqual([c.consent.reason, c.consent.revokedAt], ['revoked', view.revokedAt]);
  assert.equal(c.summary, null);
  assert.deepEqual([c.intake, c.courses, c.doseLog, c.selfMeds], [[], [], [], []]);
  assert.equal(c.lastVisit.appointmentId, ids.historyAppointments.p2);
  assert.equal(c.patient.name, 'Phạm Thị Lan');
  let w = await worklistItem(a);
  assert.deepEqual([w.consent, w.consentReason, w.consentRevokedAt, w.hasSummary, w.chiefComplaint, w.flagged], ['declined', 'revoked', view.revokedAt, false, null, false]);
  assert.ok(!('courses' in w) && !('doseLog' in w));
  // Rows stay (deletion is a later step); uploads are refused.
  assert.ok(db.prepare('SELECT count(*) n FROM intake_answer WHERE appointment_id = ?').get(a).n > 0);
  const up = await req(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token,
    body: { answers: [{ id: 'q', channel: 'pre_visit', question: '', answer: 'x', answeredAt: localIso() }] } });
  assert.equal(up.status, 403);

  // Grant again, then let it expire.
  await req(`/v1/patient/appointments/${a}/consent`, { method: 'PUT', body: { scope: ['intake', 'dose_log', 'self_meds'], wordingVersion: 1 }, token });
  assert.ok((await chart(a)).summary);
  db.prepare('UPDATE consent SET expires_at = ? WHERE appointment_id = ? AND revoked_at IS NULL').run(localIso(Date.now() - 1000), a);
  c = await chart(a);
  assert.deepEqual([c.consent.state, c.consent.reason, c.consent.revokedAt], ['declined', 'expired', null]);
  assert.equal(c.summary, null);
  assert.deepEqual([c.intake, c.courses, c.doseLog, c.selfMeds], [[], [], [], []]);
  w = await worklistItem(a);
  assert.deepEqual([w.consent, w.consentReason, w.chiefComplaint], ['declined', 'expired', null]);
  const list = await (await req('/v1/patient/appointments', { token })).json();
  assert.equal(list.find((x) => x.id === a).consent.state, 'expired');
  assert.equal((await req('/v1/patient/dose-events', { method: 'POST', token,
    body: { events: [{ courseId: `${ids.historyAppointments.p2}#1`, day: ids.today, slot: 'morning', mark: 'taken', reason: null, at: localIso() }] } })).status, 403);
  // Seed: Hòa refused (revoked, empty scope); Tùng never answered.
  const hoa = await chart(ids.appointments.p3);
  assert.equal(hoa.consent.reason, 'revoked');
  const p1 = await worklistItem(ids.appointments.p1);
  assert.equal(p1.consentReason, 'revoked'); // revoked in the dose-log test
});
