import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';

import { hashPassword, sessionCookie } from '../src/clinic/auth.js';
import { DEMO_EMAIL, DEMO_PASSWORD, assertSeedPath, seedClinic } from '../src/clinic/seed.js';
import { addDays, at, today as clinicToday } from '../src/clinic/time.js';
import { backendDir } from '../src/config.js';
import { openDatabase } from '../src/db/index.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { config, mockExtractor } from './helpers.js';

const ORIGIN = 'http://localhost:5555';
const lines = [];
let server;
let base;
let db;
let ids;
let webDir;
let tmp;
let cookie;

before(async () => {
  db = openDatabase();
  ids = await seedClinic(db, { today: clinicToday() });
  // A second clinic, to prove scoping.
  db.prepare("INSERT INTO clinic (id, name, phone) VALUES ('c-other', 'Phòng khám Khác', '0911')").run();
  const hash = await hashPassword('other-pass');
  const ins = db.prepare(`INSERT INTO practitioner (id, clinic_id, full_name, title, role, email, password_hash, created_at)
    VALUES (?, 'c-other', ?, 'BS.', 'doctor', ?, ?, '2026-01-01T08:00:00+07:00')`);
  ins.run('pr-other', 'Trần Khác', 'bs.khac@other.test', hash);
  ins.run('pr-lock', 'Lê Khóa', 'bs.khoa@other.test', hash);
  db.prepare(`INSERT INTO patient (id, clinic_id, code, full_name, birth_date, gender)
    VALUES ('p-other', 'c-other', '000001', 'Người Khác', '1970-01-01', 'Nam')`).run();
  db.prepare(`INSERT INTO appointment (id, clinic_id, patient_id, starts_at, status)
    VALUES ('a-other', 'c-other', 'p-other', ?, 'booked')`).run(at(ids.today, '09:00'));

  tmp = mkdtempSync(join(tmpdir(), 'medicapp-web-'));
  webDir = join(tmp, 'build', 'web');
  mkdirSync(join(webDir, 'assets'), { recursive: true });
  writeFileSync(join(webDir, 'index.html'), '<!doctype html><title>web bác sĩ</title>');
  writeFileSync(join(webDir, 'main.dart.js'), 'console.log(1)');
  writeFileSync(join(webDir, 'assets', 'app.wasm'), Buffer.from([0, 97, 115, 109]));
  writeFileSync(join(tmp, 'package.json'), '{"secret":"LEAK"}');
  writeFileSync(join(tmp, 'build', 'package.json'), '{"secret":"LEAK"}');

  server = createApp({
    config: config({ DOCTOR_WEB_DIR: webDir, DOCTOR_WEB_DEV_ORIGIN: ORIGIN }),
    extractor: mockExtractor,
    stt: unavailableStt,
    log: (e, f) => lines.push(JSON.stringify({ e, ...f })),
    db,
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
  cookie = await login(DEMO_EMAIL, DEMO_PASSWORD);
});

after(async () => {
  await new Promise((r) => server.close(r));
  rmSync(tmp, { recursive: true, force: true });
});

const req = (path, { method = 'GET', body, as = cookie, headers = {} } = {}) => fetch(base + path, {
  method,
  redirect: 'manual',
  headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(as ? { cookie: as } : {}), ...headers },
  body: body ? JSON.stringify(body) : undefined,
});

async function login(email, password) {
  const res = await req('/v1/staff/login', { method: 'POST', body: { email, password }, as: null });
  assert.equal(res.status, 200);
  return res.headers.get('set-cookie').split(';')[0];
}

/** medic_core adherenceOf, with clinic time fixed at +07:00. */
const SLOT = { morning: '07:00', noon: '11:30', afternoon: '16:00', evening: '19:00' };
function adherence(course, log, from, days, now) {
  const byKey = new Map(log.map((e) => [`${e.courseId}|${e.day}|${e.slot}`, e]));
  const first = course.prescribedAt.slice(0, 10);
  const last = addDays(first, course.item.days - 1);
  let due = 0;
  let taken = 0;
  for (let i = 0; i < days; i++) {
    const day = addDays(from, i);
    if (day < first || day > last) continue;
    for (const dose of course.item.doses) {
      const t = Date.parse(at(day, SLOT[dose.slot]));
      if (t < Date.parse(course.prescribedAt)) continue;
      const entry = byKey.get(`${course.id}|${day}|${dose.slot}`);
      if (!entry && Date.parse(now) - t < 60 * 60_000) continue;
      due++;
      if (entry?.mark === 'taken') taken++;
    }
  }
  return { due, taken };
}

test('đăng nhập: cookie HttpOnly SameSite=Strict, me, đăng xuất', async () => {
  const res = await req('/v1/staff/login', { method: 'POST', body: { email: 'BS.HA@anbinh.test ', password: DEMO_PASSWORD }, as: null });
  assert.equal(res.status, 200);
  const set = res.headers.get('set-cookie');
  assert.match(set, /^mc_staff=[A-Za-z0-9_-]{43};/);
  assert.match(set, /HttpOnly/);
  assert.match(set, /SameSite=Strict/);
  assert.match(set, /Path=\//);
  assert.doesNotMatch(set, /Secure/);
  assert.match(sessionCookie('x', { secure: true }), /; Secure$/);
  const body = await res.json();
  assert.deepEqual(body.staff, { id: 'pr-ha', name: 'BS. Nguyễn Thu Hà', role: 'doctor' });
  assert.deepEqual(body.clinic, { id: 'c-anbinh', name: 'Phòng khám Đa khoa An Bình', phone: '0900 000 000' });

  const mine = set.split(';')[0];
  assert.equal((await req('/v1/staff/me', { as: mine })).status, 200);
  const out = await req('/v1/staff/logout', { method: 'POST', as: mine });
  assert.equal(out.status, 204);
  assert.match(out.headers.get('set-cookie'), /Max-Age=0/);
  assert.equal((await req('/v1/staff/me', { as: mine })).status, 401);
  assert.ok(!lines.some((l) => l.includes(DEMO_PASSWORD) || l.includes(DEMO_EMAIL) || l.includes(mine.split('=')[1])));
});

test('sai mật khẩu 401, sai 5 lần thì khóa 423 kể cả mật khẩu đúng', async () => {
  const bad = await req('/v1/staff/login', { method: 'POST', body: { email: DEMO_EMAIL, password: 'nope' }, as: null });
  assert.equal(bad.status, 401);
  assert.equal((await bad.json()).error.code, 'bad_credentials');
  assert.equal((await req('/v1/staff/login', { method: 'POST', body: { email: 'ai@do.test', password: 'x' }, as: null })).status, 401);
  // The successful login above resets the counter.
  await login(DEMO_EMAIL, DEMO_PASSWORD);
  assert.equal(db.prepare("SELECT failed_logins n FROM practitioner WHERE id = 'pr-ha'").get().n, 0);

  const statuses = [];
  for (let i = 0; i < 5; i++) {
    statuses.push((await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.khoa@other.test', password: 'wrong' }, as: null })).status);
  }
  assert.deepEqual(statuses, [401, 401, 401, 401, 423]);
  const locked = await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.khoa@other.test', password: 'other-pass' }, as: null });
  assert.equal(locked.status, 423);
  assert.equal((await locked.json()).error.code, 'locked');
  assert.ok(db.prepare("SELECT locked_until FROM practitioner WHERE id = 'pr-lock'").get().locked_until);
});

test('chưa đăng nhập: 401 unauthenticated', async () => {
  for (const path of ['/v1/staff/me', '/v1/clinic/worklist', `/v1/appointments/${ids.appointments.p2}/chart`, '/v1/patients/p2/history']) {
    const res = await req(path, { as: null });
    assert.equal(res.status, 401, path);
    assert.equal((await res.json()).error.code, 'unauthenticated');
  }
  assert.equal((await req('/v1/clinic/worklist', { as: 'mc_staff=forged' })).status, 401);
});

test('hàng chờ: 6 lượt theo giờ, đồng ý chia sẻ quyết định dữ liệu thuốc', async () => {
  const res = await req('/v1/clinic/worklist');
  assert.equal(res.headers.get('cache-control'), 'no-store');
  const body = await res.json();
  assert.equal(body.date, ids.today);
  assert.match(body.now, /\+07:00$/);
  assert.deepEqual(body.items.map((i) => i.time), ['08:00', '08:30', '09:00', '09:30', '10:00', '10:30']);
  assert.deepEqual(body.items.map((i) => i.status), ['done', 'arrived', 'arrived', 'booked', 'booked', 'booked']);
  assert.deepEqual(body.items.map((i) => i.consent), ['shared', 'shared', 'declined', 'shared', 'none', 'shared']);
  assert.deepEqual(body.items.map((i) => i.resultStatus), ['sent', 'none', 'none', 'none', 'none', 'none']);
  assert.deepEqual(body.items.map((i) => i.flagged), [false, false, false, true, false, false]);
  assert.deepEqual(body.items.map((i) => i.chiefComplaint), [
    'Tái khám tăng huyết áp. Huyết áp đo ở nhà sáng nay 138/86.',
    'Đau khớp gối phải khoảng 1 tuần, sưng về đêm.',
    null,
    'Hay mệt và hơi khó thở khi gắng sức, khoảng 3 tuần nay.',
    null,
    'Đau vùng thượng vị sau ăn, kèm ợ chua, khoảng 2 tháng.',
  ]);
  const lan = body.items[1];
  assert.deepEqual(lan.patient, { id: 'p2', code: '000482', name: 'Phạm Thị Lan', age: 78, gender: 'Nữ' });
  assert.equal(lan.kind, 'Khám dịch vụ');
  assert.equal(lan.hasSummary, true);
  assert.equal(lan.courses.length, 2);
  assert.equal(lan.doseLog.length, 60);
  const hoa = body.items[2];
  assert.equal(hoa.hasSummary, false);
  assert.ok(!('doseLog' in hoa) && !('courses' in hoa));
  assert.ok(!('doseLog' in body.items[4]));
  // Ages match the prototype.
  assert.deepEqual(body.items.map((i) => i.patient.age), [52, 78, 49, 34, 61, 45]);
  // Other days and bad dates.
  assert.deepEqual((await (await req(`/v1/clinic/worklist?date=${addDays(ids.today, 1)}`)).json()).items, []);
  assert.equal((await req('/v1/clinic/worklist?date=2026-02-30')).status, 400);
});

test('hồ sơ Phạm Thị Lan: 3 mục tóm tắt có nguồn, thuốc 18/30 và 27/30, ghi audit', async () => {
  const before = db.prepare("SELECT count(*) n FROM audit_event WHERE action = 'chart.view'").get().n;
  const res = await req(`/v1/appointments/${ids.appointments.p2}/chart`);
  assert.equal(res.status, 200);
  const c = await res.json();
  assert.equal(c.appointment.time, '08:30');
  assert.equal(c.patient.insuranceCode, null);
  assert.equal(c.patient.address, 'Số 8 ngõ 25 phố Hoa Sữa, phường An Phú');
  assert.equal(c.patient.weightKg, 52);
  assert.deepEqual(c.patient.conditions, ['Gút (M10)', 'Rối loạn lipid máu (E78)']);
  assert.equal(c.consent.state, 'shared');
  assert.deepEqual(c.consent.scope, ['intake', 'dose_log', 'self_meds']);
  assert.deepEqual(c.period, { from: ids.historyDay, days: 30, now: c.period.now });

  assert.deepEqual(c.summary.sections.map((s) => s.key), ['chief', 'course', 'questions']);
  const intakeIds = new Set(c.intake.map((i) => i.id));
  for (const s of c.summary.sections) {
    assert.ok(s.sources.length > 0);
    for (const id of s.sources) assert.ok(intakeIds.has(id), id);
  }
  assert.equal(c.summary.mode, 'mock');
  assert.equal(c.intake[0].channel, 'booking');
  assert.equal(c.intake[1].question, 'Nặng hơn hay nhẹ hơn?');
  assert.deepEqual(c.selfMeds, [{ name: 'Paracetamol 500mg', how: '1 viên khi đau, khoảng 2 lần/ngày trong 2 ngày qua' }]);

  const [allo, ator] = c.courses;
  assert.equal(allo.id, `${ids.historyAppointments.p2}#1`);
  assert.equal(allo.visitId, ids.historyAppointments.p2);
  assert.equal(allo.item.name, 'Allopurinol');
  assert.deepEqual(allo.item.doses, [{ slot: 'morning', amount: 1 }]);
  assert.deepEqual(ator.item.doses, [{ slot: 'evening', amount: 1 }]);
  assert.deepEqual(adherence(ator, c.doseLog, c.period.from, 30, c.period.now), { due: 30, taken: 18 });
  assert.deepEqual(adherence(allo, c.doseLog, c.period.from, 30, c.period.now), { due: 30, taken: 27 });
  const reasons = c.doseLog.filter((e) => e.courseId === ator.id && e.mark === 'skipped').map((e) => e.reason);
  assert.equal(reasons.filter((r) => r === 'unwell').length, 5);
  assert.equal(reasons.filter((r) => r === 'other').length, 1);

  assert.equal(c.lastVisit.appointmentId, ids.historyAppointments.p2);
  assert.deepEqual(c.lastVisit.diagnosis, [['M10', 'Gút'], ['E78', 'Rối loạn lipid máu']]);
  assert.equal(c.result, null);

  const rows = db.prepare("SELECT * FROM audit_event WHERE action = 'chart.view' ORDER BY id DESC").all();
  assert.equal(rows.length, before + 1);
  assert.equal(rows[0].actor, 'pr-ha');
  assert.equal(rows[0].patient_id, 'p2');
  assert.equal(rows[0].appointment_id, ids.appointments.p2);
  assert.match(rows[0].ip, /127\.0\.0\.1/);
  assert.ok(!lines.some((l) => l.includes('Phạm Thị Lan') || l.includes('gối')));
});

test('hồ sơ khi không chia sẻ: chỉ cột người bệnh và lịch sử', async () => {
  const c = await (await req(`/v1/appointments/${ids.appointments.p3}/chart`)).json();
  assert.equal(c.consent.state, 'declined');
  assert.equal(c.summary, null);
  assert.deepEqual([c.intake, c.courses, c.doseLog, c.selfMeds], [[], [], [], []]);
  assert.equal(c.patient.name, 'Phạm Văn Hòa');
  const p5 = await (await req(`/v1/appointments/${ids.appointments.p5}/chart`)).json();
  assert.equal(p5.consent.state, 'none');
  assert.equal(p5.patient.insuranceCode, '•••• 0458');
  const p1 = await (await req(`/v1/appointments/${ids.appointments.p1}/chart`)).json();
  assert.equal(p1.patient.insuranceCode, '•••• 3921');
  assert.equal(p1.result.items[0].quantity, 28);
  assert.equal(p1.courses.length, 1); // today's prescription starts after the period
  const p4 = await (await req(`/v1/appointments/${ids.appointments.p4}/chart`)).json();
  assert.equal(p4.summary.flags.length, 1);
  assert.ok(p4.intake.some((i) => p4.summary.flags[0].sources.includes(i.id)));
});

test('phản hồi tóm tắt: lưu, ghi audit, kiểm tra giá trị', async () => {
  const sid = ids.summaries.p2;
  const bad = await req(`/v1/summaries/${sid}/feedback`, { method: 'POST', body: { value: 'meh' } });
  assert.equal(bad.status, 400);
  const res = await req(`/v1/summaries/${sid}/feedback`, { method: 'POST', body: { value: 'up' } });
  assert.equal(res.status, 200);
  const { feedback } = await res.json();
  assert.equal(feedback.value, 'up');
  assert.equal(feedback.by, 'BS. Nguyễn Thu Hà');
  const c = await (await req(`/v1/appointments/${ids.appointments.p2}/chart`)).json();
  assert.equal(c.summary.feedback.value, 'up');
  const row = db.prepare("SELECT * FROM audit_event WHERE action = 'summary.feedback' ORDER BY id DESC").get();
  assert.equal(row.actor, 'pr-ha');
  assert.equal(JSON.parse(row.detail).value, 'up');
  assert.equal((await req('/v1/summaries/s-nope/feedback', { method: 'POST', body: { value: 'up' } })).status, 404);
});

test('đến khám và bắt đầu khám theo đúng trạng thái', async () => {
  const p4 = ids.appointments.p4;
  const p5 = ids.appointments.p5;
  let res = await req(`/v1/appointments/${p4}/arrive`, { method: 'POST' });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).appointment.status, 'arrived');
  res = await req(`/v1/appointments/${p4}/arrive`, { method: 'POST' });
  assert.equal(res.status, 409);
  assert.equal((await res.json()).error.code, 'bad_state');
  res = await req(`/v1/appointments/${p4}/start`, { method: 'POST' });
  assert.equal((await res.json()).appointment.status, 'in_progress');
  assert.equal((await req(`/v1/appointments/${p4}/start`, { method: 'POST' })).status, 409);
  // Straight from booked to in progress.
  res = await req(`/v1/appointments/${p5}/start`, { method: 'POST' });
  assert.equal((await res.json()).appointment.status, 'in_progress');
  assert.equal((await req(`/v1/appointments/${ids.appointments.p1}/start`, { method: 'POST' })).status, 409);
  assert.equal((await req('/v1/appointments/a-none/arrive', { method: 'POST' })).status, 404);
});

test('lịch sử khám: kết quả đã gửi, mới nhất trước', async () => {
  const res = await req('/v1/patients/p1/history');
  const list = await res.json();
  assert.equal(list.length, 2);
  assert.equal(list[0].date, ids.today);
  assert.equal(list[0].items[0].quantity, 28);
  assert.equal(list[0].followUpDate, addDays(ids.today, 28));
  assert.equal(list[1].date, ids.historyDay);
  assert.equal(list[1].clinicName, 'Phòng khám Đa khoa An Bình');
  assert.equal(list[1].doctorName, 'BS. Nguyễn Thu Hà');
  assert.equal(list[1].version, 1);
  assert.deepEqual(await (await req('/v1/patients/p3/history')).json(), []);
  assert.equal((await req('/v1/patients/nope/history')).status, 404);
});

test('phòng khám khác: 404 theo cả hai chiều', async () => {
  const other = await login('bs.khac@other.test', 'other-pass');
  for (const path of [`/v1/appointments/${ids.appointments.p2}/chart`, '/v1/patients/p2/history']) {
    const res = await req(path, { as: other });
    assert.equal(res.status, 404, path);
    assert.equal((await res.json()).error.code, 'not_found');
  }
  assert.equal((await req(`/v1/summaries/${ids.summaries.p2}/feedback`, { method: 'POST', body: { value: 'down' }, as: other })).status, 404);
  assert.equal((await req(`/v1/appointments/${ids.appointments.p6}/arrive`, { method: 'POST', as: other })).status, 404);
  const wl = await (await req('/v1/clinic/worklist', { as: other })).json();
  assert.deepEqual(wl.items.map((i) => i.appointmentId), ['a-other']);
  assert.equal((await req('/v1/appointments/a-other/chart')).status, 404);
  assert.equal((await req('/v1/patients/p-other/history')).status, 404);
});

test('phục vụ web bác sĩ: tệp tĩnh, SPA, chặn ra ngoài thư mục', async () => {
  let res = await req('/', { as: null });
  assert.equal(res.status, 302);
  assert.equal(res.headers.get('location'), '/doctor/');
  assert.equal((await req('/doctor', { as: null })).headers.get('location'), '/doctor/');

  res = await req('/doctor/', { as: null });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('content-type'), 'text/html; charset=utf-8');
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(res.headers.get('x-frame-options'), 'DENY');
  assert.match(await res.text(), /web bác sĩ/);

  res = await req('/doctor/main.dart.js', { as: null });
  assert.equal(res.headers.get('content-type'), 'text/javascript; charset=utf-8');
  res = await req('/doctor/assets/app.wasm', { as: null });
  assert.equal(res.headers.get('content-type'), 'application/wasm');

  res = await req('/doctor/patients/p2', { as: null });
  assert.equal(res.status, 200);
  assert.match(await res.text(), /web bác sĩ/);
  assert.equal((await req('/doctor/missing.js', { as: null })).status, 404);

  for (const path of ['/doctor/..%2fpackage.json', '/doctor/..%2f..%2fpackage.json', '/doctor/%2e%2e/%2e%2e/package.json', '/doctor/..%5c..%5cpackage.json']) {
    res = await req(path, { as: null });
    const text = await res.text();
    assert.equal(res.status, 404, path);
    assert.ok(!text.includes('LEAK'), path);
  }
});

test('thiếu bản build: 404 JSON; thiếu cơ sở dữ liệu: 503', async () => {
  const bare = createApp({ config: config({ DOCTOR_WEB_DIR: join(tmp, 'none') }), extractor: mockExtractor, stt: unavailableStt, log: () => {} });
  await new Promise((r) => bare.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${bare.address().port}`;
  try {
    const web = await fetch(`${url}/doctor/`);
    assert.equal(web.status, 404);
    assert.equal((await web.json()).error.code, 'doctor_web_missing');
    const api = await fetch(`${url}/v1/staff/me`);
    assert.equal(api.status, 503);
    assert.equal((await api.json()).error.code, 'clinic_unavailable');
    assert.equal((await fetch(`${url}/health`)).status, 200);
  } finally {
    await new Promise((r) => bare.close(r));
  }
});

test('CORS chỉ cho đúng origin dev, có credentials, không bao giờ *', async () => {
  let res = await req('/v1/staff/login', { method: 'OPTIONS', as: null, headers: { origin: ORIGIN, 'access-control-request-method': 'POST' } });
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-origin'), ORIGIN);
  assert.equal(res.headers.get('access-control-allow-credentials'), 'true');
  assert.match(res.headers.get('access-control-allow-methods'), /POST/);
  assert.equal(res.headers.get('access-control-allow-headers'), 'content-type, authorization');

  res = await req('/v1/clinic/worklist', { headers: { origin: ORIGIN } });
  assert.equal(res.headers.get('access-control-allow-origin'), ORIGIN);

  res = await req('/v1/clinic/worklist', { headers: { origin: 'http://evil.test' } });
  assert.equal(res.headers.get('access-control-allow-origin'), null);
  res = await req('/v1/staff/login', { method: 'OPTIONS', as: null, headers: { origin: 'http://evil.test' } });
  assert.notEqual(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-origin'), null);
});

test('seed chỉ ghi vào backend/data hoặc thư mục tạm', () => {
  assert.ok(assertSeedPath(join(backendDir, 'data', 'clinic.db'), backendDir));
  assert.ok(assertSeedPath(join(tmp, 'x.db'), backendDir));
  assert.throws(() => assertSeedPath(join(backendDir, 'package.json'), backendDir), /backend\/data/);
  assert.throws(() => assertSeedPath(join(backendDir, 'data', '..', 'src', 'x.db'), backendDir), /backend\/data/);
});
