import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { ABSOLUTE_MS, IDLE_MS, createSessionStore, passwordProblem, temporaryPassword } from '../src/clinic/auth.js';
import { ADMIN_EMAIL, DEMO_EMAIL, DEMO_PASSWORD, seedClinic } from '../src/clinic/seed.js';
import { DOCTOR_WEB_CSP } from '../src/clinic/static.js';
import { at, localIso, today as clinicToday } from '../src/clinic/time.js';
import { openDatabase } from '../src/db/index.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { config, mockExtractor } from './helpers.js';

const TEMP = /^[2-9a-hjkmnp-tv-z]{4}-[2-9a-hjkmnp-tv-z]{4}-[2-9a-hjkmnp-tv-z]{4}$/;
const lines = [];
let server;
let base;
let db;
let ids;
let admin;
let doctor;

before(async () => {
  db = openDatabase();
  ids = await seedClinic(db, { today: clinicToday(), claimCode: 'K7MQ-4XR2-9D' });
  server = createApp({
    config: config(), extractor: mockExtractor, stt: unavailableStt, db,
    log: (e, f) => lines.push(JSON.stringify({ e, ...f })),
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
  admin = await login(ADMIN_EMAIL, DEMO_PASSWORD);
  doctor = await login(DEMO_EMAIL, DEMO_PASSWORD);
});
after(() => new Promise((r) => server.close(r)));

const req = (path, { method = 'GET', body, as, url = base } = {}) => fetch(url + path, {
  method,
  headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...(as ? { cookie: as } : {}) },
  body: body !== undefined ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined,
});
const err = async (res) => (await res.json()).error;

async function login(email, password) {
  const res = await req('/v1/staff/login', { method: 'POST', body: { email, password } });
  assert.equal(res.status, 200, email);
  return res.headers.get('set-cookie').split(';')[0];
}

async function createStaff(body) {
  const res = await req('/v1/clinic/staff', { method: 'POST', body, as: admin });
  assert.equal(res.status, 201);
  return res.json();
}

const lastAudit = (action) => db.prepare('SELECT * FROM audit_event WHERE action = ? ORDER BY id DESC').get(action);

test('quy tắc mật khẩu và mật khẩu tạm', () => {
  assert.match(passwordProblem('ngắn'), /ít nhất 10/);
  assert.match(passwordProblem(' BS.HA@anbinh.test ', 'bs.ha@anbinh.test'), /trùng email/);
  assert.match(passwordProblem('x'.repeat(257)), /quá dài/);
  assert.equal(passwordProblem('mot-cau-dai-du', 'bs.ha@anbinh.test'), null);
  const seen = new Set();
  for (let i = 0; i < 50; i++) {
    const p = temporaryPassword();
    assert.match(p, TEMP);
    seen.add(p);
  }
  assert.equal(seen.size, 50);
});

test('GET /v1/staff/session: 200 null khi chưa đăng nhập, như me khi đã đăng nhập', async () => {
  const out = await req('/v1/staff/session');
  assert.equal(out.status, 200);
  assert.equal(await out.json(), null);
  assert.equal(await (await req('/v1/staff/session', { as: 'mc_staff=forged' })).json(), null);
  const me = await (await req('/v1/staff/me', { as: doctor })).json();
  assert.deepEqual(await (await req('/v1/staff/session', { as: doctor })).json(), me);
});

test('quản trị: đăng nhập, không xem hồ sơ; bác sĩ không vào trang quản trị', async () => {
  const me = await (await req('/v1/staff/me', { as: admin })).json();
  assert.deepEqual(me.staff, { id: 'pr-admin', name: 'Quản trị An Bình', role: 'admin', mustChangePassword: false });
  for (const path of ['/v1/clinic/worklist', `/v1/appointments/${ids.appointments.p2}/chart`, '/v1/patients/p2/history', '/v1/clinic/catalog']) {
    const res = await req(path, { as: admin });
    assert.equal(res.status, 403, path);
    assert.equal((await err(res)).code, 'forbidden');
  }
  assert.equal((await req(`/v1/appointments/${ids.appointments.p2}/result-draft`, { method: 'PUT', body: {}, as: admin })).status, 403);
  for (const path of ['/v1/clinic/staff', '/v1/clinic/pilot-metrics']) {
    const res = await req(path, { as: doctor });
    assert.equal(res.status, 403, path);
    assert.equal((await err(res)).code, 'forbidden');
  }
  assert.equal((await req('/v1/clinic/staff', { method: 'POST', body: { email: 'x@y.test', fullName: 'X', role: 'admin' }, as: doctor })).status, 403);
  assert.equal((await req(`/v1/clinic/staff/${ids.doctorId}/deactivate`, { method: 'POST', as: doctor })).status, 403);
  assert.equal((await req('/v1/clinic/staff', { as: null })).status, 401);
});

test('tạo tài khoản: kiểm tra dữ liệu, mật khẩu tạm chỉ trả một lần, ghi audit', async () => {
  let res = await req('/v1/clinic/staff', { method: 'POST', body: { email: 'khong-phai-email', fullName: '', role: 'nurse' }, as: admin });
  assert.equal(res.status, 422);
  assert.deepEqual((await err(res)).fields, ['email', 'fullName', 'role']);
  res = await req('/v1/clinic/staff', { method: 'POST', body: { email: 'BS.HA@anbinh.test', fullName: 'Trùng', role: 'doctor' }, as: admin });
  assert.equal(res.status, 409);
  assert.equal((await err(res)).code, 'email_taken');

  const { staff, temporaryPassword: temp } = await createStaff({ email: ' BS.Nam@AnBinh.test', fullName: 'Lê Văn Nam', role: 'doctor', licenseNo: '0012/HN-CCHN' });
  assert.match(temp, TEMP);
  assert.equal(staff.email, 'bs.nam@anbinh.test');
  assert.equal(staff.name, 'BS. Lê Văn Nam');
  assert.equal(staff.role, 'doctor');
  assert.equal(staff.mustChangePassword, true);
  assert.equal(staff.active, true);
  assert.ok(!('password_hash' in staff) && !('passwordHash' in staff));

  const list = await (await req('/v1/clinic/staff', { as: admin })).json();
  assert.deepEqual(list.map((s) => s.email).sort(), ['bs.ha@anbinh.test', 'bs.nam@anbinh.test', 'quantri@anbinh.test']);
  assert.ok(!JSON.stringify(list).includes(temp));
  assert.ok(list.find((s) => s.email === 'bs.ha@anbinh.test').lastLoginAt);

  const row = lastAudit('staff.create');
  assert.equal(row.actor, 'pr-admin');
  assert.deepEqual(JSON.parse(row.detail), { staffId: staff.id, role: 'doctor' });
  assert.equal(row.patient_id, null);
  assert.ok(lastAudit('staff.list'));
  assert.ok(!lines.some((l) => l.includes(temp) || l.includes('bs.nam')));
});

test('mật khẩu tạm: phải đổi trước khi làm gì khác; đổi xong phiên khác kết thúc', async () => {
  const { staff, temporaryPassword: temp } = await createStaff({ email: 'bs.lan@anbinh.test', fullName: 'Phan Lan', role: 'doctor' });
  const res = await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.lan@anbinh.test', password: temp } });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).staff.mustChangePassword, true);
  const one = res.headers.get('set-cookie').split(';')[0];
  const two = await login('bs.lan@anbinh.test', temp);

  let r = await req('/v1/clinic/worklist', { as: one });
  assert.equal(r.status, 403);
  assert.equal((await err(r)).code, 'password_change_required');
  assert.equal((await req(`/v1/patients/p2/access-log`, { as: one })).status, 403);
  assert.equal((await req('/v1/staff/me', { as: one })).status, 200);

  const change = (body, as = two) => req('/v1/staff/password', { method: 'POST', body, as });
  r = await change({ currentPassword: temp, newPassword: 'ngan' });
  assert.equal(r.status, 422);
  assert.equal((await err(r)).code, 'weak_password');
  r = await change({ currentPassword: temp, newPassword: 'BS.LAN@anbinh.test' });
  assert.match((await err(r)).message, /trùng email/);
  r = await change({ currentPassword: temp, newPassword: temp });
  assert.match((await err(r)).message, /khác mật khẩu hiện tại/);
  r = await change({ currentPassword: 'sai-mat-khau-roi', newPassword: 'mat-khau-moi-cua-lan' });
  assert.equal(r.status, 400);
  assert.equal((await err(r)).code, 'wrong_password');

  r = await change({ currentPassword: temp, newPassword: 'mat-khau-moi-cua-lan' });
  assert.equal(r.status, 200);
  assert.equal((await r.json()).staff.mustChangePassword, false);
  assert.equal((await req('/v1/clinic/worklist', { as: two })).status, 200);
  assert.equal((await req('/v1/staff/me', { as: one })).status, 401); // the other session ended
  assert.equal((await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.lan@anbinh.test', password: temp } })).status, 401);
  await login('bs.lan@anbinh.test', 'mat-khau-moi-cua-lan');
  const row = lastAudit('staff.password_change');
  assert.equal(row.actor, staff.id);
  assert.deepEqual(JSON.parse(row.detail), { sessionsEnded: 1, wasTemporary: true });
  assert.ok(!lines.some((l) => l.includes('mat-khau-moi-cua-lan')));
});

test('khóa tài khoản: phiên kết thúc ngay, không đăng nhập được; mở lại thì được', async () => {
  const { staff, temporaryPassword: temp } = await createStaff({ email: 'bs.khoa@anbinh.test', fullName: 'Lý Khóa', role: 'doctor' });
  const cookie = await login('bs.khoa@anbinh.test', temp);
  assert.equal((await req('/v1/staff/me', { as: cookie })).status, 200);

  let r = await req(`/v1/clinic/staff/${staff.id}/deactivate`, { method: 'POST', as: admin });
  assert.equal(r.status, 200);
  assert.equal((await r.json()).staff.active, false);
  assert.equal((await req('/v1/staff/me', { as: cookie })).status, 401);
  r = await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.khoa@anbinh.test', password: temp } });
  assert.equal(r.status, 403);
  assert.equal((await err(r)).code, 'account_disabled');
  r = await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.khoa@anbinh.test', password: 'sai-mat-khau' } });
  assert.equal(r.status, 401); // a wrong password says nothing about the account
  assert.deepEqual(JSON.parse(lastAudit('staff.deactivate').detail), { staffId: staff.id, sessionsEnded: 1 });

  r = await req(`/v1/clinic/staff/${ids.adminId}/deactivate`, { method: 'POST', as: admin });
  assert.equal(r.status, 409);
  assert.equal((await err(r)).code, 'self');
  assert.equal((await req('/v1/clinic/staff/pr-none/deactivate', { method: 'POST', as: admin })).status, 404);

  r = await req(`/v1/clinic/staff/${staff.id}/reactivate`, { method: 'POST', as: admin });
  assert.equal((await r.json()).staff.active, true);
  assert.ok(lastAudit('staff.reactivate'));
  await login('bs.khoa@anbinh.test', temp);
});

test('đặt lại mật khẩu: mật khẩu tạm mới, mở khóa, phiên cũ kết thúc', async () => {
  const { staff, temporaryPassword: first } = await createStaff({ email: 'bs.quen@anbinh.test', fullName: 'Hồ Quên', role: 'admin' });
  assert.equal(staff.name, 'Hồ Quên'); // no title for an admin
  const cookie = await login('bs.quen@anbinh.test', first);
  for (let i = 0; i < 5; i++) await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.quen@anbinh.test', password: 'sai-mat-khau' } });
  assert.equal((await (await req('/v1/clinic/staff', { as: admin })).json()).find((s) => s.id === staff.id).locked, true);

  const r = await req(`/v1/clinic/staff/${staff.id}/reset-password`, { method: 'POST', as: admin });
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.match(body.temporaryPassword, TEMP);
  assert.notEqual(body.temporaryPassword, first);
  assert.equal(body.staff.locked, false);
  assert.equal(body.staff.mustChangePassword, true);
  assert.equal((await req('/v1/staff/me', { as: cookie })).status, 401);
  assert.equal((await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.quen@anbinh.test', password: first } })).status, 401);
  await login('bs.quen@anbinh.test', body.temporaryPassword);
  assert.equal(JSON.parse(lastAudit('staff.reset_password').detail).staffId, staff.id);
  assert.equal((await req(`/v1/clinic/staff/${ids.adminId}/reset-password`, { method: 'POST', as: admin })).status, 409);
});

test('khóa 15 phút sau 5 lần sai, hết khóa thì đăng nhập lại được; đổi mật khẩu sai 5 lần cũng khóa', async () => {
  const { temporaryPassword: temp, staff } = await createStaff({ email: 'bs.sai@anbinh.test', fullName: 'Sai Nhiều', role: 'doctor' });
  const statuses = [];
  for (let i = 0; i < 5; i++) {
    statuses.push((await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.sai@anbinh.test', password: 'khong-dung' } })).status);
  }
  assert.deepEqual(statuses, [401, 401, 401, 401, 423]);
  assert.equal((await req('/v1/staff/login', { method: 'POST', body: { email: 'bs.sai@anbinh.test', password: temp } })).status, 423);
  const until = Date.parse(db.prepare('SELECT locked_until FROM practitioner WHERE id = ?').get(staff.id).locked_until);
  assert.ok(Math.abs(until - Date.now() - 15 * 60_000) < 10_000);
  // 15 minutes later.
  db.prepare('UPDATE practitioner SET locked_until = ? WHERE id = ?').run(localIso(Date.now() - 1000), staff.id);
  const cookie = await login('bs.sai@anbinh.test', temp);

  const results = [];
  for (let i = 0; i < 5; i++) {
    results.push((await req('/v1/staff/password', { method: 'POST', body: { currentPassword: 'khong-dung', newPassword: 'mat-khau-moi-dai-du' }, as: cookie })).status);
  }
  assert.deepEqual(results, [400, 400, 400, 400, 423]);
  assert.equal((await req('/v1/staff/me', { as: cookie })).status, 401);
});

test('phiên: 30 phút không thao tác hoặc 12 giờ thì hết', () => {
  let t = 1_000_000;
  const store = createSessionStore({ now: () => t });
  try {
    const token = store.create({ id: 'pr-x', clinic_id: 'c' });
    t += IDLE_MS - 1000;
    assert.ok(store.get(token)); // sliding
    t += IDLE_MS - 1000;
    assert.ok(store.get(token));
    t += IDLE_MS;
    assert.equal(store.get(token), null);

    const busy = store.create({ id: 'pr-x', clinic_id: 'c' });
    const start = t;
    while (t - start < ABSOLUTE_MS - 20 * 60_000) {
      t += 20 * 60_000;
      assert.ok(store.get(busy));
    }
    t = start + ABSOLUTE_MS;
    assert.equal(store.get(busy), null);

    const a = store.create({ id: 'pr-y', clinic_id: 'c' });
    const b = store.create({ id: 'pr-y', clinic_id: 'c' });
    assert.equal(store.endFor('pr-y', b), 1);
    assert.equal(store.get(a), null);
    assert.ok(store.get(b));
  } finally {
    store.close();
  }
});

test('nhật ký truy cập: ai, làm gì, lúc nào, lượt khám nào; phân trang; bác sĩ và quản trị', async () => {
  await req(`/v1/appointments/${ids.appointments.p2}/chart`, { as: doctor });
  await req('/v1/patients/p2/history', { as: doctor });
  db.prepare(`INSERT INTO audit_event (at, actor, action, patient_id, appointment_id, detail, ip)
    VALUES (?, 'patient', 'consent.grant', 'p2', ?, '{"scope":["intake"]}', '10.0.0.9')`).run(localIso(Date.now() - 60_000), ids.appointments.p2);

  const res = await req('/v1/patients/p2/access-log', { as: doctor });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('cache-control'), 'no-store');
  const log = await res.json();
  assert.deepEqual(log.patient, { id: 'p2', code: '000482', name: 'Phạm Thị Lan' });
  const [first, ...rest] = log.items;
  assert.equal(first.action, 'access_log.view'); // reading the log is logged too
  assert.equal(first.actor.name, 'BS. Nguyễn Thu Hà');
  const chart = rest.find((e) => e.action === 'chart.view');
  assert.equal(chart.label, 'Mở hồ sơ lượt khám');
  assert.deepEqual(chart.actor, { kind: 'staff', name: 'BS. Nguyễn Thu Hà', role: 'doctor' });
  assert.equal(chart.appointmentId, ids.appointments.p2);
  assert.equal(chart.visitDate, ids.today);
  assert.match(chart.at, /\+07:00$/);
  assert.equal(rest.find((e) => e.action === 'history.view').visitDate, null);
  const grant = rest.find((e) => e.action === 'consent.grant');
  assert.deepEqual(grant.actor, { kind: 'patient', name: 'Người bệnh' });
  assert.equal(grant.label, 'Đồng ý chia sẻ dữ liệu');
  const text = JSON.stringify(log);
  assert.ok(!text.includes('10.0.0.9') && !text.includes('scope'));
  for (let i = 1; i < log.items.length; i++) assert.ok(log.items[i - 1].at >= log.items[i].at);

  const page = await (await req('/v1/patients/p2/access-log?limit=2&offset=1', { as: doctor })).json();
  assert.equal(page.items.length, 2);
  assert.equal(page.offset, 1);
  assert.equal(page.nextOffset, 3);
  assert.equal(page.total, log.total + 1);
  const end = await (await req(`/v1/patients/p2/access-log?offset=${page.total - 1}`, { as: doctor })).json();
  assert.equal(end.nextOffset, null);
  for (const q of ['limit=0', 'limit=101', 'offset=-1', 'limit=abc']) {
    assert.equal((await req(`/v1/patients/p2/access-log?${q}`, { as: doctor })).status, 400, q);
  }

  const byCode = await req('/v1/clinic/access-log?patientCode=000482&limit=5', { as: admin });
  assert.equal(byCode.status, 200);
  const adminView = await byCode.json();
  assert.equal(adminView.patient.id, 'p2');
  assert.deepEqual(adminView.items[0].actor, { kind: 'staff', name: 'Quản trị An Bình', role: 'admin' });
  assert.equal((await req('/v1/patients/p2/access-log', { as: admin })).status, 200);
  assert.equal((await req('/v1/clinic/access-log?patientCode=999999', { as: admin })).status, 404);
  assert.equal((await req('/v1/clinic/access-log', { as: admin })).status, 404);
  assert.equal((await req('/v1/patients/nope/access-log', { as: doctor })).status, 404);
  assert.equal((await req('/v1/patients/p2/access-log', { as: null })).status, 401);
});

test('số liệu chạy thử: tóm tắt, tỷ lệ Đúng, thời gian tới khi người bệnh nhận, đơn phải sửa', async () => {
  // Doctor feedback: one "Đúng", one "Chưa đúng".
  await req(`/v1/summaries/${ids.summaries.p2}/feedback`, { method: 'POST', body: { value: 'up' }, as: doctor });
  await req(`/v1/summaries/${ids.summaries.p4}/feedback`, { method: 'POST', body: { value: 'down' }, as: doctor });
  // Bà Lan's result of 30 days ago (sent 06:30) seen in the app at 09:30, then again later.
  const h = ids.historyAppointments.p2;
  const view = db.prepare(`INSERT INTO audit_event (at, actor, action, patient_id, appointment_id, detail)
    VALUES (?, 'patient', 'result.view', 'p2', ?, '{}')`);
  view.run(at(ids.historyDay, '09:30'), h);
  view.run(at(ids.historyDay, '11:00'), h);
  // Ông Minh's result of today is amended and sent again.
  const p1 = ids.appointments.p1;
  assert.equal((await req(`/v1/appointments/${p1}/result/amend`, { method: 'POST', body: { reason: 'Sửa số lượng' }, as: doctor })).status, 201);
  assert.equal((await req(`/v1/appointments/${p1}/result/send`, { method: 'POST', as: doctor })).status, 200);

  const res = await req(`/v1/clinic/pilot-metrics?from=${ids.historyDay}&to=${ids.today}`, { as: admin });
  assert.equal(res.status, 200);
  const m = await res.json();
  assert.equal(m.from, ids.historyDay);
  assert.equal(m.to, ids.today);
  assert.deepEqual(m.totals, {
    visits: 8, withSummary: 4, summaries: 4, feedbackUp: 1, feedbackDown: 1, upRate: 0.5,
    sent: 3, received: 1, amended: 1, medianMinutes: 180, p90Minutes: 180,
  });
  assert.deepEqual(m.days.map((d) => [d.date, d.visits, d.sent, d.received, d.medianMinutes]), [
    [ids.historyDay, 2, 2, 1, 180],
    [ids.today, 6, 1, 0, null],
  ]);
  assert.equal(m.days[1].upRate, 0.5);
  assert.equal(m.days[0].upRate, null);
  assert.deepEqual(JSON.parse(lastAudit('pilot_metrics.view').detail), { from: ids.historyDay, to: ids.today });

  // Default: the last 30 days up to today.
  const d = await (await req('/v1/clinic/pilot-metrics', { as: admin })).json();
  assert.equal(d.to, ids.today);
  assert.equal(d.totals.visits, 6);
  for (const q of ['from=2026-02-30', `from=${ids.today}&to=${ids.historyDay}`, 'from=2024-01-01&to=2026-01-01']) {
    assert.equal((await req(`/v1/clinic/pilot-metrics?${q}`, { as: admin })).status, 400, q);
  }
});

test('header bảo mật trên mọi phản hồi, no-store cho API, HSTS khi HTTPS=1, giới hạn thân', async () => {
  for (const path of ['/v1/staff/me', '/health', '/v1/clinic/worklist', '/nope']) {
    const res = await req(path, { as: doctor });
    assert.equal(res.headers.get('cache-control'), 'no-store', path);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff', path);
    assert.equal(res.headers.get('x-frame-options'), 'DENY', path);
    assert.equal(res.headers.get('referrer-policy'), 'no-referrer', path);
    assert.match(res.headers.get('content-security-policy'), /default-src 'none'/, path);
    assert.equal(res.headers.get('strict-transport-security'), null, path);
  }
  const logout = await req('/v1/staff/logout', { method: 'POST' });
  assert.equal(logout.headers.get('cache-control'), 'no-store');
  assert.equal(logout.headers.get('x-frame-options'), 'DENY');
  assert.match(DOCTOR_WEB_CSP, /script-src 'self' 'wasm-unsafe-eval'/);
  assert.doesNotMatch(DOCTOR_WEB_CSP, /unsafe-eval'(?<!wasm-unsafe-eval')|https?:/);

  const secure = createApp({ config: config({ HTTPS: '1' }), extractor: mockExtractor, stt: unavailableStt, log: () => {}, db });
  await new Promise((r) => secure.listen(0, '127.0.0.1', r));
  try {
    const url = `http://127.0.0.1:${secure.address().port}`;
    const res = await req('/health', { url });
    assert.match(res.headers.get('strict-transport-security'), /max-age=31536000/);
    const login = await req('/v1/staff/login', { method: 'POST', body: { email: DEMO_EMAIL, password: DEMO_PASSWORD }, url });
    assert.match(login.headers.get('set-cookie'), /; Secure/);
  } finally {
    await new Promise((r) => secure.close(r));
  }

  const big = await req('/v1/staff/login', { method: 'POST', body: JSON.stringify({ email: 'a@b.c', password: 'x'.repeat(17 * 1024) }) });
  assert.equal(big.status, 413);
  assert.equal((await err(big)).code, 'too_large');
});
