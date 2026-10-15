import {
  bookableDates,
  catalog,
  dateLabel,
  department,
  doctor,
  facility,
} from './catalog.js';
import { ExtractorError, validateExtraction } from './extraction.js';

/**
 * Conversation orchestrator. The extractor (mock rules or the model) only
 * proposes field values; this module validates them against the catalog,
 * keeps manual edits, enforces eligibility and decides the single next
 * question. Availability, slots and payment stay in the app's
 * BookingRepository, which stands in for the hospital system in this prototype.
 */

const FIELDS = ['patientId', 'type', 'facilityId', 'departmentId', 'doctorId', 'time'];
const USER_SET = new Set(['choice', 'manual', 'context']);
const MAX_PENDING = 5;

const ERROR_MESSAGES = {
  config: 'Dịch vụ AI chưa được cấu hình đúng. Bạn có thể chọn nhanh bên dưới hoặc đặt lịch từng bước.',
  permission: 'Tài khoản AI chưa có quyền dùng model đã cấu hình. Bạn có thể chọn nhanh hoặc đặt lịch từng bước.',
  quota: 'Dịch vụ AI đang tạm hết lượt. Vui lòng thử lại sau hoặc chọn nhanh bên dưới.',
  rate_limited: 'Bạn đã gửi nhiều yêu cầu liên tiếp. Vui lòng chờ một chút hoặc chọn nhanh bên dưới.',
  network: 'Chưa kết nối được dịch vụ AI. Câu vừa nói chưa được xử lý, vui lòng nói hoặc nhập lại.',
  timeout: 'Dịch vụ AI phản hồi quá lâu. Câu vừa nói chưa được xử lý, vui lòng nói hoặc nhập lại.',
  incomplete: 'Chưa hiểu trọn câu vừa rồi. Vui lòng nói ngắn hơn hoặc chọn nhanh bên dưới.',
  refusal: 'Mình chưa xử lý được yêu cầu này. Vui lòng nói lại nhu cầu đặt khám hoặc chọn nhanh.',
  invalid_output: 'Chưa hiểu câu vừa rồi. Vui lòng nói lại hoặc chọn nhanh bên dưới.',
};

export function createSessionState({ id, today, profiles, known = {} }) {
  const session = {
    id,
    today,
    profiles,
    version: 0,
    fields: {},
    departmentReason: null,
    symptoms: null,
    pending: [],
    runId: 0,
    inflight: null,
    asked: {},
    urgent: false,
    notice: null,
    modelCalls: [],
  };
  const patch = {};
  if (profiles.some((p) => p.id === known.patientId)) patch.patientId = known.patientId;
  if (known.type === 'insurance' || known.type === 'service') patch.type = known.type;
  if (facility(known.facilityId)) patch.facilityId = known.facilityId;
  applyPatch(session, patch, { source: 'context' });
  return session;
}

function get(session, field) {
  return session.fields[field]?.value ?? null;
}

function ageOf(session) {
  return session.profiles.find((p) => p.id === get(session, 'patientId'))?.age ?? null;
}

/**
 * Applies validated values. A model result never overwrites a field the user
 * set (by choice or manual edit) after the utterances it was computed from.
 */
export function applyPatch(session, patch, { source, sinceVersion = Infinity }) {
  const changed = [];
  const notes = [];
  const version = session.version + 1;
  const userSource = USER_SET.has(source);
  const locked = (field) => {
    const current = session.fields[field];
    return !userSource && current && USER_SET.has(current.source) && current.version > sinceVersion;
  };
  const set = (field, value, as = source) => {
    if (locked(field)) return false;
    const current = session.fields[field];
    if (JSON.stringify(current?.value ?? null) === JSON.stringify(value ?? null)) {
      if (current && userSource) current.source = as;
      return false;
    }
    if (value === null || value === undefined) delete session.fields[field];
    else session.fields[field] = { value, source: as, version };
    changed.push(field);
    return true;
  };

  if ('patientId' in patch) {
    const previous = get(session, 'patientId');
    if (set('patientId', patch.patientId) && previous) {
      // Health details belong to the previous patient (PRD AC17).
      session.symptoms = null;
      session.departmentReason = null;
      if (session.fields.departmentId?.source !== 'manual') set('departmentId', null);
      set('doctorId', null);
      notes.push('Đã đổi người khám, mô tả sức khỏe và gợi ý khoa của người trước đã được xóa.');
    }
  }
  if ('type' in patch) set('type', patch.type);
  if ('facilityId' in patch && set('facilityId', patch.facilityId)) {
    const doc = doctor(get(session, 'doctorId'));
    if (doc && doc.facilityId !== patch.facilityId) set('doctorId', null);
  }
  if ('departmentId' in patch && set('departmentId', patch.departmentId, patch.departmentReason && !userSource ? 'suggested' : source)) {
    session.departmentReason = userSource ? null : patch.departmentReason ?? null;
    const doc = doctor(get(session, 'doctorId'));
    if (doc && doc.departmentId !== patch.departmentId) set('doctorId', null);
  }
  if ('doctorId' in patch) {
    const doc = doctor(patch.doctorId);
    if (!doc) set('doctorId', null);
    else {
      const fac = get(session, 'facilityId');
      const dep = get(session, 'departmentId');
      const conflict = (fac && fac !== doc.facilityId) || (dep && dep !== doc.departmentId);
      if (conflict && !userSource) {
        notes.push(`${doc.name} không khám ở nơi hoặc chuyên khoa đã chọn, nên chưa đổi bác sĩ.`);
      } else {
        set('facilityId', doc.facilityId);
        set('departmentId', doc.departmentId);
        set('doctorId', doc.id);
      }
    }
  }
  if ('time' in patch || 'period' in patch) {
    const current = get(session, 'time');
    let next = current;
    if ('time' in patch) next = patch.time ? { ...patch.time, period: null } : null;
    if ('period' in patch) next = { ...(next ?? { kind: 'earliest', date: null }), period: patch.period };
    set('time', next);
  }
  if (patch.symptoms) {
    session.symptoms = [session.symptoms, patch.symptoms].filter(Boolean).join(' · ').slice(-600);
  }
  if (changed.length) session.version = version;
  return { changed, notes };
}

/** Removes values that became invalid together; returns user-facing notes. */
function enforceEligibility(session) {
  const notes = [];
  const dep = department(get(session, 'departmentId'));
  const age = ageOf(session);
  if (dep?.maxAge !== undefined && age !== null && age > dep.maxAge) {
    applyPatch(session, { departmentId: null }, { source: 'manual' });
    notes.push(`${dep.name} chỉ nhận người đến ${dep.maxAge} tuổi. Vui lòng chọn chuyên khoa khác.`);
  }
  const fac = facility(get(session, 'facilityId'));
  if (fac && get(session, 'type') === 'insurance' && !fac.acceptsInsurance) {
    applyPatch(session, { facilityId: null }, { source: 'manual' });
    notes.push(`${fac.name} không nhận khám BHYT. Vui lòng chọn nơi khám khác; hình thức khám được giữ nguyên.`);
  }
  return notes;
}

function facilitiesFor(session) {
  const type = get(session, 'type');
  const dep = get(session, 'departmentId');
  return catalog.facilities.filter(
    (f) => (type !== 'insurance' || f.acceptsInsurance) && (!dep || f.departments.includes(dep)),
  );
}

function question(session, field, text, options) {
  session.asked[field] = (session.asked[field] ?? 0) + 1;
  // After two unanswered rounds on the same field, steer to pickers/basic flow.
  return { field, text, options, allow_picker: session.asked[field] > 2 };
}

export function nextQuestion(session) {
  if (!get(session, 'patientId')) {
    return question(session, 'patientId', 'Bạn đặt lịch khám cho ai?',
      session.profiles.map((p) => ({ value: p.id, label: p.relationship })));
  }
  if (!get(session, 'type')) {
    return question(session, 'type', 'Bạn muốn khám BHYT hay khám dịch vụ?', [
      { value: 'insurance', label: 'Khám BHYT' },
      { value: 'service', label: 'Khám dịch vụ' },
    ]);
  }
  if (!get(session, 'departmentId')) {
    const age = ageOf(session);
    const fac = facility(get(session, 'facilityId'));
    const options = catalog.departments
      .filter((d) => d.maxAge === undefined || age === null || age <= d.maxAge)
      .filter((d) => !fac || fac.departments.includes(d.id))
      .map((d) => ({ value: d.id, label: d.name }));
    return question(session, 'departmentId', session.symptoms
      ? 'Mô tả chưa đủ để gợi ý chuyên khoa. Bạn có thể nói thêm hoặc chọn chuyên khoa muốn khám.'
      : 'Bạn đang gặp vấn đề gì, hoặc muốn khám chuyên khoa nào?', options);
  }
  const dep = department(get(session, 'departmentId'));
  const fac = facility(get(session, 'facilityId'));
  if (!fac || !fac.departments.includes(dep.id)) {
    const options = facilitiesFor(session).map((f) => ({ value: f.id, label: f.name, hint: f.address }));
    const text = fac
      ? `${fac.name} chưa có khoa ${dep.name}. Bạn muốn khám ở cơ sở nào?`
      : 'Bạn muốn khám ở khu vực hoặc cơ sở nào?';
    return question(session, 'facilityId', text, options);
  }
  if (!get(session, 'time')) {
    return question(session, 'time', 'Bạn muốn khám khi nào?', [
      { value: 'earliest', label: 'Sớm nhất còn chỗ' },
      { value: 'earliest:morning', label: 'Buổi sáng sớm nhất' },
      { value: 'earliest:afternoon', label: 'Buổi chiều sớm nhất' },
      ...bookableDates(session.today).map((d) => ({ value: `date:${d}`, label: dateLabel(d) })),
    ]);
  }
  return null;
}

export function publicFields(session) {
  const time = get(session, 'time');
  return {
    patient_id: get(session, 'patientId'),
    visit_type: get(session, 'type'),
    facility_id: get(session, 'facilityId'),
    department_id: get(session, 'departmentId'),
    department_reason: session.departmentReason,
    doctor_id: get(session, 'doctorId'),
    time: time ? { kind: time.kind, date: time.date ?? null, period: time.period ?? null } : null,
    symptoms: session.symptoms,
  };
}

export function reply(session, { mode, status: forced, error, notes = [], changed = [], rejected = [], turnId = null }) {
  const extraNotes = enforceEligibility(session);
  const allNotes = [...notes, ...extraNotes, ...(session.notice ? [session.notice] : [])];
  session.notice = null;
  let status = forced;
  let q = null;
  if (!status) {
    if (session.urgent) status = 'urgent';
    else {
      q = nextQuestion(session);
      status = q ? 'ask' : 'ready';
    }
  }
  if (status === 'fallback') q = nextQuestion(session);
  return {
    session_id: session.id,
    turn_id: turnId,
    draft_version: session.version,
    status,
    processing: Boolean(session.inflight),
    mode,
    fields: publicFields(session),
    sources: Object.fromEntries(FIELDS.filter((f) => session.fields[f]).map((f) => [f, session.fields[f].source])),
    question: q,
    notice: allNotes.join(' ') || null,
    error: error ? { code: error, message: ERROR_MESSAGES[error] ?? ERROR_MESSAGES.network } : null,
    changed,
    rejected,
    catalog_version: catalog.version,
  };
}

/** Validates a quick reply or manual edit coming from the app. */
export function parseUserValues(session, field, value) {
  const patch = {};
  switch (field) {
    case 'patientId':
      if (!session.profiles.some((p) => p.id === value)) return null;
      patch.patientId = value;
      break;
    case 'type':
      if (value !== 'insurance' && value !== 'service') return null;
      patch.type = value;
      break;
    case 'facilityId':
      if (!facility(value)) return null;
      patch.facilityId = value;
      break;
    case 'departmentId':
      if (!department(value)) return null;
      patch.departmentId = value;
      break;
    case 'doctorId':
      if (value !== null && !doctor(value)) return null;
      patch.doctorId = value;
      break;
    case 'time': {
      if (value === 'earliest') patch.time = { kind: 'earliest', date: null };
      else if (/^earliest:(morning|afternoon)$/.test(value ?? '')) {
        patch.time = { kind: 'earliest', date: null };
        patch.period = value.split(':')[1];
      } else if (/^date:\d{4}-\d{2}-\d{2}(:(morning|afternoon))?$/.test(value ?? '')) {
        const [, date, period] = value.split(':');
        if (!bookableDates(session.today).includes(date)) return null;
        patch.time = { kind: 'date', date };
        if (period) patch.period = period;
      } else return null;
      break;
    }
    default:
      return null;
  }
  return patch;
}

function rateLimited(session, limit, now) {
  session.modelCalls = session.modelCalls.filter((t) => now - t < 60_000);
  if (session.modelCalls.length >= limit) return true;
  session.modelCalls.push(now);
  return false;
}

/**
 * Processes a finished utterance (typed or final transcript). A newer
 * utterance aborts the running extraction and re-runs it over every pending
 * utterance, so nothing said is lost and stale results are never applied.
 */
export async function handleUtterance(session, text, { extractor, mode, limit, turnId, log = () => {}, now = Date.now }) {
  session.version += 1;
  session.pending.push({ text: String(text).slice(0, 1000), version: session.version });
  if (session.pending.length > MAX_PENDING) session.pending.splice(0, session.pending.length - MAX_PENDING);
  if (rateLimited(session, limit, now())) {
    session.pending = [];
    return reply(session, { mode, status: 'fallback', error: 'rate_limited', turnId });
  }
  session.inflight?.abort();
  const controller = new AbortController();
  const runId = ++session.runId;
  session.inflight = controller;
  const batch = [...session.pending];
  let raw;
  try {
    raw = await extractor({
      utterances: batch.map((b) => b.text),
      profiles: session.profiles,
      today: session.today,
      state: publicFields(session),
      signal: controller.signal,
    });
  } catch (error) {
    if (runId !== session.runId) return { session_id: session.id, turn_id: turnId, status: 'superseded' };
    session.inflight = null;
    session.pending = session.pending.filter((p) => !batch.includes(p));
    const code = error instanceof ExtractorError ? error.code : 'network';
    log('turn_failed', { code });
    return reply(session, { mode, status: 'fallback', error: code, turnId });
  }
  if (runId !== session.runId) return { session_id: session.id, turn_id: turnId, status: 'superseded' };
  session.inflight = null;
  session.pending = session.pending.filter((p) => !batch.includes(p));
  const result = validateExtraction(raw, { profiles: session.profiles, today: session.today });
  if (result.rejected.length) log('rejected_fields', { fields: result.rejected });
  const { changed, notes } = applyPatch(session, result.patch, {
    source: 'ai',
    sinceVersion: Math.max(...batch.map((b) => b.version)),
  });
  if (result.urgent) session.urgent = true;
  if (result.outOfScope) notes.push('Ứng dụng không tư vấn chẩn đoán hay thuốc; mình chỉ giúp bạn đặt lịch khám.');
  if (result.rejected.includes('date')) notes.push('Ngày bạn nói không có lịch đặt trực tuyến (chỉ nhận 6 ngày tới, nghỉ Chủ nhật).');
  return reply(session, { mode, notes, changed, rejected: result.rejected, turnId });
}

export function handleUserValue(session, field, value, { mode, source }) {
  const patch = parseUserValues(session, field, value);
  if (!patch) return null;
  const { changed, notes } = applyPatch(session, patch, { source });
  return reply(session, { mode, notes, changed });
}
