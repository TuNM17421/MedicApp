import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createSessionState, handleUserValue, handleUtterance } from '../src/orchestrator.js';
import { ExtractorError, emptyExtraction } from '../src/extraction.js';
import { PROFILES, TODAY, mockExtractor } from './helpers.js';

const opts = (extra = {}) => ({ extractor: mockExtractor, mode: 'mock', limit: 12, ...extra });
const newSession = (known = {}) => createSessionState({ id: 's1', today: TODAY, profiles: PROFILES, known });

test('a complete request becomes ready without extra questions (AC01)', async () => {
  const s = newSession();
  const r = await handleUtterance(s, 'Tôi muốn khám dịch vụ cho tôi, đau khớp gối, ở An Bình, sáng thứ Sáu', opts());
  assert.equal(r.status, 'ready');
  assert.deepEqual(r.fields.time, { kind: 'date', date: '2026-10-16', period: 'morning' });
  assert.equal(r.fields.department_id, 'bones');
  assert.equal(r.sources.departmentId, 'suggested');
  assert.ok(r.fields.department_reason);
});

test('symptoms only: asks one question at a time and invents nothing (AC02)', async () => {
  const s = newSession();
  const r = await handleUtterance(s, 'Dạo này tôi bị đau lưng', opts());
  assert.equal(r.status, 'ask');
  assert.equal(r.question.field, 'type');
  assert.equal(r.fields.facility_id, null);
  assert.equal(r.fields.time, null);
  const r2 = handleUserValue(s, 'type', 'service', { mode: 'mock', source: 'choice' });
  assert.equal(r2.question.field, 'facilityId');
  assert.ok(r2.question.options.every((o) => ['anbinh', 'songxanh', 'hoalac'].includes(o.value)));
});

test('context from the basic flow is kept and not asked again (AC03)', async () => {
  const s = newSession({ patientId: 'mother', type: 'insurance', facilityId: 'hoalac' });
  const r = await handleUtterance(s, 'mẹ tôi bị tiểu đường, khám sớm nhất', opts());
  assert.equal(r.status, 'ready');
  assert.equal(r.fields.facility_id, 'hoalac');
  assert.equal(r.fields.department_id, 'endocrine');
});

test('a correction in the same sentence keeps only the last time (AC05)', async () => {
  const s = newSession({ patientId: 'self', type: 'service', facilityId: 'anbinh' });
  const r = await handleUtterance(s, 'khám tim mạch sáng thứ Sáu, à không, chiều thứ Bảy', opts());
  assert.deepEqual(r.fields.time, { kind: 'date', date: '2026-10-17', period: 'afternoon' });
  const r2 = await handleUtterance(s, 'đổi sang thứ Hai', opts());
  assert.equal(r2.fields.time.date, '2026-10-19');
  assert.equal(r2.fields.department_id, 'heart', 'other fields are kept');
});

test('a newer utterance supersedes a slow one and keeps both texts (AC06)', async () => {
  const s = newSession({ patientId: 'self', type: 'service', facilityId: 'anbinh' });
  let release;
  const gate = new Promise((r) => (release = r));
  const calls = [];
  const slow = async (input) => {
    calls.push(input.utterances);
    if (calls.length === 1) await gate;
    return mockExtractor(input);
  };
  const first = handleUtterance(s, 'tôi đau khớp', opts({ extractor: slow }));
  const second = handleUtterance(s, 'khám sớm nhất', opts({ extractor: slow }));
  release();
  assert.equal((await first).status, 'superseded');
  const r = await second;
  assert.deepEqual(calls[1], ['tôi đau khớp', 'khám sớm nhất']);
  assert.equal(r.status, 'ready');
});

test('a manual edit is not overwritten by a late model result (AC07)', async () => {
  const s = newSession({ patientId: 'self', type: 'service', facilityId: 'anbinh' });
  let release;
  const gate = new Promise((r) => (release = r));
  const pending = handleUtterance(s, 'khám tim mạch thứ Sáu', opts({ extractor: async (i) => { await gate; return mockExtractor(i); } }));
  const edited = handleUserValue(s, 'departmentId', 'eyes', { mode: 'mock', source: 'manual' });
  assert.equal(edited.processing, true, 'confirm stays blocked while a turn is processing');
  release();
  const r = await pending;
  assert.equal(r.fields.department_id, 'eyes');
  assert.equal(r.sources.departmentId, 'manual');
  assert.equal(r.fields.time.date, '2026-10-16');
});

test('unknown IDs and dates from the model are rejected (AC08)', async () => {
  const s = newSession();
  const bad = async () => ({ ...emptyExtraction(), facility_id: 'fake-hospital', doctor_id: 'dr-x', time_kind: 'date', date: '2026-10-18' });
  const r = await handleUtterance(s, 'xyz', opts({ extractor: bad }));
  assert.deepEqual(r.rejected.sort(), ['date', 'doctor_id', 'facility_id']);
  assert.equal(r.fields.facility_id, null);
  assert.match(r.notice, /Chủ nhật/);
});

test('model failures fall back without changing the draft (AC13)', async () => {
  const s = newSession({ patientId: 'self' });
  for (const code of ['config', 'quota', 'incomplete', 'network']) {
    const r = await handleUtterance(s, 'khám mắt', opts({ extractor: async () => { throw new ExtractorError(code); } }));
    assert.equal(r.status, 'fallback');
    assert.equal(r.error.code, code);
    assert.equal(r.fields.department_id, null);
    assert.ok(r.question, 'quick replies stay available');
  }
});

test('rate limit stops model calls per session', async () => {
  const s = newSession();
  let calls = 0;
  const counting = async (i) => { calls++; return mockExtractor(i); };
  let last;
  for (let i = 0; i < 4; i++) last = await handleUtterance(s, 'xin chào', opts({ extractor: counting, limit: 3 }));
  assert.equal(calls, 3);
  assert.equal(last.error.code, 'rate_limited');
});

test('urgent signals stop the normal booking path (AC14)', async () => {
  const s = newSession({ patientId: 'self', type: 'service', facilityId: 'anbinh' });
  const r = await handleUtterance(s, 'tôi đau ngực dữ dội và khó thở', opts());
  assert.equal(r.status, 'urgent');
  assert.equal(r.question, null);
  const r2 = handleUserValue(s, 'time', 'earliest', { mode: 'mock', source: 'choice' });
  assert.equal(r2.status, 'urgent');
});

test('changing patient clears the previous health details (AC17)', async () => {
  const s = newSession({ type: 'service', facilityId: 'anbinh' });
  await handleUtterance(s, 'cho tôi, đau họng, khám sớm nhất', opts());
  const r = handleUserValue(s, 'patientId', 'mother', { mode: 'mock', source: 'choice' });
  assert.equal(r.fields.symptoms, null);
  assert.equal(r.fields.department_id, null);
  assert.deepEqual(r.fields.time, { kind: 'earliest', date: null, period: null });
  assert.match(r.notice, /người trước/);
});

test('eligibility: children department and BHYT facility rules', async () => {
  const s = newSession({ patientId: 'self', type: 'insurance' });
  let r = handleUserValue(s, 'departmentId', 'children', { mode: 'mock', source: 'choice' });
  assert.equal(r.fields.department_id, null);
  assert.match(r.notice, /15 tuổi/);
  assert.ok(!r.question.options.some((o) => o.value === 'children'));
  r = handleUserValue(s, 'facilityId', 'songxanh', { mode: 'mock', source: 'choice' });
  assert.equal(r.fields.facility_id, null);
  assert.equal(r.fields.visit_type, 'insurance', 'never switches visit type on its own');
});

test('department not offered at the chosen facility asks for another facility', async () => {
  const s = newSession({ patientId: 'self', type: 'service', facilityId: 'hoalac' });
  const r = handleUserValue(s, 'departmentId', 'heart', { mode: 'mock', source: 'choice' });
  assert.equal(r.question.field, 'facilityId');
  assert.match(r.question.text, /chưa có khoa Tim mạch/);
  assert.deepEqual(r.question.options.map((o) => o.value), ['anbinh', 'songxanh']);
});

test('invalid quick-reply values are refused', () => {
  const s = newSession();
  assert.equal(handleUserValue(s, 'facilityId', 'nowhere', { mode: 'mock', source: 'choice' }), null);
  assert.equal(handleUserValue(s, 'time', 'date:2026-10-18', { mode: 'mock', source: 'choice' }), null);
  assert.equal(handleUserValue(s, 'unknown', 'x', { mode: 'mock', source: 'choice' }), null);
});
