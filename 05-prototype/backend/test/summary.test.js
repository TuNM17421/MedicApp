// Bước 17: pre-visit summary (guard, red flags, mock and OpenAI summarisers,
// worker trigger and coalescing, consent gating, off mode, newest summary).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import OpenAI from 'openai';

import { DEMO_EMAIL, DEMO_PASSWORD, seedClinic } from '../src/clinic/seed.js';
import { at, localIso, today as clinicToday } from '../src/clinic/time.js';
import { readConfig } from '../src/config.js';
import { openDatabase } from '../src/db/index.js';
import { createApp } from '../src/server.js';
import { unavailableStt } from '../src/stt.js';
import { guardSummary, unsupported } from '../src/summary/guard.js';
import { summariseMock } from '../src/summary/mock.js';
import { PROMPT_VERSION, SUMMARY_SCHEMA, buildSummaryRequest, createOpenAISummariser } from '../src/summary/openai.js';
import { redact, runSummary } from '../src/summary/pipeline.js';
import { detectRedFlags, redFlagList, signCodes } from '../src/summary/red-flags.js';
import { createSummaryWorker } from '../src/summary/worker.js';
import { config, mockExtractor } from './helpers.js';

const A = [
  { id: 'a1', channel: 'booking', question: '', answer: 'Tái khám huyết áp, sáng nay đo 138 trên 86.' },
  { id: 'a2', channel: 'pre_visit', question: 'Đã tự dùng thuốc gì?', answer: 'Có uống panadol, đỡ được chút. Hai hôm nay đau hơn.' },
  { id: 'a3', channel: 'pre_visit', question: 'Muốn hỏi bác sĩ điều gì?', answer: 'Có giảm thuốc được không bác sĩ.' },
];
const sentence = (text, sources) => ({ text, sources });

// ---- guard ---------------------------------------------------------------

test('guard: câu không có nguồn hoặc nguồn lạ bị bỏ, phần còn lại giữ', () => {
  const out = guardSummary({
    sections: [
      { key: 'chief', sentences: [sentence('Tái khám huyết áp, đo 138/86', ['a1']), sentence('Hay hồi hộp', []), sentence('Mất ngủ', ['a9'])] },
      { key: 'questions', sentences: [sentence('Hỏi có giảm thuốc được không', ['a3', 'a3'])] },
      { key: 'diagnosis', sentences: [sentence('Tăng huyết áp', ['a1'])] },
    ],
  }, A);
  assert.deepEqual(out.sections, [
    { key: 'chief', text: 'Tái khám huyết áp, đo 138/86.', sources: ['a1'] },
    { key: 'questions', text: 'Hỏi có giảm thuốc được không.', sources: ['a3'] },
  ]);
  assert.deepEqual(out.dropped.map((d) => d.reason).sort(), ['no_sources', 'unknown_key', 'unknown_source']);
});

test('guard: số không có trong câu được trích làm bỏ cả mục', () => {
  const out = guardSummary({
    sections: [
      { key: 'chief', sentences: [sentence('Đo huyết áp 138/86', ['a1'])] },
      { key: 'course', sentences: [sentence('Đau hơn trong 2 ngày', ['a2']), sentence('Tuân thủ thuốc 80%', ['a2'])] },
    ],
  }, A);
  assert.deepEqual(out.sections.map((s) => s.key), ['chief']);
  assert.deepEqual(out.dropped, [{ key: 'course', reason: 'number', value: '80' }]);
  // A number must be in the sentence's own sources, not elsewhere in the visit.
  const cross = guardSummary({ sections: [{ key: 'course', sentences: [sentence('Huyết áp 138/86', ['a2'])] }] }, A);
  assert.equal(cross.sections.length, 0);
  // Number words in the answer back digits in the summary, and the reverse.
  assert.equal(unsupported('Đau tăng 2 ngày nay.', [A[1]]), null);
  assert.equal(unsupported('Đau khoảng ba tuần.', [{ answer: 'đau 3 tuần rồi' }]), null);
  assert.deepEqual(unsupported('Quên hai liều.', [{ answer: 'có quên uống thuốc' }]), { reason: 'number', value: '2' });
});

test('guard: tên thuốc không có trong câu được trích làm bỏ mục; tên cùng nhóm được chấp nhận', () => {
  assert.equal(unsupported('Đã tự uống paracetamol, đỡ ít.', [A[1]]), null);
  assert.deepEqual(unsupported('Đã tự uống ibuprofen.', [A[1]]), { reason: 'drug', value: 'ibuprofen' });
  assert.deepEqual(unsupported('Đang dùng Amlodipin.', [A[0]]), { reason: 'drug', value: 'amlodipin' });
  const out = guardSummary({
    sections: [{ key: 'course', sentences: [sentence('Có uống panadol', ['a2']), sentence('Có dùng omeprazol', ['a2'])] }],
  }, A);
  assert.deepEqual(out.sections, []);
  assert.deepEqual(out.dropped, [{ key: 'course', reason: 'drug', value: 'omeprazol' }]);
});

test('guard: đầu ra sai dạng không làm hỏng gì', () => {
  for (const bad of [null, 'x', { sections: 'x' }, { sections: [null, { key: 'chief', sentences: [null, { text: 5 }] }] }]) {
    assert.deepEqual(guardSummary(bad, A).sections, []);
  }
});

// ---- red flags -----------------------------------------------------------

test('dấu hiệu cần chú ý: theo danh sách, không phân biệt dấu, bỏ qua câu phủ định', () => {
  const yes = {
    'Hôm qua đau ngực trái': ['chest_pain'],
    'dau nguc trai tu sang': ['chest_pain'],
    'Có lúc leo cầu thang thấy tức ngực, ngồi nghỉ thì hết.': ['chest_pain'],
    'Không sốt nhưng hay khó thở về đêm': ['dyspnea'],
    'Không đi lại được vì khó thở': ['dyspnea'],
    'Tuần trước bị ngất một lần': ['syncope'],
    'Sáng dậy thấy yếu nửa người bên phải, nói khó': ['hemiparesis', 'speech'],
    'Đi ngoài phân đen 2 ngày nay': ['melena'],
    'Hôm qua nôn ra máu': ['hematemesis'],
    'Cháu sốt cao co giật': ['seizure'],
    'Dạo này tôi không muốn sống nữa': ['suicidal'],
    'toi co y dinh tu tu': ['suicidal'],
    'Không biết có phải đau ngực không': ['chest_pain'],
    'Cha tôi bị đau ngực': ['chest_pain'],
  };
  for (const [text, codes] of Object.entries(yes)) assert.deepEqual(signCodes(text).sort(), codes.sort(), text);
  const no = [
    'Không đau ngực, không khó thở.',
    'khong dau nguc, ko kho tho',
    'Em không bị đau ngực hay khó thở gì cả',
    'Chưa bao giờ ngất',
    'Bị ngạt mũi 3 hôm',
    'bi ngat mui, so mui',
    'Chuyện này hơi khó nói',
    'Không đau đầu, không chóng mặt gì.',
    'Không thấy phân đen, không nôn ra máu',
  ];
  for (const text of no) assert.deepEqual(signCodes(text), [], text);
});

test('cờ trích câu gốc và id câu trả lời; danh sách ghi rõ cần bác sĩ duyệt', () => {
  const flags = detectRedFlags([
    { id: 'i-1', answer: 'Không sốt ạ. Có lúc leo cầu thang thấy tức ngực, ngồi nghỉ thì hết.' },
    { id: 'i-2', answer: 'Không đau ngực.' },
  ]);
  assert.deepEqual(flags.map(({ text, sources, signs }) => ({ text, sources, signs })), [
    { text: 'Có lúc leo cầu thang thấy tức ngực, ngồi nghỉ thì hết.', sources: ['i-1'], signs: ['đau ngực'] },
  ]);
  assert.match(redFlagList.note, /cần bác sĩ phòng khám đối tác duyệt trước khi dùng/);
  assert.equal(redFlagList.reviewed, false);
});

// ---- summarisers ---------------------------------------------------------

test('mock: theo quy tắc, ổn định, câu nào cũng có nguồn và qua kiểm tra', async () => {
  const p1 = await summariseMock({ answers: A });
  assert.deepEqual(p1, await summariseMock({ answers: A }));
  const out = guardSummary(p1, A);
  assert.deepEqual(out.sections.map((s) => [s.key, s.sources]), [['chief', ['a1']], ['course', ['a2']], ['questions', ['a3']]]);
  assert.equal(out.dropped.length, 0);
});

test('redact: bỏ tên, số điện thoại, mã BHYT, địa chỉ', () => {
  const pii = { name: 'Phạm Thị Lan', phone: '0912000482', insuranceCode: 'DN4010120003921', address: 'Số 8 ngõ 25' };
  const out = redact('Tôi là phạm thị lan, số 0912 000 482, thẻ DN4010120003921, ở Số 8 ngõ 25. Gọi 0987654321.', pii);
  assert.equal(out, 'Tôi là [tên], số [số điện thoại], thẻ [mã BHYT], ở [địa chỉ]. Gọi [số điện thoại].');
});

const cfg = readConfig({ SMART_MODE: 'mock', OPENAI_API_KEY: 'sk-test', CLINIC_AI_SUMMARY: 'openai' });
const client = (impl) => ({ responses: { create: impl } });
const okResponse = (body) => ({ status: 'completed', output: [], output_text: JSON.stringify(body) });

test('openai: request có schema strict, store=false, model cấu hình, không có thông tin định danh', async () => {
  const req = buildSummaryRequest(cfg, A);
  assert.equal(req.model, 'gpt-6-luna');
  assert.equal(req.store, false);
  assert.deepEqual(req.reasoning, { effort: 'low' });
  assert.equal(req.max_output_tokens, 1200);
  assert.deepEqual(req.text.format, { type: 'json_schema', name: 'visit_summary', schema: SUMMARY_SCHEMA, strict: true });
  assert.deepEqual(SUMMARY_SCHEMA.properties.sections.items.properties.key.enum, ['chief', 'course', 'questions']);
  assert.match(req.instructions, /Không tự tính hay viết con số/);
  assert.deepEqual(JSON.parse(req.input), { answers: A.map(({ id, channel, question, answer }) => ({ id, channel, question, answer })) });

  // Through the pipeline: short ids out, real ids back, no PII in the body.
  let seen;
  const rows = [
    { id: 'a-p2-x/q1', channel: 'booking', question: '', answer: 'Tôi là Phạm Thị Lan, đau gối phải 1 tuần. SĐT 0912000482.' },
    { id: 'a-p2-x/q2', channel: 'pre_visit', question: 'Đã tự dùng thuốc gì?', answer: 'Có uống panadol.' },
  ];
  const summarise = createOpenAISummariser(cfg, {
    client: client(async (body, opts) => {
      seen = body;
      assert.ok(opts && 'signal' in opts);
      return okResponse({ sections: [
        { key: 'chief', sentences: [{ text: 'Đau gối phải 1 tuần.', sources: ['a1'] }] },
        { key: 'course', sentences: [{ text: 'Đã tự uống paracetamol.', sources: ['a2'] }] },
      ] });
    }),
  });
  const out = await runSummary({
    rows, summarise, pii: { name: 'Phạm Thị Lan', phone: '0912000482', insuranceCode: 'DN4010120003921', address: 'Số 8 ngõ 25' },
  });
  for (const pii of ['Phạm Thị Lan', '0912000482', 'a-p2-x', 'DN4010120003921', 'Số 8']) assert.ok(!JSON.stringify(seen).includes(pii), pii);
  assert.deepEqual(JSON.parse(seen.input).answers.map((a) => a.id), ['a1', 'a2']);
  assert.deepEqual(out.sections.map((s) => s.sources), [['a-p2-x/q1'], ['a-p2-x/q2']]);
});

test('openai: lỗi mạng thử lại một lần, lỗi key không thử lại, incomplete là lỗi', async () => {
  let calls = 0;
  const flaky = createOpenAISummariser(cfg, {
    retryDelayMs: 0,
    client: client(async () => {
      if (++calls === 1) throw new OpenAI.APIConnectionError({ message: 'reset' });
      return okResponse({ sections: [] });
    }),
  });
  await flaky({ answers: A });
  assert.equal(calls, 2);
  calls = 0;
  const auth = createOpenAISummariser(cfg, {
    retryDelayMs: 0,
    client: client(async () => {
      calls++;
      throw new OpenAI.AuthenticationError(401, { message: 'bad key' }, 'bad key', new Headers());
    }),
  });
  await assert.rejects(auth({ answers: A }), (e) => e.code === 'config');
  assert.equal(calls, 1);
  const inc = createOpenAISummariser(cfg, { client: client(async () => ({ status: 'incomplete', output: [] })) });
  await assert.rejects(inc({ answers: A }), (e) => e.code === 'incomplete');
});

test('cấu hình CLINIC_AI_SUMMARY', () => {
  assert.equal(readConfig({}).summaryMode, 'mock');
  assert.equal(readConfig({ OPENAI_API_KEY: 'sk-x' }).summaryMode, 'openai');
  assert.equal(readConfig({ OPENAI_API_KEY: 'sk-x', CLINIC_AI_SUMMARY: 'mock' }).summaryMode, 'mock');
  assert.equal(readConfig({ CLINIC_AI_SUMMARY: 'off' }).summaryMode, 'off');
  assert.throws(() => readConfig({ CLINIC_AI_SUMMARY: 'openai' }), /OPENAI_API_KEY/);
  assert.throws(() => readConfig({ CLINIC_AI_SUMMARY: 'gpt' }), /CLINIC_AI_SUMMARY/);
});

// ---- worker and API ------------------------------------------------------

let db;
let ids;
let server;
let base;
let staff;
const servers = [];
const calls = [];
let gate = null;
// Records each run; while `gate` is set, runs wait for it.
async function countingSummariser(input) {
  calls.push(input.answers.length);
  if (gate) await gate.promise;
  return summariseMock(input);
}

async function start(env, summary) {
  const s = createApp({ config: config(env), extractor: mockExtractor, stt: unavailableStt, log: () => {}, db, summary });
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  servers.push(s);
  return { s, url: `http://127.0.0.1:${s.address().port}` };
}

before(async () => {
  db = openDatabase();
  ids = await seedClinic(db, { today: clinicToday() });
  ({ s: server, url: base } = await start({}, { summarise: countingSummariser, debounceMs: 200 }));
  const res = await fetch(`${base}/v1/staff/login`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
  });
  staff = res.headers.get('set-cookie').split(';')[0];
});
after(() => Promise.all(servers.map((s) => new Promise((r) => s.close(r)))));

const call = (path, { method = 'GET', body, token, url = base } = {}) => fetch(url + path, {
  method,
  headers: {
    ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    ...(!token ? { cookie: staff } : {}),
  },
  body: body !== undefined ? JSON.stringify(body) : undefined,
});

async function signIn(phone, url = base) {
  server.clinic.patient.resetLimits();
  const { devCode } = await (await call('/v1/patient/otp', { method: 'POST', body: { phone }, url })).json();
  return (await (await call('/v1/patient/session', { method: 'POST', body: { phone, code: devCode }, url })).json()).token;
}

const answer = (id, text, over = {}) => ({ id, channel: 'pre_visit', question: '', answer: text, answeredAt: localIso(), ...over });
const rowsOf = (a) => db.prepare('SELECT * FROM visit_summary WHERE appointment_id = ? ORDER BY rowid').all(a);
const chart = async (a) => (await call(`/v1/appointments/${a}/chart`)).json();

test('gửi câu trả lời thì tạo tóm tắt mới ở nền; hồ sơ trả bản mới nhất có cờ; ghi audit system', async () => {
  const a = ids.appointments.p6;
  const token = await signIn(ids.phones.p6);
  const before = rowsOf(a).length;
  calls.length = 0;
  const res = await call(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token, body: { answers: [
    answer('n1', 'Hai hôm nay đi ngoài phân đen, hơi chóng mặt.', { question: 'Nặng hơn hay nhẹ hơn?' }),
    answer('n2', 'Không đau ngực.', { question: 'Có triệu chứng khác không?' }),
  ] } });
  assert.equal(res.status, 200);
  assert.equal(rowsOf(a).length, before, 'the upload does not wait for the summary');
  await server.clinic.summaries.idle();
  assert.equal(calls.length, 1);
  const rows = rowsOf(a);
  assert.equal(rows.length, before + 1, 'a new row; the seed summary stays');
  assert.equal(rows.at(-1).prompt_version, PROMPT_VERSION);
  assert.equal(rows.at(-1).mode, 'mock');

  const c = await chart(a);
  assert.equal(c.summary.id, rows.at(-1).id);
  assert.equal(c.summary.mode, 'mock');
  const intakeIds = new Set(c.intake.map((i) => i.id));
  for (const s of c.summary.sections) {
    assert.ok(['chief', 'course', 'questions'].includes(s.key));
    assert.ok(s.sources.length && s.sources.every((id) => intakeIds.has(id)), s.key);
  }
  assert.deepEqual(c.summary.flags.map((f) => [f.sources, f.signs]), [[[`${a}/n1`], ['đi ngoài phân đen']]]);
  assert.equal(c.summary.feedback, null);
  const audit = db.prepare("SELECT * FROM audit_event WHERE action = 'summary.generate' ORDER BY id DESC").get();
  assert.equal(audit.actor, 'system');
  assert.equal(audit.appointment_id, a);
  const detail = JSON.parse(audit.detail);
  assert.equal(detail.summaryId, rows.at(-1).id);
  assert.equal(detail.flags, 1);
  assert.ok(!audit.detail.includes('phân đen'), 'no patient words in the audit');
  const wl = (await (await call('/v1/clinic/worklist')).json()).items.find((i) => i.appointmentId === a);
  assert.equal(wl.flagged, true);

  // Same answers again: nothing new.
  await call(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token, body: { answers: [
    answer('n2', 'Không đau ngực.', { question: 'Có triệu chứng khác không?', answeredAt: c.intake.find((i) => i.id.endsWith('/n2')).answeredAt }),
  ] } });
  await server.clinic.summaries.idle();
  assert.equal(rowsOf(a).length, before + 1);
});

test('nhiều lần gửi liền nhau gộp thành một lần chạy; câu mới đến khi đang chạy thì chạy thêm một lần', async () => {
  const a = ids.appointments.p2;
  const token = await signIn(ids.phones.p2);
  calls.length = 0;
  const before = rowsOf(a).length;
  for (let i = 1; i <= 3; i++) {
    const res = await call(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token, body: { answers: [answer(`b${i}`, `Đau gối thêm ${i} ngày`)] } });
    assert.equal(res.status, 200);
  }
  await server.clinic.summaries.idle();
  assert.equal(calls.length, 1, 'one run for three uploads');
  assert.equal(rowsOf(a).length, before + 1);

  let release;
  gate = { promise: new Promise((r) => { release = r; }) };
  calls.length = 0;
  await call(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token, body: { answers: [answer('c1', 'Gối sưng hơn')] } });
  server.clinic.summaries.flush();
  while (!calls.length) await new Promise((r) => setTimeout(r, 5));
  // Two more uploads while the first run is still waiting on the model.
  await call(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token, body: { answers: [answer('c2', 'Đêm qua sốt nhẹ')] } });
  server.clinic.summaries.flush();
  await call(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token, body: { answers: [answer('c3', 'Sáng nay đỡ sốt')] } });
  server.clinic.summaries.flush();
  gate = null;
  release();
  await server.clinic.summaries.idle();
  assert.equal(calls.length, 2, 'the running one, then one more for everything that came in');
  const all = db.prepare('SELECT count(*) n FROM intake_answer WHERE appointment_id = ?').get(a).n;
  assert.equal(calls[1], all);
  assert.equal(rowsOf(a).length, before + 3);
});

test('không tạo tóm tắt khi chưa đồng ý phạm vi intake, đã rút, hoặc rút trong lúc chạy', async () => {
  const worker = server.clinic.summaries;
  // p5: never answered the consent question; p3: declined.
  db.prepare(`INSERT INTO intake_answer (id, appointment_id, channel, question, answer, answered_at)
    VALUES ('x-p5', ?, 'pre_visit', '', 'Đau lưng', ?)`).run(ids.appointments.p5, localIso());
  assert.deepEqual(await worker.generate(ids.appointments.p5), { status: 'skipped', reason: 'no_consent' });
  assert.deepEqual(await worker.generate(ids.appointments.p3), { status: 'skipped', reason: 'no_consent' });
  // A consent without 'intake' does not count.
  db.prepare(`INSERT INTO consent (id, appointment_id, scope, wording_version, granted_at, expires_at)
    VALUES ('cs-p5-x', ?, '["dose_log"]', 1, ?, '2099-01-01T00:00:00+07:00')`).run(ids.appointments.p5, localIso());
  assert.deepEqual(await worker.generate(ids.appointments.p5), { status: 'skipped', reason: 'no_consent' });
  assert.equal(rowsOf(ids.appointments.p5).length, 0);

  // Revoked while the model works: the result is thrown away.
  const a = ids.appointments.p4;
  const token = await signIn(ids.phones.p4);
  let release;
  gate = { promise: new Promise((r) => { release = r; }) };
  calls.length = 0;
  const before = rowsOf(a).length;
  const run = worker.generate(a);
  while (!calls.length) await new Promise((r) => setTimeout(r, 5));
  assert.equal((await call(`/v1/patient/appointments/${a}/consent`, { method: 'DELETE', token })).status, 200);
  gate = null;
  release();
  assert.deepEqual(await run, { status: 'skipped', reason: 'no_consent' });
  assert.equal(rowsOf(a).length, before);
});

test('lỗi model: không có dòng mới, ghi audit thất bại', async () => {
  const worker = createSummaryWorker({
    db, config: config(), summarise: async () => { const e = new Error('x'); e.code = 'timeout'; throw e; },
  });
  const a = ids.appointments.p1;
  const before = rowsOf(a).length;
  assert.deepEqual(await worker.generate(a), { status: 'failed', code: 'timeout' });
  assert.equal(rowsOf(a).length, before);
  const audit = db.prepare("SELECT * FROM audit_event WHERE action = 'summary.generate' ORDER BY id DESC").get();
  assert.deepEqual(JSON.parse(audit.detail).result, 'failed');
  worker.close();
});

test('CLINIC_AI_SUMMARY=off: gửi câu trả lời không tạo tóm tắt', async () => {
  const { s, url } = await start({ CLINIC_AI_SUMMARY: 'off' }, { debounceMs: 0 });
  assert.equal(s.clinic.summaries.mode, 'off');
  const a = ids.appointments.p1;
  const token = await signIn(ids.phones.p1, url);
  const before = rowsOf(a).length;
  const res = await call(`/v1/patient/appointments/${a}/intake`, { method: 'PUT', token, url, body: { answers: [answer('off1', 'Đau đầu nhẹ')] } });
  assert.equal(res.status, 200);
  await s.clinic.summaries.idle();
  assert.equal(s.clinic.summaries.pending(), 0);
  assert.deepEqual(await s.clinic.summaries.generate(a), { status: 'skipped', reason: 'off' });
  assert.equal(rowsOf(a).length, before);
  const health = await (await fetch(`${url}/health`)).json();
  assert.equal(health.summary_mode, 'off');
});

test('hồ sơ trả tóm tắt mới nhất, kể cả khi hai bản cùng thời điểm', async () => {
  const a = ids.appointments.p1;
  const t = localIso(Date.now() + 60_000);
  const insert = db.prepare(`INSERT INTO visit_summary (id, appointment_id, sections, flags, mode, model, prompt_version, created_at)
    VALUES (?, ?, ?, '[]', 'mock', '', 'test', ?)`);
  // 'zz' sorts after 'aa': the order must come from insertion, not the id.
  insert.run('s-zz', a, JSON.stringify([{ key: 'chief', text: 'Cũ.', sources: [] }]), t);
  insert.run('s-aa', a, JSON.stringify([{ key: 'chief', text: 'Mới.', sources: [] }]), t);
  const c = await chart(a);
  assert.equal(c.summary.id, 's-aa');
  assert.deepEqual(Object.keys(c.summary).sort(), ['createdAt', 'feedback', 'flags', 'id', 'mode', 'sections']);
});

test('eval set: 30 hội thoại mẫu, có cờ và câu phủ định', () => {
  const cases = JSON.parse(readFileSync(new URL('../eval/summary-cases.json', import.meta.url), 'utf8')).cases;
  assert.equal(cases.length, 30);
  assert.ok(cases.some((c) => c.expectFlags.length));
  assert.ok(cases.some((c) => c.negated?.length));
});

test('mock: the app’s pre-visit questions land in their sections', async () => {
  const { sectionOf } = await import('../src/summary/mock.js');
  const of = (question) => sectionOf({ channel: 'pre_visit', question, answer: 'x' });
  assert.equal(of('Lần này bạn đi khám vì điều gì?'), 'chief');
  assert.equal(of('Bệnh nặng hơn hay nhẹ hơn so với trước?'), 'course');
  assert.equal(of('Bạn đã tự dùng thuốc gì chưa?'), 'course');
  assert.equal(of('Bạn muốn hỏi bác sĩ điều gì?'), 'questions');
});
