// Doctor web API (CLINIC-API.md): staff sign-in, worklist, chart, summary
// feedback, arrive/start and visit history. Every query is scoped to the
// signed-in doctor's clinic; another clinic's ids answer 404. Logs carry
// event names and codes only, never names, symptoms or tokens.
import { HttpError, notFound, readJson, sendJson } from '../http.js';
import {
  LOCK_MS, MAX_FAILED, clearCookie, createSessionStore, readCookie, sessionCookie, verifyPassword,
} from './auth.js';
import { addDays, ageOn, localIso, parseDay, today } from './time.js';

export const CLINIC_PREFIXES = ['staff', 'clinic', 'appointments', 'summaries', 'patients'];
export const PERIOD_DAYS = 30;

const unauthenticated = () => new HttpError(401, 'unauthenticated', 'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại.');
const json = (text, fallback) => {
  try {
    return text == null ? fallback : JSON.parse(text);
  } catch {
    return fallback;
  }
};

const staffJson = (p) => ({ id: p.id, name: `${p.title} ${p.full_name}`.trim(), role: p.role });
const clinicJson = (c) => ({ id: c.id, name: c.name, phone: c.phone });
const maskInsurance = (code) => (code ? `•••• ${code.slice(-4)}` : null);

export function createClinicApi({ db, config, log }) {
  const store = createSessionStore();
  const q = (sql) => db.prepare(sql);

  const stmt = {
    staffByEmail: q('SELECT * FROM practitioner WHERE email = ?'),
    staffById: q('SELECT * FROM practitioner WHERE id = ?'),
    clinic: q('SELECT * FROM clinic WHERE id = ?'),
    loginFailed: q('UPDATE practitioner SET failed_logins = ?, locked_until = ? WHERE id = ?'),
    loginOk: q('UPDATE practitioner SET failed_logins = 0, locked_until = NULL WHERE id = ?'),
    audit: q(`INSERT INTO audit_event (at, actor, action, patient_id, appointment_id, detail, ip)
      VALUES (?, ?, ?, ?, ?, ?, ?)`),
    day: q(`SELECT a.*, p.code, p.full_name, p.birth_date, p.gender FROM appointment a
      JOIN patient p ON p.id = a.patient_id
      WHERE a.clinic_id = ? AND a.starts_at >= ? AND a.starts_at < ? ORDER BY a.starts_at, a.id`),
    appointment: q(`SELECT a.*, p.code, p.full_name, p.birth_date, p.gender, p.address, p.weight_kg,
      p.insurance_code, p.allergy, p.conditions FROM appointment a
      JOIN patient p ON p.id = a.patient_id WHERE a.id = ? AND a.clinic_id = ?`),
    consent: q('SELECT * FROM consent WHERE appointment_id = ? ORDER BY granted_at DESC, id DESC LIMIT 1'),
    summary: q('SELECT * FROM visit_summary WHERE appointment_id = ? ORDER BY created_at DESC, id DESC LIMIT 1'),
    summaryById: q(`SELECT s.*, a.patient_id, a.clinic_id FROM visit_summary s
      JOIN appointment a ON a.id = s.appointment_id WHERE s.id = ? AND a.clinic_id = ?`),
    feedback: q('UPDATE visit_summary SET feedback = ?, feedback_by = ?, feedback_at = ? WHERE id = ?'),
    intake: q('SELECT * FROM intake_answer WHERE appointment_id = ? ORDER BY answered_at, id'),
    selfMeds: q('SELECT name, how FROM self_medication WHERE appointment_id = ? ORDER BY rowid'),
    courses: q('SELECT * FROM med_course WHERE patient_id = ? ORDER BY prescribed_at, id'),
    doses: q(`SELECT * FROM dose_event WHERE patient_id = ? AND day >= ? AND day <= ?
      ORDER BY day, course_id, slot`),
    resultStatuses: q('SELECT status FROM visit_result WHERE appointment_id = ?'),
    results: q(`SELECT r.*, a.starts_at, a.id AS appt_id, c.name AS clinic_name, pr.title, pr.full_name AS doctor_name
      FROM visit_result r
      JOIN appointment a ON a.id = r.appointment_id
      JOIN clinic c ON c.id = a.clinic_id
      LEFT JOIN practitioner pr ON pr.id = r.signed_by
      WHERE a.patient_id = ? AND a.clinic_id = ? AND r.status IN ('sent', 'amended')
        AND r.version = (SELECT max(r2.version) FROM visit_result r2
          WHERE r2.appointment_id = r.appointment_id AND r2.status IN ('sent', 'amended'))
      ORDER BY a.starts_at DESC`),
    patient: q('SELECT id FROM patient WHERE id = ? AND clinic_id = ?'),
    setStatus: q('UPDATE appointment SET status = ?, practitioner_id = coalesce(practitioner_id, ?) WHERE id = ? AND clinic_id = ?'),
  };

  function audit(req, staff, action, { patientId = null, appointmentId = null, detail = {} } = {}) {
    stmt.audit.run(localIso(), staff.id, action, patientId, appointmentId, JSON.stringify(detail), req.socket.remoteAddress ?? '');
  }

  function requireStaff(req) {
    const session = store.get(readCookie(req));
    if (!session) throw unauthenticated();
    const staff = stmt.staffById.get(session.staffId);
    if (!staff || staff.clinic_id !== session.clinicId) throw unauthenticated();
    return staff;
  }

  // ---- read models -------------------------------------------------------

  function consentOf(appointmentId, now) {
    const row = stmt.consent.get(appointmentId);
    if (!row) return { state: 'none', grantedAt: null, expiresAt: null, scope: [] };
    const scope = json(row.scope, []);
    if (row.revoked_at || row.expires_at <= now || !scope.length) {
      return { state: 'declined', grantedAt: null, expiresAt: null, scope: [] };
    }
    return { state: 'shared', grantedAt: row.granted_at, expiresAt: row.expires_at, scope };
  }

  function resultStatusOf(appointmentId) {
    const statuses = stmt.resultStatuses.all(appointmentId).map((r) => r.status);
    if (statuses.some((s) => s === 'sent' || s === 'amended')) return 'sent';
    return statuses.includes('draft') ? 'draft' : 'none';
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
    const nowMs = Date.now();
    if (staff.locked_until && Date.parse(staff.locked_until) > nowMs) {
      log('staff_login', { result: 'locked' });
      throw locked();
    }
    if (!(await verifyPassword(password, staff.password_hash))) {
      const failed = (staff.locked_until ? 0 : staff.failed_logins) + 1;
      if (failed >= MAX_FAILED) {
        stmt.loginFailed.run(0, localIso(nowMs + LOCK_MS), staff.id);
        log('staff_login', { result: 'locked' });
        throw locked();
      }
      stmt.loginFailed.run(failed, null, staff.id);
      log('staff_login', { result: 'bad_credentials' });
      throw bad();
    }
    stmt.loginOk.run(staff.id);
    const token = store.create(staff);
    log('staff_login', { result: 'ok' });
    return sendJson(res, 200, { staff: staffJson(staff), clinic: clinicJson(stmt.clinic.get(staff.clinic_id)) }, {
      'set-cookie': sessionCookie(token, { secure: config.https }),
    });
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
    const own = results.find((r) => r.appt_id === a.id);
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
      result: own ? historyJson(own) : null,
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
    if (area === 'staff' && parts.length === 3) {
      if (m === 'POST' && id === 'login') return login(req, res);
      if (m === 'POST' && id === 'logout') {
        const token = readCookie(req);
        if (store.get(token)) log('staff_logout', {});
        store.delete(token);
        res.writeHead(204, { 'set-cookie': clearCookie({ secure: config.https }), 'cache-control': 'no-store' });
        return res.end();
      }
      if (m === 'GET' && id === 'me') {
        const staff = requireStaff(req);
        return sendJson(res, 200, { staff: staffJson(staff), clinic: clinicJson(stmt.clinic.get(staff.clinic_id)) });
      }
      throw notFound();
    }
    const staff = requireStaff(req);
    if (m === 'GET' && area === 'clinic' && id === 'worklist' && parts.length === 3) return worklist(req, res, staff, url);
    if (area === 'appointments' && parts.length === 4) {
      if (m === 'GET' && sub === 'chart') return chart(req, res, staff, id);
      if (m === 'POST' && (sub === 'arrive' || sub === 'start')) return transition(req, res, staff, id, sub);
    }
    if (m === 'POST' && area === 'summaries' && sub === 'feedback' && parts.length === 4) return feedback(req, res, staff, id);
    if (m === 'GET' && area === 'patients' && sub === 'history' && parts.length === 4) return history(req, res, staff, id);
    throw notFound();
  }

  return { handle, sessions: store, close: () => store.close() };
}
