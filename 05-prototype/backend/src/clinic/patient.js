// Patient API (bước 16, CLINIC-API.md "Người bệnh"): sign-in by phone and
// one-time code, the person's own appointments and results, sharing consent
// per visit and the upload of intake answers, self-medication and dose
// events. A session belongs to a phone; it reaches every patient row (in any
// clinic) with that phone. Logs carry event names and a masked phone only,
// never names, answers or tokens.
import { createHash, createHmac, randomBytes, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';

import { HttpError, notFound, readJson, sendJson } from '../http.js';
import { visitResultJson } from './api.js';
import { SLOTS } from './prescription.js';
import { localIso, parseDay } from './time.js';

export const OTP_TTL_S = 300;
export const OTP_MAX_ATTEMPTS = 5;
export const OTP_WINDOW_MS = 10 * 60_000;
export const OTP_PER_PHONE = 3;
export const OTP_PER_IP = 10;
export const SESSION_DAYS = 30;
export const CONSENT_DAYS = 30;
export const UPLOADS_PER_MINUTE = 60;
export const SCOPES = ['intake', 'dose_log', 'self_meds'];
export const MAX_ANSWERS = 50;
export const MAX_SELF_MEDS = 30;
export const MAX_DOSE_EVENTS = 500;
/** Uploads may be larger than the 16 KiB of other bodies (500 dose events, 50 answers). */
export const UPLOAD_BODY = 512 * 1024;

const DAY_MS = 86_400_000;
const REASONS = ['forgot', 'outOfStock', 'unwell', 'other'];
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;

/** '0xxxxxxxxx', or null. Spaces, dots and dashes are ignored; +84 / 84 become 0. */
export function normalizePhone(raw) {
  if (typeof raw !== 'string' || raw.length > 32) return null;
  let s = raw.replace(/[\s.-]/g, '');
  if (/^\+84\d{9}$/.test(s)) s = `0${s.slice(3)}`;
  else if (/^84\d{9}$/.test(s)) s = `0${s.slice(2)}`;
  return /^0\d{9}$/.test(s) ? s : null;
}

/** '09•••••123' for logs. */
export const maskPhone = (phone) => `${phone.slice(0, 2)}•••••${phone.slice(-3)}`;

const sha256 = (text) => createHash('sha256').update(text).digest('base64url');
const isText = (v, max, min = 0) => typeof v === 'string' && v.trim().length >= min && v.length <= max;
const isoTime = (v) => typeof v === 'string' && ISO_TIME.test(v) && !Number.isNaN(Date.parse(v));
const json = (text, fallback) => {
  try {
    return text == null ? fallback : JSON.parse(text);
  } catch {
    return fallback;
  }
};

const unauthenticated = () => new HttpError(401, 'unauthenticated', 'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại.');
const badCode = () => new HttpError(401, 'bad_code', 'Mã xác nhận không đúng hoặc đã hết hạn.');
const badPhone = () => new HttpError(422, 'bad_phone', 'Số điện thoại không hợp lệ.', ['phone']);
const rateLimited = () => new HttpError(429, 'rate_limited', 'Bạn thử quá nhiều lần. Vui lòng đợi rồi thử lại.');
const consentRequired = () => new HttpError(403, 'consent_required', 'Bạn chưa đồng ý chia sẻ phần dữ liệu này với phòng khám.');
const badUpload = (fields) => new HttpError(400, 'bad_upload', 'Dữ liệu gửi lên không hợp lệ.', fields);

/** Fixed-window counters keyed by string. */
function createLimiter(windowMs, max) {
  const hits = new Map();
  const sweep = setInterval(() => {
    const t = Date.now();
    for (const [k, h] of hits) if (t - h.start >= windowMs) hits.delete(k);
  }, Math.min(windowMs, 60_000));
  sweep.unref();
  return {
    /** Counts a hit; false when over the limit. */
    hit(key) {
      const t = Date.now();
      let h = hits.get(key);
      if (!h || t - h.start >= windowMs) hits.set(key, (h = { start: t, count: 0 }));
      return ++h.count <= max;
    },
    reset: () => hits.clear(),
    close() {
      clearInterval(sweep);
      hits.clear();
    },
  };
}

/**
 * [onIntake](appointmentId) is called after intake answers are stored, or
 * sharing of them is granted (bước 17 summary); it must not block.
 */
export function createPatientApi({ db, config, log, onIntake = () => {} }) {
  const q = (sql) => db.prepare(sql);
  const otpByPhone = createLimiter(OTP_WINDOW_MS, OTP_PER_PHONE);
  const otpByIp = createLimiter(OTP_WINDOW_MS, OTP_PER_IP);
  const uploads = createLimiter(60_000, UPLOADS_PER_MINUTE);

  const stmt = {
    knownPhone: q('SELECT 1 FROM patient WHERE phone = ? LIMIT 1'),
    nameOf: q(`SELECT p.full_name FROM patient p LEFT JOIN appointment a ON a.patient_id = p.id
      WHERE p.phone = ? ORDER BY a.starts_at DESC LIMIT 1`),
    putOtp: q(`INSERT INTO patient_otp (phone, code_hash, expires_at, attempts, created_at) VALUES (?, ?, ?, 0, ?)
      ON CONFLICT (phone) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at,
      attempts = 0, created_at = excluded.created_at`),
    otp: q('SELECT * FROM patient_otp WHERE phone = ?'),
    otpAttempt: q('UPDATE patient_otp SET attempts = attempts + 1 WHERE phone = ?'),
    dropOtp: q('DELETE FROM patient_otp WHERE phone = ?'),
    newSession: q('INSERT INTO patient_session (token_hash, phone, created_at, expires_at) VALUES (?, ?, ?, ?)'),
    session: q('SELECT * FROM patient_session WHERE token_hash = ?'),
    revokeSession: q('UPDATE patient_session SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL'),
    appointments: q(`SELECT a.*, c.name AS clinic_name, c.phone AS clinic_phone FROM appointment a
      JOIN patient p ON p.id = a.patient_id JOIN clinic c ON c.id = a.clinic_id
      WHERE p.phone = ? ORDER BY a.starts_at DESC, a.id DESC`),
    appointment: q(`SELECT a.*, p.full_name, p.birth_date, p.gender, p.address, p.weight_kg, p.insurance_code,
      c.name AS clinic_name, c.phone AS clinic_phone FROM appointment a
      JOIN patient p ON p.id = a.patient_id JOIN clinic c ON c.id = a.clinic_id
      WHERE a.id = ? AND p.phone = ?`),
    hasSent: q("SELECT 1 FROM visit_result WHERE appointment_id = ? AND status = 'sent' LIMIT 1"),
    sentResult: q(`SELECT r.*, pr.title, pr.full_name AS doctor_name FROM visit_result r
      LEFT JOIN practitioner pr ON pr.id = r.signed_by
      WHERE r.appointment_id = ? AND r.status = 'sent' ORDER BY r.version DESC LIMIT 1`),
    consent: q('SELECT * FROM consent WHERE appointment_id = ? ORDER BY granted_at DESC, rowid DESC LIMIT 1'),
    revokeConsents: q('UPDATE consent SET revoked_at = ? WHERE appointment_id = ? AND revoked_at IS NULL'),
    insertConsent: q(`INSERT INTO consent (id, appointment_id, scope, wording_version, granted_at, expires_at, revoked_at)
      VALUES (?, ?, ?, ?, ?, ?, NULL)`),
    intakeCount: q('SELECT count(*) AS n FROM intake_answer WHERE appointment_id = ?'),
    upsertIntake: q(`INSERT INTO intake_answer (id, appointment_id, channel, question, answer, answered_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET channel = excluded.channel, question = excluded.question,
      answer = excluded.answer, answered_at = excluded.answered_at`),
    selfMeds: q('SELECT name, how FROM self_medication WHERE appointment_id = ? ORDER BY rowid'),
    clearSelfMeds: q('DELETE FROM self_medication WHERE appointment_id = ?'),
    insertSelfMed: q('INSERT INTO self_medication (id, appointment_id, name, how) VALUES (?, ?, ?, ?)'),
    patientsOf: q('SELECT id FROM patient WHERE phone = ?'),
    consentsOfPatient: q('SELECT id FROM appointment WHERE patient_id = ?'),
    course: q('SELECT 1 FROM med_course WHERE patient_id = ? AND id = ?'),
    upsertDose: q(`INSERT INTO dose_event (patient_id, course_id, day, slot, mark, reason, recorded_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (patient_id, course_id, day, slot) DO UPDATE SET mark = excluded.mark,
      reason = excluded.reason, recorded_at = excluded.recorded_at`),
    audit: q(`INSERT INTO audit_event (at, actor, action, patient_id, appointment_id, detail, ip)
      VALUES (?, 'patient', ?, ?, ?, ?, ?)`),
  };

  const ipOf = (req) => req.socket.remoteAddress ?? '';
  const audit = (req, action, a, detail = {}) =>
    stmt.audit.run(localIso(), action, a.patient_id, a.id, JSON.stringify(detail), ipOf(req));
  const codeHash = (phone, code) => createHmac('sha256', config.otpPepper).update(`${phone}:${code}`).digest('base64url');

  function atomically(fn) {
    db.exec('BEGIN IMMEDIATE');
    try {
      const out = fn();
      db.exec('COMMIT');
      return out;
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  }

  // ---- sign-in -------------------------------------------------------------

  async function requestOtp(req, res) {
    if (config.patientOtpMode === 'off') {
      throw new HttpError(503, 'otp_unavailable', 'Chưa gửi được mã xác nhận. Vui lòng thử lại sau.');
    }
    const body = await readJson(req);
    const phone = normalizePhone(body.phone);
    if (!phone) throw badPhone();
    const okIp = otpByIp.hit(ipOf(req));
    const okPhone = otpByPhone.hit(phone);
    if (!okIp || !okPhone) {
      log('patient_otp', { result: 'rate_limited' });
      throw rateLimited();
    }
    const code = config.demoOtp ?? String(randomInt(0, 1_000_000)).padStart(6, '0');
    // Unknown phones get the same answer, but no code is stored.
    if (stmt.knownPhone.get(phone)) {
      const t = Date.now();
      stmt.putOtp.run(phone, codeHash(phone, code), localIso(t + OTP_TTL_S * 1000), localIso(t));
    }
    // Dev only (no SMS provider yet): the code goes to the log and the answer.
    log('patient_otp', { phone: maskPhone(phone), code });
    return sendJson(res, 202, { expiresIn: OTP_TTL_S, devCode: code });
  }

  async function signIn(req, res) {
    const body = await readJson(req);
    const phone = normalizePhone(body.phone);
    if (!phone) throw badPhone();
    const code = typeof body.code === 'string' ? body.code.trim() : '';
    const now = localIso();
    const row = stmt.otp.get(phone);
    if (!row || row.expires_at <= now || row.attempts >= OTP_MAX_ATTEMPTS) {
      if (row) stmt.dropOtp.run(phone);
      log('patient_login', { result: 'bad_code' });
      throw badCode();
    }
    stmt.otpAttempt.run(phone);
    const expected = Buffer.from(row.code_hash);
    const got = Buffer.from(codeHash(phone, code));
    if (!/^\d{6}$/.test(code) || expected.length !== got.length || !timingSafeEqual(expected, got)) {
      if (row.attempts + 1 >= OTP_MAX_ATTEMPTS) stmt.dropOtp.run(phone);
      log('patient_login', { result: 'bad_code' });
      throw badCode();
    }
    stmt.dropOtp.run(phone);
    const token = randomBytes(32).toString('base64url');
    const expiresAt = localIso(Date.now() + SESSION_DAYS * DAY_MS);
    stmt.newSession.run(sha256(token), phone, now, expiresAt);
    log('patient_login', { result: 'ok' });
    return sendJson(res, 200, { token, expiresAt, patient: { phone, name: stmt.nameOf.get(phone)?.full_name ?? '' } });
  }

  const bearer = (req) => {
    const m = /^Bearer\s+([A-Za-z0-9_-]{20,100})\s*$/.exec(req.headers.authorization ?? '');
    return m ? m[1] : null;
  };

  function requirePatient(req) {
    const token = bearer(req);
    const s = token ? stmt.session.get(sha256(token)) : null;
    if (!s || s.revoked_at || s.expires_at <= localIso()) throw unauthenticated();
    return { phone: s.phone, tokenHash: s.token_hash };
  }

  function signOut(req, res) {
    const token = bearer(req);
    if (token && stmt.revokeSession.run(localIso(), sha256(token)).changes) log('patient_logout', {});
    res.writeHead(204, { 'cache-control': 'no-store' });
    return res.end();
  }

  // ---- read models ---------------------------------------------------------

  /** Latest consent row of the visit, as the patient sees it; null when none. */
  function consentView(appointmentId, now = localIso()) {
    const row = stmt.consent.get(appointmentId);
    if (!row) return null;
    const state = row.revoked_at ? 'revoked' : row.expires_at <= now ? 'expired' : 'shared';
    return {
      state,
      scope: json(row.scope, []),
      grantedAt: row.granted_at,
      expiresAt: row.expires_at,
      revokedAt: row.revoked_at ?? null,
    };
  }

  const activeScope = (appointmentId) => {
    const c = consentView(appointmentId);
    return c && c.state === 'shared' ? c.scope : [];
  };

  function findAppointment(id, who) {
    const a = typeof id === 'string' ? stmt.appointment.get(id, who.phone) : null;
    if (!a) throw notFound();
    return a;
  }

  function appointments(req, res, who) {
    const now = localIso();
    const items = stmt.appointments.all(who.phone).map((a) => ({
      id: a.id,
      clinic: { id: a.clinic_id, name: a.clinic_name, phone: a.clinic_phone },
      startsAt: a.starts_at,
      time: a.starts_at.slice(11, 16),
      specialty: a.specialty,
      kind: a.kind,
      status: a.status,
      // A draft (first or amendment) is not the patient's business yet.
      resultStatus: stmt.hasSent.get(a.id) ? 'sent' : 'none',
      consent: consentView(a.id, now),
      intakeCount: stmt.intakeCount.get(a.id).n,
      selfMeds: stmt.selfMeds.all(a.id).map((m) => ({ name: m.name, how: m.how })),
    }));
    return sendJson(res, 200, items);
  }

  function result(req, res, who, id) {
    const a = findAppointment(id, who);
    const r = stmt.sentResult.get(a.id);
    if (!r) throw notFound();
    audit(req, 'result.view', a, { version: r.version });
    log('result_view', {});
    return sendJson(res, 200, visitResultJson(a, r));
  }

  // ---- consent -------------------------------------------------------------

  async function grant(req, res, who, id) {
    const a = findAppointment(id, who);
    const body = await readJson(req);
    const bad = [];
    const scope = body.scope;
    if (!Array.isArray(scope) || !scope.length || scope.some((s) => !SCOPES.includes(s)) || new Set(scope).size !== scope.length) {
      bad.push('scope');
    }
    if (!Number.isInteger(body.wordingVersion) || body.wordingVersion < 1 || body.wordingVersion > 1000) bad.push('wordingVersion');
    if (bad.length) throw new HttpError(422, 'bad_consent', 'Phạm vi chia sẻ không hợp lệ.', bad);
    if (a.status === 'cancelled') throw new HttpError(409, 'bad_state', 'Lượt khám đã hủy.');
    const t = Date.now();
    const now = localIso(t);
    // 30 days after the visit; when that has already passed, 30 days from now.
    let end = Date.parse(a.starts_at) + CONSENT_DAYS * DAY_MS;
    if (end <= t) end = t + CONSENT_DAYS * DAY_MS;
    const ordered = SCOPES.filter((s) => scope.includes(s));
    atomically(() => {
      stmt.revokeConsents.run(now, a.id);
      stmt.insertConsent.run(`cs-${randomUUID()}`, a.id, JSON.stringify(ordered), body.wordingVersion, now, localIso(end));
    });
    audit(req, 'consent.grant', a, { scope: ordered, wordingVersion: body.wordingVersion });
    log('consent_grant', { scope: ordered.length });
    if (ordered.includes('intake') && stmt.intakeCount.get(a.id).n) onIntake(a.id);
    return sendJson(res, 200, consentView(a.id));
  }

  function revoke(req, res, who, id) {
    const a = findAppointment(id, who);
    if (!stmt.consent.get(a.id)) throw new HttpError(404, 'not_found', 'Chưa có đồng ý chia sẻ cho lượt khám này.');
    const changed = stmt.revokeConsents.run(localIso(), a.id).changes;
    if (changed) {
      audit(req, 'consent.revoke', a);
      log('consent_revoke', {});
    }
    return sendJson(res, 200, consentView(a.id));
  }

  // ---- uploads -------------------------------------------------------------

  async function readUpload(req, who) {
    if (!uploads.hit(who.tokenHash)) throw rateLimited();
    return readJson(req, UPLOAD_BODY);
  }

  async function putIntake(req, res, who, id) {
    const a = findAppointment(id, who);
    const body = await readUpload(req, who);
    const answers = body.answers;
    if (!Array.isArray(answers) || answers.length > MAX_ANSWERS) throw badUpload(['answers']);
    const bad = [];
    answers.forEach((x, i) => {
      const p = `answers[${i}]`;
      if (!x || typeof x !== 'object') return bad.push(p);
      if (!isText(x.id, 64, 1)) bad.push(`${p}.id`);
      if (x.channel !== 'booking' && x.channel !== 'pre_visit') bad.push(`${p}.channel`);
      if (x.question != null && !isText(x.question, 300)) bad.push(`${p}.question`);
      if (!isText(x.answer, 2000, 1)) bad.push(`${p}.answer`);
      if (!isoTime(x.answeredAt)) bad.push(`${p}.answeredAt`);
      return undefined;
    });
    if (bad.length) throw badUpload(bad);
    if (!activeScope(a.id).includes('intake')) throw consentRequired();
    atomically(() => {
      for (const x of answers) {
        // Namespaced per visit: a client id can never reach another visit's row.
        stmt.upsertIntake.run(`${a.id}/${x.id.trim()}`, a.id, x.channel, (x.question ?? '').trim(), x.answer.trim(),
          localIso(Date.parse(x.answeredAt)));
      }
    });
    audit(req, 'intake.upload', a, { answers: answers.length });
    log('patient_upload', { kind: 'intake', n: answers.length });
    if (answers.length) onIntake(a.id);
    return sendJson(res, 200, { count: stmt.intakeCount.get(a.id).n });
  }

  async function putSelfMeds(req, res, who, id) {
    const a = findAppointment(id, who);
    const body = await readUpload(req, who);
    const items = body.items;
    if (!Array.isArray(items) || items.length > MAX_SELF_MEDS) throw badUpload(['items']);
    const bad = [];
    items.forEach((x, i) => {
      if (!x || typeof x !== 'object') return bad.push(`items[${i}]`);
      if (!isText(x.name, 120, 1)) bad.push(`items[${i}].name`);
      if (x.how != null && !isText(x.how, 200)) bad.push(`items[${i}].how`);
      return undefined;
    });
    if (bad.length) throw badUpload(bad);
    if (!activeScope(a.id).includes('self_meds')) throw consentRequired();
    atomically(() => {
      stmt.clearSelfMeds.run(a.id);
      items.forEach((x, k) => stmt.insertSelfMed.run(`sm-${a.id}-${k + 1}`, a.id, x.name.trim(), (x.how ?? '').trim()));
    });
    audit(req, 'self_meds.upload', a, { items: items.length });
    log('patient_upload', { kind: 'self_meds', n: items.length });
    return sendJson(res, 200, { count: items.length });
  }

  async function postDoseEvents(req, res, who) {
    const body = await readUpload(req, who);
    const events = body.events;
    if (!Array.isArray(events) || events.length > MAX_DOSE_EVENTS) throw badUpload(['events']);
    const bad = [];
    events.forEach((e, i) => {
      const p = `events[${i}]`;
      if (!e || typeof e !== 'object') return bad.push(p);
      if (!isText(e.courseId, 160, 1)) bad.push(`${p}.courseId`);
      if (!parseDay(e.day)) bad.push(`${p}.day`);
      if (!SLOTS.includes(e.slot)) bad.push(`${p}.slot`);
      if (e.mark !== 'taken' && e.mark !== 'skipped') bad.push(`${p}.mark`);
      if (e.reason != null && !REASONS.includes(e.reason)) bad.push(`${p}.reason`);
      if (!isoTime(e.at)) bad.push(`${p}.at`);
      return undefined;
    });
    if (bad.length) throw badUpload(bad);
    // Patients (of this phone) with at least one live consent covering dose_log.
    const sharing = stmt.patientsOf.all(who.phone).map((p) => p.id)
      .filter((pid) => stmt.consentsOfPatient.all(pid).some((a) => activeScope(a.id).includes('dose_log')));
    if (!sharing.length) throw consentRequired();
    const ignored = new Set();
    let accepted = 0;
    atomically(() => {
      for (const e of events) {
        const owner = sharing.find((pid) => stmt.course.get(pid, e.courseId));
        if (!owner) {
          ignored.add(e.courseId);
          continue;
        }
        stmt.upsertDose.run(owner, e.courseId, e.day, e.slot, e.mark, e.mark === 'skipped' ? (e.reason ?? null) : null,
          localIso(Date.parse(e.at)));
        accepted++;
      }
    });
    log('patient_upload', { kind: 'dose_log', n: accepted, ignored: ignored.size });
    return sendJson(res, 200, { accepted, ignored: [...ignored] });
  }

  /** Answers `/v1/patient/...`; [parts] are the decoded path segments. */
  async function handle(req, res, parts) {
    const [, , area, id, sub] = parts;
    const m = req.method;
    if (area === 'otp' && parts.length === 3 && m === 'POST') return requestOtp(req, res);
    if (area === 'session' && parts.length === 3) {
      if (m === 'POST') return signIn(req, res);
      if (m === 'DELETE') return signOut(req, res);
    }
    const who = requirePatient(req);
    if (area === 'appointments') {
      if (parts.length === 3 && m === 'GET') return appointments(req, res, who);
      if (parts.length === 5) {
        if (sub === 'result' && m === 'GET') return result(req, res, who, id);
        if (sub === 'consent' && m === 'PUT') return grant(req, res, who, id);
        if (sub === 'consent' && m === 'DELETE') return revoke(req, res, who, id);
        if (sub === 'intake' && m === 'PUT') return putIntake(req, res, who, id);
        if (sub === 'self-meds' && m === 'PUT') return putSelfMeds(req, res, who, id);
      }
    }
    if (area === 'dose-events' && parts.length === 3 && m === 'POST') return postDoseEvents(req, res, who);
    throw notFound();
  }

  return {
    handle,
    /** Tests only: forget the rate-limit windows. */
    resetLimits() {
      otpByPhone.reset();
      otpByIp.reset();
      uploads.reset();
    },
    close() {
      otpByPhone.close();
      otpByIp.close();
      uploads.close();
    },
  };
}
