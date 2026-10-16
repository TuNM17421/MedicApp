import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { hashPassword } from '../src/clinic/auth.js';
import { formatClaimCode, newClaimCode, normalizeClaimCode } from '../src/clinic/prescription.js';
import { DEMO_EMAIL, DEMO_PASSWORD, seedClinic } from '../src/clinic/seed.js';
import { addDays, at, today as clinicToday } from '../src/clinic/time.js';
import { openDatabase } from '../src/db/index.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { config, mockExtractor } from './helpers.js';

const CLAIM = 'K7MQ-4XR2-9D';
const CODE_RE = /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{2}$/;
let server;
let base;
let db;
let ids;
let cookie;
let other;

before(async () => {
  db = openDatabase();
  ids = await seedClinic(db, { today: clinicToday(), claimCode: CLAIM.toLowerCase() });
  db.prepare("INSERT INTO clinic (id, name, phone) VALUES ('c-other', 'Phòng khám Khác', '0911')").run();
  db.prepare(`INSERT INTO practitioner (id, clinic_id, full_name, title, role, email, password_hash, created_at)
    VALUES ('pr-other', 'c-other', 'Trần Khác', 'BS.', 'doctor', 'bs.khac@other.test', ?, '2026-01-01T08:00:00+07:00')`)
    .run(await hashPassword('other-pass'));
  server = createApp({ config: config(), extractor: mockExtractor, stt: unavailableStt, log: () => {}, db });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
  cookie = await login(DEMO_EMAIL, DEMO_PASSWORD);
  other = await login('bs.khac@other.test', 'other-pass');
});
after(() => new Promise((r) => server.close(r)));

const req = (path, { method = 'GET', body, as = cookie } = {}) => fetch(base + path, {
  method,
  headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(as ? { cookie: as } : {}) },
  body: body ? JSON.stringify(body) : undefined,
});

async function login(email, password) {
  const res = await req('/v1/staff/login', { method: 'POST', body: { email, password }, as: null });
  assert.equal(res.status, 200);
  return res.headers.get('set-cookie').split(';')[0];
}

const item = (over = {}) => ({
  name: 'Colchicin', strength: '1mg', form: 'viên', quantity: 10, route: 'Uống',
  doses: [{ slot: 'evening', amount: 1 }, { slot: 'morning', amount: 0.5 }], meal: 'after', days: 7, note: '', ...over,
});
const full = {
  diagnosis: [['M10', 'Gút'], ['E78', 'Rối loạn lipid máu']],
  items: [item()],
  advice: 'Uống đủ 2 lít nước mỗi ngày.\n\nHạn chế bia rượu.',
  followUpDate: '2026-11-13',
  internalNote: 'Theo dõi acid uric.',
};

test('mã nhận kết quả: Crockford, chuẩn hóa chữ thường và dấu gạch', () => {
  for (let i = 0; i < 50; i++) assert.match(formatClaimCode(newClaimCode()), CODE_RE);
  assert.equal(normalizeClaimCode(' k7mq-4xr2-9d '), 'K7MQ4XR29D');
  assert.equal(normalizeClaimCode('K7MQ-4XR2-9o'), 'K7MQ4XR290');
  assert.equal(normalizeClaimCode('K7MQ-4XR2-9U'), null);
  assert.equal(normalizeClaimCode('K7MQ'), null);
  assert.equal(ids.claimCodes.p1, CLAIM);
});

test('danh mục mẫu có đủ thuốc và ICD-10 của bản bấm thử', async () => {
  const res = await req('/v1/clinic/catalog');
  assert.equal(res.status, 200);
  const { drugs, icd10 } = await res.json();
  assert.ok(drugs.length >= 40 && icd10.length >= 40);
  const titles = new Set(drugs.map((d) => `${d.name} ${d.strength}`));
  for (const t of ['Allopurinol 300mg', 'Atorvastatin 10mg', 'Atorvastatin 20mg', 'Colchicin 1mg', 'Meloxicam 7,5mg', 'Paracetamol 500mg',
    'Amlodipin 5mg', 'Losartan 50mg', 'Metformin 500mg', 'Omeprazol 20mg', 'Esomeprazol 20mg', 'Glucosamin 500mg', 'Diclofenac gel 1%']) {
    assert.ok(titles.has(t), t);
  }
  for (const d of drugs) assert.deepEqual(Object.keys(d), ['name', 'strength', 'form', 'route']);
  const codes = new Map(icd10);
  for (const [c, n] of [['M10', 'Gút'], ['E78', 'Rối loạn lipid máu'], ['M17', 'Thoái hóa khớp gối'], ['M25.5', 'Đau khớp'],
    ['I10', 'Tăng huyết áp vô căn'], ['E11', 'Đái tháo đường type 2'], ['K21', 'Bệnh trào ngược dạ dày thực quản'],
    ['K29', 'Viêm dạ dày và tá tràng'], ['R06.0', 'Khó thở'], ['R07.4', 'Đau ngực, không đặc hiệu'], ['R53', 'Mệt mỏi']]) {
    assert.equal(codes.get(c), n, c);
  }
});

test('chưa đăng nhập: 401 cho các giao diện kết quả', async () => {
  const a = ids.appointments.p2;
  for (const [method, path] of [['GET', '/v1/clinic/catalog'], ['GET', `/v1/appointments/${a}/result`],
    ['PUT', `/v1/appointments/${a}/result-draft`], ['POST', `/v1/appointments/${a}/result/send`], ['POST', `/v1/appointments/${a}/result/amend`]]) {
    const res = await req(path, { method, as: null, body: method === 'GET' ? undefined : {} });
    assert.equal(res.status, 401, path);
  }
});

test('bản nháp: tạo, ghi đè, kiểm tra kiểu dữ liệu', async () => {
  const a = ids.appointments.p2;
  assert.equal(await (await req(`/v1/appointments/${a}/result`)).json(), null);
  let res = await req(`/v1/appointments/${a}/result-draft`, { method: 'PUT', body: { diagnosis: [['m10', 'Gút']], items: [{ name: 'Colchicin' }] } });
  assert.equal(res.status, 200);
  const first = await res.json();
  assert.equal(first.version, 1);
  assert.equal(first.status, 'draft');
  assert.deepEqual(first.diagnosis, [['M10', 'Gút']]);
  assert.deepEqual(first.items[0], { name: 'Colchicin', strength: '', form: 'viên', quantity: 0, route: 'Uống', doses: [], meal: 'any', days: 0, note: '' });
  assert.equal(first.claimCode, null);
  assert.equal(first.signedBy, null);

  res = await req(`/v1/appointments/${a}/result-draft`, { method: 'PUT', body: { ...full, items: [item({ quantity: undefined })] } });
  const second = await res.json();
  assert.equal(second.id, first.id);
  assert.equal(second.version, 1);
  assert.equal(second.advice, full.advice);
  assert.deepEqual(second.items[0].doses, [{ slot: 'morning', amount: 0.5 }, { slot: 'evening', amount: 1 }]);
  assert.equal(db.prepare('SELECT count(*) n FROM visit_result WHERE appointment_id = ?').get(a).n, 1);

  res = await req(`/v1/appointments/${a}/result-draft`, {
    method: 'PUT',
    body: { diagnosis: 'Gút', items: [item({ quantity: 1.5, doses: [{ slot: 'morning', amount: 1 }, { slot: 'morning', amount: 1 }], meal: 'sometimes' })], followUpDate: '13/11/2026' },
  });
  assert.equal(res.status, 400);
  const err = (await res.json()).error;
  assert.equal(err.code, 'bad_draft');
  assert.deepEqual(err.fields.sort(), ['diagnosis', 'followUpDate', 'items[0].doses[1]', 'items[0].meal', 'items[0].quantity'].sort());
  res = await req(`/v1/appointments/${a}/result-draft`, { method: 'PUT', body: { items: Array.from({ length: 21 }, () => item()) } });
  assert.equal(res.status, 400);
  res = await req(`/v1/appointments/${a}/result-draft`, { method: 'PUT', body: { advice: 'x'.repeat(2001) } });
  assert.equal(res.status, 400);

  const wl = await (await req('/v1/clinic/worklist')).json();
  assert.equal(wl.items.find((i) => i.appointmentId === a).resultStatus, 'draft');
  const chart = await (await req(`/v1/appointments/${a}/chart`)).json();
  assert.equal(chart.appointment.resultStatus, 'draft');
  assert.equal(chart.result.status, 'draft');
});

test('gửi: thiếu trường thì 422 kèm fields', async () => {
  const a = ids.appointments.p2;
  await req(`/v1/appointments/${a}/result-draft`, {
    method: 'PUT', body: { diagnosis: [], items: [item({ name: '', quantity: 0, doses: [{ slot: 'noon', amount: 0 }], days: 0 })] },
  });
  const res = await req(`/v1/appointments/${a}/result/send`, { method: 'POST' });
  assert.equal(res.status, 422);
  const err = (await res.json()).error;
  assert.equal(err.code, 'incomplete');
  assert.deepEqual(err.fields, ['diagnosis', 'items[0].name', 'items[0].quantity', 'items[0].doses', 'items[0].days']);
  assert.equal((await req(`/v1/appointments/${ids.appointments.p6}/result/send`, { method: 'POST' })).status, 409);
});

test('gửi: ký, tạo mã, lượt khám xong, ghi audit; sau đó không sửa được', async () => {
  const a = ids.appointments.p2;
  await req(`/v1/appointments/${a}/result-draft`, { method: 'PUT', body: full });
  const res = await req(`/v1/appointments/${a}/result/send`, { method: 'POST' });
  assert.equal(res.status, 200);
  const sent = await res.json();
  assert.equal(sent.status, 'sent');
  assert.equal(sent.signedBy, 'BS. Nguyễn Thu Hà');
  assert.match(sent.signedAt, /\+07:00$/);
  assert.match(sent.claimCode, CODE_RE);
  const row = db.prepare('SELECT claim_code, claim_expires_at, status FROM appointment WHERE id = ?').get(a);
  assert.equal(row.status, 'done');
  assert.equal(formatClaimCode(row.claim_code), sent.claimCode);
  assert.equal(row.claim_expires_at.slice(0, 10), addDays(clinicToday(), 30));
  const audit = db.prepare("SELECT * FROM audit_event WHERE action = 'result.send' ORDER BY id DESC").get();
  assert.equal(audit.actor, 'pr-ha');
  assert.equal(audit.appointment_id, a);

  const wl = await (await req('/v1/clinic/worklist')).json();
  const entry = wl.items.find((i) => i.appointmentId === a);
  assert.deepEqual([entry.status, entry.resultStatus], ['done', 'sent']);
  const chart = await (await req(`/v1/appointments/${a}/chart`)).json();
  assert.equal(chart.result.claimCode, sent.claimCode);

  let again = await req(`/v1/appointments/${a}/result-draft`, { method: 'PUT', body: full });
  assert.equal(again.status, 409);
  assert.equal((await again.json()).error.code, 'result_sent');
  again = await req(`/v1/appointments/${a}/result/send`, { method: 'POST' });
  assert.equal(again.status, 409);
});

test('sửa kết quả: bản 2 nháp, gửi thì bản 1 thành amended, cùng mã', async () => {
  const a = ids.appointments.p2;
  const code = (await (await req(`/v1/appointments/${a}/result`)).json()).claimCode;
  let res = await req(`/v1/appointments/${a}/result/amend`, { method: 'POST', body: { reason: '  ' } });
  assert.equal(res.status, 422);
  assert.deepEqual((await res.json()).error.fields, ['reason']);
  res = await req(`/v1/appointments/${a}/result/amend`, { method: 'POST', body: { reason: 'Sửa liều Colchicin' } });
  assert.equal(res.status, 201);
  const v2 = await res.json();
  assert.deepEqual([v2.version, v2.status, v2.amendReason, v2.signedBy], [2, 'draft', 'Sửa liều Colchicin', null]);
  assert.deepEqual(v2.items, (await (await req(`/v1/appointments/${a}/chart`)).json()).result.items);
  assert.equal((await req(`/v1/appointments/${a}/result/amend`, { method: 'POST', body: { reason: 'x' } })).status, 409);

  // While v2 is open, the patient and the history still see v1.
  const chart = await (await req(`/v1/appointments/${a}/chart`)).json();
  assert.equal(chart.appointment.resultStatus, 'draft');
  let hist = await (await req('/v1/patients/p2/history')).json();
  assert.equal(hist.filter((h) => h.appointmentId === a).length, 1);
  assert.equal(hist[0].version, 1);

  await req(`/v1/appointments/${a}/result-draft`, { method: 'PUT', body: { ...full, items: [item({ quantity: 14, days: 14 })] } });
  res = await req(`/v1/appointments/${a}/result/send`, { method: 'POST' });
  const sent = await res.json();
  assert.deepEqual([sent.version, sent.status, sent.claimCode], [2, 'sent', code]);
  assert.deepEqual(db.prepare('SELECT version, status FROM visit_result WHERE appointment_id = ? ORDER BY version').all(a).map((r) => ({ ...r })),
    [{ version: 1, status: 'amended' }, { version: 2, status: 'sent' }]);
  assert.ok(db.prepare("SELECT 1 FROM audit_event WHERE action = 'result.amend' AND appointment_id = ?").get(a));

  hist = await (await req('/v1/patients/p2/history')).json();
  assert.deepEqual(hist.filter((h) => h.appointmentId === a).map((h) => h.version), [2]);
  assert.equal(hist.length, 2); // plus the visit 30 days ago

  const claimed = await (await fetch(`${base}/v1/results/claim/${code}`)).json();
  assert.equal(claimed.version, 2);
  assert.equal(claimed.items[0].quantity, 14);
  assert.equal(claimed.diagnosis, 'Gút (M10); Rối loạn lipid máu (E78)');
  assert.deepEqual(claimed.advice, ['Uống đủ 2 lít nước mỗi ngày.', 'Hạn chế bia rượu.', 'Hẹn tái khám ngày 13/11/2026.']);
  assert.equal(claimed.insuranceCode, '');
  assert.equal(claimed.weightKg, 52);
  assert.equal(claimed.patientAge, 78);
});

test('nhận kết quả bằng mã: dạng VisitResult, không cần đăng nhập, ghi audit', async () => {
  const res = await fetch(`${base}/v1/results/claim/k7mq4xr2-9d`);
  assert.equal(res.status, 200);
  const r = await res.json();
  assert.deepEqual(Object.keys(r).sort(), ['address', 'advice', 'appointmentId', 'diagnosis', 'doctorName', 'facilityName', 'facilityPhone',
    'followUpDate', 'insuranceCode', 'issuedAt', 'items', 'patientAge', 'patientGender', 'patientName', 'version', 'weightKg'].sort());
  assert.equal(r.appointmentId, ids.appointments.p1);
  assert.equal(r.version, 1);
  assert.equal(r.issuedAt, at(clinicToday(), '08:24'));
  assert.equal(r.facilityName, 'Phòng khám Đa khoa An Bình');
  assert.equal(r.facilityPhone, '0900 000 000');
  assert.equal(r.doctorName, 'BS. Nguyễn Thu Hà');
  assert.deepEqual([r.patientName, r.patientAge, r.patientGender], ['Trần Văn Minh', 52, 'Nam']);
  assert.equal(r.insuranceCode, '•••• 3921');
  assert.equal(r.weightKg, null);
  assert.equal(r.diagnosis, 'Tăng huyết áp vô căn (I10)');
  assert.equal(r.items[0].quantity, 28);
  const [y, m, d] = addDays(clinicToday(), 28).split('-');
  assert.equal(r.advice.at(-1), `Hẹn tái khám ngày ${d}/${m}/${y}.`);
  const audit = db.prepare("SELECT * FROM audit_event WHERE action = 'result.claim' ORDER BY id DESC").get();
  assert.equal(audit.actor, 'patient');
  assert.equal(audit.appointment_id, ids.appointments.p1);
});

test('mã sai hoặc hết hạn: cùng 404', async () => {
  const wrong = await fetch(`${base}/v1/results/claim/AAAA-AAAA-AA`);
  assert.equal(wrong.status, 404);
  const garbage = await fetch(`${base}/v1/results/claim/not-a-code`);
  assert.equal(garbage.status, 404);
  const a = ids.appointments.p1;
  const keep = db.prepare('SELECT claim_expires_at e FROM appointment WHERE id = ?').get(a).e;
  db.prepare('UPDATE appointment SET claim_expires_at = ? WHERE id = ?').run(at(addDays(clinicToday(), -1), '08:00'), a);
  const expired = await fetch(`${base}/v1/results/claim/${CLAIM}`);
  db.prepare('UPDATE appointment SET claim_expires_at = ? WHERE id = ?').run(keep, a);
  assert.equal(expired.status, 404);
  const [w, e] = [await wrong.json(), await expired.json()];
  assert.deepEqual(w, e);
  assert.equal((await garbage.json()).error.message, w.error.message);
});

test('phòng khám khác: 404 cho mọi giao diện kết quả', async () => {
  const a = ids.appointments.p6;
  for (const [method, path, body] of [['GET', `/v1/appointments/${a}/result`], ['PUT', `/v1/appointments/${a}/result-draft`, full],
    ['POST', `/v1/appointments/${a}/result/send`], ['POST', `/v1/appointments/${a}/result/amend`, { reason: 'x' }]]) {
    const res = await req(path, { method, body, as: other });
    assert.equal(res.status, 404, `${method} ${path}`);
  }
  assert.equal(await (await req(`/v1/appointments/${a}/result`)).json(), null);
});

test('giới hạn 10 lần nhận mã mỗi phút mỗi IP', async () => {
  // Earlier tests already used part of this minute's budget from 127.0.0.1.
  const statuses = [];
  for (let i = 0; i < 11; i++) statuses.push((await fetch(`${base}/v1/results/claim/AAAA-AAAA-AA`)).status);
  assert.ok(statuses.includes(429));
  const last = await fetch(`${base}/v1/results/claim/${CLAIM}`);
  assert.equal(last.status, 429);
  assert.equal((await last.json()).error.code, 'rate_limited');
});
