// Doctor web API (CLINIC-API.md): staff sign-in, worklist, chart, summary
// feedback, arrive/start, visit history, result drafts and sending (bước 15),
// the patient's claim by code, and (bước 18) own password, accounts, access
// log and pilot numbers for the clinic admin. Every query is scoped to the
// signed-in staff's clinic; another clinic's ids answer 404. Clinical data is
// for doctors only; the admin role manages accounts and sees no charts. Logs
// carry event names and codes only, never names, symptoms or tokens.
import { HttpError, notFound, readJson, sendJson } from '../http.js';
import {
  LOCK_MS, MAX_FAILED, clearCookie, createSessionStore, hashPassword, passwordProblem, readCookie, sessionCookie,
  verifyPassword,
} from './auth.js';
import { createAdminApi } from './admin.js';
import { readFileSync } from 'node:fs';

import { createSummaryWorker } from '../summary/worker.js';
import { createFamilyApi } from '../family/api.js';
import { createPatientApi } from './patient.js';

import {
  formatClaimCode, missingForSend, newClaimCode, normalizeClaimCode, parseDraft,
} from './prescription.js';
import { addDays, ageOn, localIso, parseDay, today } from './time.js';

export const CLINIC_PREFIXES = ['staff', 'clinic', 'appointments', 'summaries', 'patients', 'results', 'patient', 'family'];
export const CLAIM_DAYS = 30;
export const CLAIM_PER_MINUTE = 10;

/** Sample drug and ICD-10 list (catalog/clinic-catalog.json). */
export const clinicCatalog = JSON.parse(readFileSync(new URL('../../catalog/clinic-catalog.json', import.meta.url), 'utf8'));
export const PERIOD_DAYS = 30;

const unauthenticated = () => new HttpError(401, 'unauthenticated', 'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại.');
const json = (text, fallback) => {
  try {
    return text == null ? fallback : JSON.parse(text);
  } catch {
    return fallback;
  }
};

const staffJson = (p) => ({
  id: p.id,
  name: `${p.title} ${p.full_name}`.trim(),
  role: p.role,
  mustChangePassword: Boolean(p.must_change_password),
});
const forbidden = () => new HttpError(403, 'forbidden', 'Tài khoản của bạn không có quyền dùng chức năng này.');
const clinicJson = (c) => ({ id: c.id, name: c.name, phone: c.phone });
const maskInsurance = (code) => (code ? `•••• ${code.slice(-4)}` : null);

/**
 * A sent result as medic_core VisitResult (without visitId, profileId): the
 * body of the claim by code and of the signed-in patient's result view.
 * [a] is the appointment joined with patient and clinic (clinic_name,
 * clinic_phone); [r] the sent visit_result joined with the signer.
 */
export function visitResultJson(a, r) {
  const day = a.starts_at.slice(0, 10);
  const advice = r.advice.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (r.follow_up_date) {
    const [y, m, d] = r.follow_up_date.split('-');
    advice.push(`Hẹn tái khám ngày ${d}/${m}/${y}.`);
  }
  return {
    appointmentId: a.id,
    version: r.version,
    issuedAt: r.signed_at,
    facilityName: a.clinic_name,
    facilityPhone: a.clinic_phone,
    doctorName: r.doctor_name ? `${r.title} ${r.doctor_name}`.trim() : '',
    patientName: a.full_name,
    patientAge: ageOn(a.birth_date, day),
    patientGender: a.gender,
    address: a.address,
    insuranceCode: maskInsurance(a.insurance_code) ?? '',
    weightKg: a.weight_kg ?? null,
    diagnosis: json(r.diagnosis, []).map(([c, n]) => `${n} (${c})`).join('; '),
    items: json(r.items, []),
    advice,
    followUpDate: r.follow_up_date ?? null,
  };
}

/**
 * [summary]: options for the bước 17 summary worker (tests pass
 * `summarise` and `debounceMs`).
 */
export function createClinicApi({ db, config, log, summary = {} }) {
  const store = createSessionStore();
  const summaries = createSummaryWorker({ db, config, log, ...summary });
  const patient = createPatientApi({ db, config, log, onIntake: (id) => summaries.schedule(id) });
  const family = createFamilyApi({ db, log });
  const q = (sql) => db.prepare(sql);

  const stmt = {
    staffByEmail: q('SELECT * FROM practitioner WHERE email = ?'),
    staffById: q('SELECT * FROM practitioner WHERE id = ?'),
    clinic: q('SELECT * FROM clinic WHERE id = ?'),
    loginFailed: q('UPDATE practitioner SET failed_logins = ?, locked_until = ? WHERE id = ?'),
    loginOk: q('UPDATE practitioner SET failed_logins = 0, locked_until = NULL, last_login_at = ? WHERE id = ?'),
    passwordOk: q('UPDATE practitioner SET failed_logins = 0, locked_until = NULL WHERE id = ?'),
    setPassword: q(`UPDATE practitioner SET password_hash = ?, must_change_password = 0, password_changed_at = ?
      WHERE id = ?`),
    audit: q(`INSERT INTO audit_event (at, actor, action, patient_id, appointment_id, detail, ip)
      VALUES (?, ?, ?, ?, ?, ?, ?)`),
    day: q(`SELECT a.*, p.code, p.full_name, p.birth_date, p.gender FROM appointment a
      JOIN patient p ON p.id = a.patient_id
      WHERE a.clinic_id = ? AND a.starts_at >= ? AND a.starts_at < ? ORDER BY a.starts_at, a.id`),
    appointment: q(`SELECT a.*, p.code, p.full_name, p.birth_date, p.gender, p.address, p.weight_kg,
      p.insurance_code, p.allergy, p.conditions FROM appointment a
      JOIN patient p ON p.id = a.patient_id WHERE a.id = ? AND a.clinic_id = ?`),
    consent: q('SELECT * FROM consent WHERE appointment_id = ? ORDER BY granted_at DESC, rowid DESC LIMIT 1'),
    summary: q('SELECT * FROM visit_summary WHERE appointment_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1'),
    summaryById: q(`SELECT s.*, a.patient_id, a.clinic_id FROM visit_summary s
      JOIN appointment a ON a.id = s.appointment_id WHERE s.id = ? AND a.clinic_id = ?`),
    feedback: q('UPDATE visit_summary SET feedback = ?, feedback_by = ?, feedback_at = ? WHERE id = ?'),
    intake: q('SELECT * FROM intake_answer WHERE appointment_id = ? ORDER BY answered_at, id'),
    selfMeds: q('SELECT name, how FROM self_medication WHERE appointment_id = ? ORDER BY rowid'),
    courses: q('SELECT * FROM med_course WHERE patient_id = ? ORDER BY prescribed_at, id'),
    doses: q(`SELECT * FROM dose_event WHERE patient_id = ? AND day >= ? AND day <= ?
      ORDER BY day, course_id, slot`),
    latestResult: q('SELECT * FROM visit_result WHERE appointment_id = ? ORDER BY version DESC LIMIT 1'),
    insertResult: q(`INSERT INTO visit_result (id, appointment_id, version, status, diagnosis, items, advice,
      follow_up_date, internal_note, amend_reason, updated_at) VALUES (?, ?, ?, 'draft', ?, ?, ?, ?, ?, ?, ?)`),
    updateDraft: q(`UPDATE visit_result SET diagnosis = ?, items = ?, advice = ?, follow_up_date = ?, internal_note = ?,
      updated_at = ? WHERE id = ? AND status = 'draft'`),
    markAmended: q("UPDATE visit_result SET status = 'amended' WHERE appointment_id = ? AND status = 'sent'"),
    markSent: q("UPDATE visit_result SET status = 'sent', signed_by = ?, signed_at = ?, updated_at = ? WHERE id = ? AND status = 'draft'"),
    claimTaken: q('SELECT 1 FROM appointment WHERE claim_code = ?'),
    setClaim: q('UPDATE appointment SET claim_code = ?, claim_expires_at = ? WHERE id = ? AND claim_code IS NULL'),
    setDone: q("UPDATE appointment SET status = 'done', practitioner_id = coalesce(practitioner_id, ?) WHERE id = ?"),
    firstSigned: q('SELECT min(signed_at) AS at FROM visit_result WHERE appointment_id = ? AND signed_at IS NOT NULL'),
    upsertCourse: q(`INSERT INTO med_course (id, patient_id, item, prescribed_at) VALUES (?, ?, ?, ?)
      ON CONFLICT (patient_id, id) DO UPDATE SET item = excluded.item, prescribed_at = excluded.prescribed_at`),
    coursesOfPatient: q('SELECT id FROM med_course WHERE patient_id = ?'),
    deleteCourse: q('DELETE FROM med_course WHERE patient_id = ? AND id = ?'),
    byClaim: q(`SELECT a.*, p.full_name, p.birth_date, p.gender, p.address, p.weight_kg, p.insurance_code,
      c.name AS clinic_name, c.phone AS clinic_phone FROM appointment a
      JOIN patient p ON p.id = a.patient_id JOIN clinic c ON c.id = a.clinic_id WHERE a.claim_code = ?`),
    sentResult: q(`SELECT r.*, pr.title, pr.full_name AS doctor_name FROM visit_result r
      LEFT JOIN practitioner pr ON pr.id = r.signed_by
      WHERE r.appointment_id = ? AND r.status = 'sent' ORDER BY r.version DESC LIMIT 1`),
    results: q(`SELECT r.*, a.starts_at, a.id AS appt_id, c.name AS clinic_name, pr.title, pr.full_name AS doctor_name
      FROM visit_result r
      JOIN appointment a ON a.id = r.appointment_id
      JOIN clinic c ON c.id = a.clinic_id
      LEFT JOIN practitioner pr ON pr.id = r.signed_by
      WHERE a.patient_id = ? AND a.clinic_id = ? AND r.status = 'sent'
      ORDER BY a.starts_at DESC, r.version DESC`),
    patient: q('SELECT id FROM patient WHERE id = ? AND clinic_id = ?'),
    setStatus: q('UPDATE appointment SET status = ?, practitioner_id = coalesce(practitioner_id, ?) WHERE id = ? AND clinic_id = ?'),
  };

  function audit(req, staff, action, { patientId = null, appointmentId = null, detail = {} } = {}) {
    stmt.audit.run(localIso(), staff.id, action, patientId, appointmentId, JSON.stringify(detail), req.socket.remoteAddress ?? '');
  }

  /**
   * The signed-in staff. A deactivated account is signed out on its next
   * request. Until a one-time password is replaced, only `me`, `logout` and
   * `password` answer ([pending] true); the rest is 403 password_change_required.
   */
  function requireStaff(req, { pending = false } = {}) {
    const token = readCookie(req);
    const session = store.get(token);
    if (!session) throw unauthenticated();
    const staff = stmt.staffById.get(session.staffId);
    if (!staff || staff.clinic_id !== session.clinicId || !staff.active) {
      store.delete(token);
      throw unauthenticated();
    }
    if (staff.must_change_password && !pending) {
      throw new HttpError(403, 'password_change_required', 'Cần đổi mật khẩu tạm trước khi tiếp tục.');
    }
    return staff;
  }

  /** Clinical endpoints: doctors only. */
  function requireDoctor(staff) {
    if (staff.role !== 'doctor') throw forbidden();
    return staff;
  }

  const admin = createAdminApi({ db, log, store, audit, staffJson });

  /**
   * Checks [password] against the account and applies the lockout rule
   * (5 wrong in a row: locked 15 minutes). 'ok', 'bad' or 'locked'.
   */
  async function checkPassword(staff, password) {
    const nowMs = Date.now();
    if (staff.locked_until && Date.parse(staff.locked_until) > nowMs) return 'locked';
    if (await verifyPassword(password, staff.password_hash)) return 'ok';
    const failed = (staff.locked_until ? 0 : staff.failed_logins) + 1;
    if (failed >= MAX_FAILED) {
      stmt.loginFailed.run(0, localIso(nowMs + LOCK_MS), staff.id);
      return 'locked';
    }
    stmt.loginFailed.run(failed, null, staff.id);
    return 'bad';
  }

  // ---- read models -------------------------------------------------------

  /**
   * The latest consent row of the visit. `reason` tells why it is
   * `declined`: 'revoked' (withdrawn or refused) or 'expired'.
   */
  function consentOf(appointmentId, now) {
    const row = stmt.consent.get(appointmentId);
    if (!row) return { state: 'none', grantedAt: null, expiresAt: null, scope: [], reason: null, revokedAt: null };
    const scope = json(row.scope, []);
    const reason = row.revoked_at ? 'revoked' : row.expires_at <= now ? 'expired' : null;
    if (reason || !scope.length) {
      return { state: 'declined', grantedAt: null, expiresAt: null, scope: [], reason, revokedAt: row.revoked_at ?? null };
    }
    return { state: 'shared', grantedAt: row.granted_at, expiresAt: row.expires_at, scope, reason: null, revokedAt: null };
  }

  /** Status of the newest version: `draft` while an amendment is open. */
  function resultStatusOf(appointmentId) {
    const latest = stmt.latestResult.get(appointmentId);
    if (!latest) return 'none';
    return latest.status === 'draft' ? 'draft' : 'sent';
  }

  function signerName(id) {
    const p = id ? stmt.staffById.get(id) : null;
    return p ? staffJson(p).name : null;
  }

  const resultDraftJson = (r, claimCode) => ({
    id: r.id,
    appointmentId: r.appointment_id,
    version: r.version,
    status: r.status,
    diagnosis: json(r.diagnosis, []),
    items: json(r.items, []),
    advice: r.advice,
    followUpDate: r.follow_up_date ?? null,
    internalNote: r.internal_note,
    amendReason: r.amend_reason ?? null,
    signedBy: signerName(r.signed_by),
    signedAt: r.signed_at ?? null,
    updatedAt: r.updated_at,
    claimCode: formatClaimCode(claimCode),
  });

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

  const appointmentJson = (a) => ({
    id: a.id,
    time: a.starts_at.slice(11, 16),
    startsAt: a.starts_at,
    status: a.status,
    kind: a.kind,
    specialty: a.specialty,
    resultStatus: resultStatusOf(a.id),
  });

  const periodOf = (a) => {
    const day = a.starts_at.slice(0, 10);
    return { from: addDays(day, -PERIOD_DAYS), to: addDays(day, -1), days: PERIOD_DAYS };
  };

  /** Courses active during the period, and the doses recorded for them in it. */
  function medsOf(patientId, period) {
    const courses = [];
    for (const row of stmt.courses.all(patientId)) {
      const item = json(row.item, null);
      if (!item) continue;
      const first = row.prescribed_at.slice(0, 10);
      const last = addDays(first, Math.max(1, item.days) - 1);
      if (first > period.to || last < period.from) continue;
      courses.push({ id: row.id, visitId: row.id.split('#')[0], prescribedAt: row.prescribed_at, item });
    }
    const ids = new Set(courses.map((c) => c.id));
    const doseLog = stmt.doses.all(patientId, period.from, period.to)
      .filter((d) => ids.has(d.course_id))
      .map((d) => ({ courseId: d.course_id, day: d.day, slot: d.slot, mark: d.mark, at: d.recorded_at, reason: d.reason ?? null }));
    return { courses, doseLog };
  }

  function summaryOf(appointmentId) {
    const s = stmt.summary.get(appointmentId);
    if (!s) return null;
    let feedback = null;
    if (s.feedback) {
      const by = s.feedback_by ? stmt.staffById.get(s.feedback_by) : null;
      feedback = { value: s.feedback, by: by ? staffJson(by).name : null, at: s.feedback_at };
    }
    return {
      id: s.id,
      mode: s.mode,
      createdAt: s.created_at,
      sections: json(s.sections, []),
      flags: json(s.flags, []),
      feedback,
    };
  }

  const historyJson = (r) => ({
    appointmentId: r.appt_id,
    date: r.starts_at.slice(0, 10),
    clinicName: r.clinic_name,
    doctorName: r.doctor_name ? `${r.title} ${r.doctor_name}`.trim() : '',
    diagnosis: json(r.diagnosis, []),
    items: json(r.items, []),
    advice: r.advice,
    followUpDate: r.follow_up_date ?? null,
    version: r.version,
  });

  const patientBrief = (a, day) => ({
    id: a.patient_id,
    code: a.code,
    name: a.full_name,
    age: ageOn(a.birth_date, day),
    gender: a.gender,
  });

  // ---- handlers ----------------------------------------------------------

  async function login(req, res) {
    const body = await readJson(req);
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    const password = typeof body.password === 'string' ? body.password : '';
    const bad = () => new HttpError(401, 'bad_credentials', 'Email hoặc mật khẩu không đúng.');
    const locked = () => new HttpError(423, 'locked', 'Tài khoản tạm khóa 15 phút vì nhập sai nhiều lần.');
    if (!email || email.length > 254 || !password || password.length > 256) throw bad();
    const staff = stmt.staffByEmail.get(email);
    if (!staff) {
      await verifyPassword(password, null); // keep timing close to a real check
      log('staff_login', { result: 'bad_credentials' });
      throw bad();
    }
    const check = await checkPassword(staff, password);
    if (check !== 'ok') {
      log('staff_login', { result: check === 'locked' ? 'locked' : 'bad_credentials' });
      throw check === 'locked' ? locked() : bad();
    }
    // Only after the right password, so the answer does not reveal accounts.
    if (!staff.active) {
      log('staff_login', { result: 'disabled' });
      throw new HttpError(403, 'account_disabled', 'Tài khoản đã bị khóa. Vui lòng liên hệ quản trị phòng khám.');
    }
    stmt.loginOk.run(localIso(), staff.id);
    const token = store.create(staff);
    log('staff_login', { result: 'ok', mustChange: Boolean(staff.must_change_password) });
    return sendJson(res, 200, { staff: staffJson(staff), clinic: clinicJson(stmt.clinic.get(staff.clinic_id)) }, {
      'set-cookie': sessionCookie(token, { secure: config.https }),
    });
  }

  /**
   * POST /v1/staff/password { currentPassword, newPassword }. Wrong current
   * passwords count toward the lockout; a lockout ends the account's sessions.
   * Other sessions of the account end; this one stays.
   */
  async function changePassword(req, res) {
    const staff = requireStaff(req, { pending: true });
    const body = await readJson(req);
    const current = typeof body.currentPassword === 'string' ? body.currentPassword : '';
    const next = typeof body.newPassword === 'string' ? body.newPassword : '';
    const problem = passwordProblem(next, staff.email);
    if (problem) throw new HttpError(422, 'weak_password', problem, ['newPassword']);
    if (!current || current.length > 256) throw new HttpError(400, 'wrong_password', 'Mật khẩu hiện tại không đúng.', ['currentPassword']);
    const check = await checkPassword(staff, current);
    if (check === 'locked') {
      store.endFor(staff.id);
      log('staff_password', { result: 'locked' });
      throw new HttpError(423, 'locked', 'Tài khoản tạm khóa 15 phút vì nhập sai nhiều lần.');
    }
    if (check === 'bad') {
      log('staff_password', { result: 'wrong_password' });
      throw new HttpError(400, 'wrong_password', 'Mật khẩu hiện tại không đúng.', ['currentPassword']);
    }
    if (next === current) throw new HttpError(422, 'weak_password', 'Mật khẩu mới cần khác mật khẩu hiện tại.', ['newPassword']);
    stmt.passwordOk.run(staff.id);
    stmt.setPassword.run(await hashPassword(next), localIso(), staff.id);
    const ended = store.endFor(staff.id, readCookie(req));
    audit(req, staff, 'staff.password_change', { detail: { sessionsEnded: ended, wasTemporary: Boolean(staff.must_change_password) } });
    log('staff_password', { result: 'ok' });
    const fresh = stmt.staffById.get(staff.id);
    return sendJson(res, 200, { staff: staffJson(fresh), clinic: clinicJson(stmt.clinic.get(staff.clinic_id)) });
  }

  function worklist(req, res, staff, url) {
    const raw = url.searchParams.get('date');
    const date = raw == null || raw === '' ? today() : parseDay(raw);
    if (!date) throw new HttpError(400, 'bad_date', 'Ngày không hợp lệ.');
    const now = localIso();
    const items = stmt.day.all(staff.clinic_id, date, addDays(date, 1)).map((a) => {
      const consent = consentOf(a.id, now);
      const shared = consent.state === 'shared';
      const summary = shared && consent.scope.includes('intake') ? stmt.summary.get(a.id) : null;
      const item = {
        appointmentId: a.id,
        time: a.starts_at.slice(11, 16),
        status: a.status,
        kind: a.kind,
        specialty: a.specialty,
        patient: patientBrief(a, date),
        consent: consent.state,
        consentReason: consent.reason,
        consentRevokedAt: consent.revokedAt,
        hasSummary: Boolean(summary),
        chiefComplaint: summary ? (json(summary.sections, []).find((s) => s.key === 'chief')?.text ?? null) : null,
        flagged: Boolean(summary && json(summary.flags, []).length),
        resultStatus: resultStatusOf(a.id),
      };
      if (shared) {
        const meds = consent.scope.includes('dose_log') ? medsOf(a.patient_id, periodOf(a)) : { courses: [], doseLog: [] };
        item.courses = meds.courses;
        item.doseLog = meds.doseLog;
      }
      return item;
    });
    return sendJson(res, 200, { date, now, items });
  }

  function findAppointment(id, staff) {
    const a = typeof id === 'string' ? stmt.appointment.get(id, staff.clinic_id) : null;
    if (!a) throw notFound();
    return a;
  }

  function chart(req, res, staff, id) {
    const a = findAppointment(id, staff);
    const now = localIso();
    const day = a.starts_at.slice(0, 10);
    const consent = consentOf(a.id, now);
    const shared = consent.state === 'shared';
    const has = (s) => shared && consent.scope.includes(s);
    const period = periodOf(a);
    const meds = has('dose_log') ? medsOf(a.patient_id, period) : { courses: [], doseLog: [] };
    const results = stmt.results.all(a.patient_id, staff.clinic_id);
    const own = stmt.latestResult.get(a.id);
    const last = results.find((r) => r.appt_id !== a.id && r.starts_at < a.starts_at);
    audit(req, staff, 'chart.view', { patientId: a.patient_id, appointmentId: a.id, detail: { consent: consent.state } });
    log('chart_view', { consent: consent.state });
    return sendJson(res, 200, {
      appointment: appointmentJson(a),
      patient: {
        id: a.patient_id,
        code: a.code,
        name: a.full_name,
        age: ageOn(a.birth_date, day),
        gender: a.gender,
        birthDate: a.birth_date,
        address: a.address,
        weightKg: a.weight_kg ?? null,
        insuranceCode: maskInsurance(a.insurance_code),
        allergy: a.allergy,
        conditions: json(a.conditions, []),
      },
      consent,
      period: { from: period.from, days: period.days, now },
      summary: has('intake') ? summaryOf(a.id) : null,
      intake: has('intake')
        ? stmt.intake.all(a.id).map((i) => ({ id: i.id, channel: i.channel, question: i.question, answer: i.answer, answeredAt: i.answered_at }))
        : [],
      courses: meds.courses,
      doseLog: meds.doseLog,
      selfMeds: has('self_meds') ? stmt.selfMeds.all(a.id).map((m) => ({ name: m.name, how: m.how })) : [],
      lastVisit: last ? historyJson(last) : null,
      result: own ? resultDraftJson(own, a.claim_code) : null,
    });
  }

  async function feedback(req, res, staff, id) {
    const body = await readJson(req);
    if (body.value !== 'up' && body.value !== 'down') {
      throw new HttpError(400, 'bad_value', 'Đánh giá chỉ nhận "up" hoặc "down".');
    }
    const s = typeof id === 'string' ? stmt.summaryById.get(id, staff.clinic_id) : null;
    // A summary is only reachable while the person still shares their answers.
    const consent = s ? consentOf(s.appointment_id, localIso()) : null;
    if (!s || consent.state !== 'shared' || !consent.scope.includes('intake')) throw notFound();
    const at = localIso();
    stmt.feedback.run(body.value, staff.id, at, s.id);
    audit(req, staff, 'summary.feedback', { patientId: s.patient_id, appointmentId: s.appointment_id, detail: { summaryId: s.id, value: body.value } });
    log('summary_feedback', { value: body.value });
    return sendJson(res, 200, { feedback: { value: body.value, by: staffJson(staff).name, at } });
  }

  function transition(req, res, staff, id, action) {
    const a = findAppointment(id, staff);
    const from = action === 'arrive' ? ['booked'] : ['booked', 'arrived'];
    const to = action === 'arrive' ? 'arrived' : 'in_progress';
    if (!from.includes(a.status)) throw new HttpError(409, 'bad_state', 'Lượt khám không ở trạng thái phù hợp.');
    stmt.setStatus.run(to, staff.id, a.id, staff.clinic_id);
    audit(req, staff, `appointment.${action}`, { patientId: a.patient_id, appointmentId: a.id, detail: { from: a.status, to } });
    log('appointment_status', { to });
    return sendJson(res, 200, { appointment: appointmentJson(findAppointment(id, staff)) });
  }

  // ---- results (bước 15) --------------------------------------------------

  function getResult(req, res, staff, id) {
    const a = findAppointment(id, staff);
    const r = stmt.latestResult.get(a.id);
    return sendJson(res, 200, r ? resultDraftJson(r, a.claim_code) : null);
  }

  async function saveDraft(req, res, staff, id) {
    const a = findAppointment(id, staff);
    const draft = parseDraft(await readJson(req));
    if (a.status === 'cancelled') throw new HttpError(409, 'bad_state', 'Lượt khám đã hủy.');
    const now = localIso();
    const latest = stmt.latestResult.get(a.id);
    if (latest && latest.status !== 'draft') {
      throw new HttpError(409, 'result_sent', 'Kết quả đã gửi. Mở bản sửa để thay đổi.');
    }
    const fields = [JSON.stringify(draft.diagnosis), JSON.stringify(draft.items), draft.advice, draft.followUpDate, draft.internalNote];
    if (latest) stmt.updateDraft.run(...fields, now, latest.id);
    else stmt.insertResult.run(`r-${a.id}-v1`, a.id, 1, ...fields, null, now);
    audit(req, staff, 'result.draft', { patientId: a.patient_id, appointmentId: a.id, detail: { version: latest?.version ?? 1 } });
    return sendJson(res, 200, resultDraftJson(stmt.latestResult.get(a.id), a.claim_code));
  }

  function sendResult(req, res, staff, id) {
    const a = findAppointment(id, staff);
    const latest = stmt.latestResult.get(a.id);
    if (!latest) throw new HttpError(409, 'no_draft', 'Chưa có bản nháp kết quả.');
    if (latest.status !== 'draft') throw new HttpError(409, 'result_sent', 'Kết quả này đã gửi.');
    const missing = missingForSend({ diagnosis: json(latest.diagnosis, []), items: json(latest.items, []) });
    if (missing.length) throw new HttpError(422, 'incomplete', 'Kết quả còn thiếu thông tin bắt buộc.', missing);
    const now = localIso();
    const code = atomically(() => {
      stmt.markAmended.run(a.id);
      stmt.markSent.run(staff.id, now, now, latest.id);
      stmt.setDone.run(staff.id, a.id);
      syncCourses(a, json(latest.items, []));
      if (a.claim_code) return a.claim_code;
      let fresh;
      do fresh = newClaimCode(); while (stmt.claimTaken.get(fresh));
      stmt.setClaim.run(fresh, localIso(Date.now() + CLAIM_DAYS * 86_400_000), a.id);
      return fresh;
    });
    audit(req, staff, 'result.send', { patientId: a.patient_id, appointmentId: a.id, detail: { version: latest.version } });
    log('result_sent', { version: latest.version });
    return sendJson(res, 200, resultDraftJson(stmt.latestResult.get(a.id), code));
  }

  /**
   * Bước 16: the sent prescription as med_course rows '<appointmentId>#<n>'
   * (n from 1), so the app's dose events can name them. prescribed_at is the
   * first signing; an amendment replaces the items and drops lines it removed.
   */
  function syncCourses(a, items) {
    const prescribedAt = stmt.firstSigned.get(a.id).at;
    items.forEach((item, i) => stmt.upsertCourse.run(`${a.id}#${i + 1}`, a.patient_id, JSON.stringify(item), prescribedAt));
    const prefix = `${a.id}#`;
    for (const { id } of stmt.coursesOfPatient.all(a.patient_id)) {
      if (id.startsWith(prefix) && Number(id.slice(prefix.length)) > items.length) stmt.deleteCourse.run(a.patient_id, id);
    }
  }

  async function amendResult(req, res, staff, id) {
    const a = findAppointment(id, staff);
    const body = await readJson(req);
    const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
    if (!reason || reason.length > 500) throw new HttpError(422, 'incomplete', 'Cần ghi lý do sửa kết quả.', ['reason']);
    const latest = stmt.latestResult.get(a.id);
    if (!latest || latest.status !== 'sent') throw new HttpError(409, 'not_sent', 'Chỉ sửa được kết quả đã gửi.');
    const version = latest.version + 1;
    stmt.insertResult.run(`r-${a.id}-v${version}`, a.id, version, latest.diagnosis, latest.items, latest.advice,
      latest.follow_up_date, latest.internal_note, reason, localIso());
    audit(req, staff, 'result.amend', { patientId: a.patient_id, appointmentId: a.id, detail: { version } });
    return sendJson(res, 201, resultDraftJson(stmt.latestResult.get(a.id), a.claim_code));
  }

  // ---- claim by code (no sign-in) ----------------------------------------

  const claimHits = new Map();
  const claimSweep = setInterval(() => {
    const t = Date.now();
    for (const [ip, h] of claimHits) if (t - h.start >= 60_000) claimHits.delete(ip);
  }, 60_000);
  claimSweep.unref();

  function claim(req, res, rawCode) {
    const ip = req.socket.remoteAddress ?? '';
    const t = Date.now();
    let hits = claimHits.get(ip);
    if (!hits || t - hits.start >= 60_000) claimHits.set(ip, (hits = { start: t, count: 0 }));
    if (++hits.count > CLAIM_PER_MINUTE) {
      log('result_claim', { result: 'rate_limited' });
      throw new HttpError(429, 'rate_limited', 'Bạn thử quá nhiều lần. Vui lòng đợi một phút.');
    }
    const missing = () => new HttpError(404, 'not_found', 'Mã không đúng hoặc đã hết hạn.');
    const code = normalizeClaimCode(rawCode);
    const a = code ? stmt.byClaim.get(code) : null;
    const r = a && a.claim_expires_at > localIso(t) ? stmt.sentResult.get(a.id) : null;
    if (!r) {
      log('result_claim', { result: 'not_found' });
      throw missing();
    }
    stmt.audit.run(localIso(t), 'patient', 'result.claim', a.patient_id, a.id, JSON.stringify({ version: r.version }), ip);
    log('result_claim', { result: 'ok' });
    return sendJson(res, 200, visitResultJson(a, r));
  }

  function history(req, res, staff, patientId) {
    if (!stmt.patient.get(patientId, staff.clinic_id)) throw notFound();
    const entries = stmt.results.all(patientId, staff.clinic_id).map(historyJson);
    audit(req, staff, 'history.view', { patientId });
    return sendJson(res, 200, entries);
  }

  /** Answers a `/v1/<CLINIC_PREFIXES>/...` request. */
  async function handle(req, res, url) {
    const parts = url.pathname.split('/').filter(Boolean).map((p) => {
      try {
        return decodeURIComponent(p);
      } catch {
        throw notFound();
      }
    });
    const [, area, id, sub] = parts;
    const m = req.method;
    if (area === 'patient') return patient.handle(req, res, parts);
    if (area === 'family') return family.handle(req, res, parts, url);
    if (area === 'staff' && parts.length === 3) {
      if (m === 'POST' && id === 'login') return login(req, res);
      if (m === 'POST' && id === 'logout') {
        const token = readCookie(req);
        if (store.get(token)) log('staff_logout', {});
        store.delete(token);
        res.writeHead(204, { 'set-cookie': clearCookie({ secure: config.https }), 'cache-control': 'no-store' });
        return res.end();
      }
      if (m === 'POST' && id === 'password') return changePassword(req, res);
      // Bước 18: like `me`, but 200 null when signed out, so the web's first
      // check does not print a 401 in the browser console.
      if (m === 'GET' && id === 'session') {
        let staff = null;
        try {
          staff = requireStaff(req, { pending: true });
        } catch (error) {
          if (!(error instanceof HttpError) || error.status !== 401) throw error;
        }
        return sendJson(res, 200, staff ? { staff: staffJson(staff), clinic: clinicJson(stmt.clinic.get(staff.clinic_id)) } : null);
      }
      if (m === 'GET' && id === 'me') {
        const staff = requireStaff(req, { pending: true });
        return sendJson(res, 200, { staff: staffJson(staff), clinic: clinicJson(stmt.clinic.get(staff.clinic_id)) });
      }
      throw notFound();
    }
    if (area === 'results') {
      if (m === 'GET' && id === 'claim' && parts.length === 4) return claim(req, res, sub);
      throw notFound();
    }
    const staff = requireStaff(req);
    // Bước 18: admin pages, and the access log (doctor or admin).
    if (area === 'clinic' && id === 'staff') {
      if (parts.length === 3 && m === 'GET') return admin.listStaff(req, res, staff);
      if (parts.length === 3 && m === 'POST') return admin.createStaff(req, res, staff);
      if (parts.length === 5 && m === 'POST') {
        if (parts[4] === 'deactivate') return admin.setActive(req, res, staff, sub, false);
        if (parts[4] === 'reactivate') return admin.setActive(req, res, staff, sub, true);
        if (parts[4] === 'reset-password') return admin.resetPassword(req, res, staff, sub);
      }
      throw notFound();
    }
    if (m === 'GET' && area === 'clinic' && id === 'pilot-metrics' && parts.length === 3) return admin.pilotMetrics(req, res, staff, url);
    if (m === 'GET' && area === 'clinic' && id === 'access-log' && parts.length === 3) return admin.accessLogByCode(req, res, staff, url);
    if (m === 'GET' && area === 'patients' && sub === 'access-log' && parts.length === 4) {
      return admin.accessLogById(req, res, staff, id, url);
    }
    requireDoctor(staff);
    if (m === 'GET' && area === 'clinic' && id === 'worklist' && parts.length === 3) return worklist(req, res, staff, url);
    if (m === 'GET' && area === 'clinic' && id === 'catalog' && parts.length === 3) {
      return sendJson(res, 200, { drugs: clinicCatalog.drugs, icd10: clinicCatalog.icd10 });
    }
    if (area === 'appointments' && parts.length === 4) {
      if (m === 'GET' && sub === 'chart') return chart(req, res, staff, id);
      if (m === 'POST' && (sub === 'arrive' || sub === 'start')) return transition(req, res, staff, id, sub);
      if (m === 'GET' && sub === 'result') return getResult(req, res, staff, id);
      if (m === 'PUT' && sub === 'result-draft') return saveDraft(req, res, staff, id);
    }
    if (area === 'appointments' && parts.length === 5 && parts[3] === 'result' && m === 'POST') {
      if (parts[4] === 'send') return sendResult(req, res, staff, id);
      if (parts[4] === 'amend') return amendResult(req, res, staff, id);
    }
    if (m === 'POST' && area === 'summaries' && sub === 'feedback' && parts.length === 4) return feedback(req, res, staff, id);
    if (m === 'GET' && area === 'patients' && sub === 'history' && parts.length === 4) return history(req, res, staff, id);
    throw notFound();
  }

  return {
    handle,
    sessions: store,
    patient,
    family,
    summaries,
    close: () => {
      store.close();
      patient.close();
      family.close();
      summaries.close();
      clearInterval(claimSweep);
    },
  };
}
