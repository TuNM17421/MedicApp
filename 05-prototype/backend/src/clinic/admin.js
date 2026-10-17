// Bước 18 (CLINIC-API.md "Quản trị và vận hành"): the clinic admin's
// accounts page, the per-patient access log and the pilot numbers. Every
// query is scoped to the caller's clinic; another clinic's ids answer 404.
// Every admin action writes an audit_event. Logs carry event names only.
import { randomUUID } from 'node:crypto';

import { HttpError, notFound, readJson, sendJson } from '../http.js';
import { hashPassword, temporaryPassword } from './auth.js';
import { addDays, localIso, parseDay, today } from './time.js';

export const ROLES = ['doctor', 'admin'];
export const ACCESS_LOG_LIMIT = 50;
export const ACCESS_LOG_MAX = 100;
export const METRICS_MAX_DAYS = 366;

/** What each audit action means, in plain Vietnamese, for the access log. */
export const ACTION_LABELS = {
  'chart.view': 'Mở hồ sơ lượt khám',
  'history.view': 'Xem lịch sử khám',
  'summary.feedback': 'Đánh giá tóm tắt trước khám',
  'summary.generate': 'Tạo tóm tắt trước khám',
  'appointment.arrive': 'Đánh dấu đã đến',
  'appointment.start': 'Bắt đầu khám',
  'result.draft': 'Lưu nháp kết quả khám',
  'result.send': 'Ký và gửi kết quả khám',
  'result.amend': 'Mở bản sửa kết quả khám',
  'result.claim': 'Nhận kết quả bằng mã',
  'result.view': 'Xem kết quả trong app',
  'consent.grant': 'Đồng ý chia sẻ dữ liệu',
  'consent.revoke': 'Rút lại đồng ý chia sẻ',
  'intake.upload': 'Gửi câu trả lời trước khám',
  'self_meds.upload': 'Gửi danh sách thuốc tự dùng',
  'access_log.view': 'Xem nhật ký truy cập',
};

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const forbidden = () => new HttpError(403, 'forbidden', 'Tài khoản của bạn không có quyền dùng chức năng này.');

const isText = (v, max, min = 0) => typeof v === 'string' && v.trim().length >= min && v.trim().length <= max;

/** Nearest-rank percentile of sorted numbers; null when empty. */
function percentile(sorted, p) {
  if (!sorted.length) return null;
  return sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)];
}

/**
 * [store] is the staff session store; [audit](req, staff, action, opts)
 * writes an audit_event; [staffJson] shapes a practitioner row.
 */
export function createAdminApi({ db, log, store, audit, staffJson }) {
  const q = (sql) => db.prepare(sql);
  const stmt = {
    staffOfClinic: q('SELECT * FROM practitioner WHERE clinic_id = ? ORDER BY active DESC, role, full_name, id'),
    staffInClinic: q('SELECT * FROM practitioner WHERE id = ? AND clinic_id = ?'),
    emailTaken: q('SELECT 1 FROM practitioner WHERE email = ?'),
    insertStaff: q(`INSERT INTO practitioner (id, clinic_id, full_name, title, license_no, role, email, password_hash,
      created_at, active, must_change_password) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)`),
    setActive: q('UPDATE practitioner SET active = ? WHERE id = ? AND clinic_id = ?'),
    resetPassword: q(`UPDATE practitioner SET password_hash = ?, must_change_password = 1, failed_logins = 0,
      locked_until = NULL WHERE id = ? AND clinic_id = ?`),
    patient: q('SELECT id, code, full_name FROM patient WHERE id = ? AND clinic_id = ?'),
    patientByCode: q('SELECT id, code, full_name FROM patient WHERE code = ? AND clinic_id = ?'),
    logCount: q('SELECT count(*) AS n FROM audit_event WHERE patient_id = ?'),
    log: q(`SELECT e.id, e.at, e.actor, e.action, e.appointment_id, a.starts_at, pr.title, pr.full_name, pr.role
      FROM audit_event e
      LEFT JOIN appointment a ON a.id = e.appointment_id
      LEFT JOIN practitioner pr ON pr.id = e.actor AND pr.clinic_id = ?
      WHERE e.patient_id = ? ORDER BY e.at DESC, e.id DESC LIMIT ? OFFSET ?`),
    visits: q(`SELECT id, starts_at FROM appointment WHERE clinic_id = ? AND starts_at >= ? AND starts_at < ?
      AND status != 'cancelled' ORDER BY starts_at, id`),
    summaries: q('SELECT feedback FROM visit_summary WHERE appointment_id = ?'),
    firstSent: q('SELECT min(signed_at) AS at FROM visit_result WHERE appointment_id = ? AND signed_at IS NOT NULL'),
    firstReceived: q(`SELECT min(at) AS at FROM audit_event WHERE appointment_id = ?
      AND action IN ('result.claim', 'result.view') AND at >= ?`),
    amended: q("SELECT 1 FROM visit_result WHERE appointment_id = ? AND status = 'amended' LIMIT 1"),
  };

  const requireAdmin = (staff) => {
    if (staff.role !== 'admin') throw forbidden();
  };

  const accountJson = (p, now = Date.now()) => ({
    ...staffJson(p),
    fullName: p.full_name,
    title: p.title,
    email: p.email,
    licenseNo: p.license_no,
    active: Boolean(p.active),
    locked: Boolean(p.locked_until && Date.parse(p.locked_until) > now),
    createdAt: p.created_at,
    lastLoginAt: p.last_login_at ?? null,
  });

  function findStaff(id, admin) {
    const p = typeof id === 'string' ? stmt.staffInClinic.get(id, admin.clinic_id) : null;
    if (!p) throw notFound();
    return p;
  }

  // ---- accounts --------------------------------------------------------------

  function listStaff(req, res, admin) {
    requireAdmin(admin);
    audit(req, admin, 'staff.list');
    return sendJson(res, 200, stmt.staffOfClinic.all(admin.clinic_id).map((p) => accountJson(p)));
  }

  async function createStaff(req, res, admin) {
    requireAdmin(admin);
    const body = await readJson(req);
    const bad = [];
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    if (!EMAIL.test(email) || email.length > 254) bad.push('email');
    if (!isText(body.fullName, 80, 1)) bad.push('fullName');
    if (!ROLES.includes(body.role)) bad.push('role');
    if (body.title != null && !isText(body.title, 20)) bad.push('title');
    if (body.licenseNo != null && !isText(body.licenseNo, 40)) bad.push('licenseNo');
    if (bad.length) throw new HttpError(422, 'bad_staff', 'Thông tin tài khoản chưa hợp lệ.', bad);
    if (stmt.emailTaken.get(email)) throw new HttpError(409, 'email_taken', 'Email này đã có tài khoản.', ['email']);
    const password = temporaryPassword();
    const id = `pr-${randomUUID()}`;
    const title = body.title != null ? body.title.trim() : body.role === 'doctor' ? 'BS.' : '';
    stmt.insertStaff.run(id, admin.clinic_id, body.fullName.trim(), title, (body.licenseNo ?? '').trim(), body.role, email,
      await hashPassword(password), localIso());
    audit(req, admin, 'staff.create', { detail: { staffId: id, role: body.role } });
    log('staff_admin', { action: 'create', role: body.role });
    // The one-time password leaves the server only here, once.
    return sendJson(res, 201, { staff: accountJson(stmt.staffInClinic.get(id, admin.clinic_id)), temporaryPassword: password });
  }

  function setActive(req, res, admin, id, active) {
    requireAdmin(admin);
    const p = findStaff(id, admin);
    if (p.id === admin.id) throw new HttpError(409, 'self', 'Không tự khóa tài khoản của chính mình.');
    stmt.setActive.run(active ? 1 : 0, p.id, admin.clinic_id);
    // A deactivated account's sessions end at once (requireStaff also checks).
    const ended = active ? 0 : store.endFor(p.id);
    audit(req, admin, active ? 'staff.reactivate' : 'staff.deactivate', { detail: { staffId: p.id, sessionsEnded: ended } });
    log('staff_admin', { action: active ? 'reactivate' : 'deactivate' });
    return sendJson(res, 200, { staff: accountJson(findStaff(id, admin)) });
  }

  async function resetPassword(req, res, admin, id) {
    requireAdmin(admin);
    const p = findStaff(id, admin);
    if (p.id === admin.id) throw new HttpError(409, 'self', 'Đổi mật khẩu của chính mình ở mục Đổi mật khẩu.');
    const password = temporaryPassword();
    stmt.resetPassword.run(await hashPassword(password), p.id, admin.clinic_id);
    const ended = store.endFor(p.id);
    audit(req, admin, 'staff.reset_password', { detail: { staffId: p.id, sessionsEnded: ended } });
    log('staff_admin', { action: 'reset_password' });
    return sendJson(res, 200, { staff: accountJson(findStaff(id, admin)), temporaryPassword: password });
  }

  // ---- access log ------------------------------------------------------------

  function accessLog(req, res, staff, patient, url) {
    const raw = (name, fallback) => {
      const v = url.searchParams.get(name);
      return v == null || v === '' ? fallback : Number(v);
    };
    const limit = raw('limit', ACCESS_LOG_LIMIT);
    const offset = raw('offset', 0);
    if (!Number.isInteger(limit) || limit < 1 || limit > ACCESS_LOG_MAX || !Number.isInteger(offset) || offset < 0) {
      throw new HttpError(400, 'bad_page', 'Trang không hợp lệ.');
    }
    // Viewing the log is itself an access, recorded before reading so it shows.
    audit(req, staff, 'access_log.view', { patientId: patient.id });
    const total = stmt.logCount.get(patient.id).n;
    const items = stmt.log.all(staff.clinic_id, patient.id, limit, offset).map((e) => {
      let actor;
      if (e.actor === 'patient') actor = { kind: 'patient', name: 'Người bệnh' };
      else if (e.actor === 'system') actor = { kind: 'system', name: 'Hệ thống' };
      else actor = { kind: 'staff', name: e.full_name ? `${e.title} ${e.full_name}`.trim() : 'Nhân viên', role: e.role ?? null };
      return {
        id: e.id,
        at: e.at,
        actor,
        action: e.action,
        label: ACTION_LABELS[e.action] ?? 'Thao tác khác',
        appointmentId: e.appointment_id ?? null,
        visitDate: e.starts_at ? e.starts_at.slice(0, 10) : null,
      };
    });
    return sendJson(res, 200, {
      patient: { id: patient.id, code: patient.code, name: patient.full_name },
      total,
      offset,
      items,
      nextOffset: offset + items.length < total ? offset + items.length : null,
    });
  }

  /** GET /v1/patients/:id/access-log (doctor or admin of the clinic). */
  function accessLogById(req, res, staff, patientId, url) {
    const p = typeof patientId === 'string' ? stmt.patient.get(patientId, staff.clinic_id) : null;
    if (!p) throw notFound();
    return accessLog(req, res, staff, p, url);
  }

  /** GET /v1/clinic/access-log?patientCode= (the admin has no worklist to find ids). */
  function accessLogByCode(req, res, staff, url) {
    const code = (url.searchParams.get('patientCode') ?? '').trim();
    const p = code && code.length <= 32 ? stmt.patientByCode.get(code, staff.clinic_id) : null;
    if (!p) throw notFound();
    return accessLog(req, res, staff, p, url);
  }

  // ---- pilot metrics ---------------------------------------------------------

  function pilotMetrics(req, res, admin, url) {
    requireAdmin(admin);
    const rawTo = url.searchParams.get('to');
    const rawFrom = url.searchParams.get('from');
    const to = rawTo ? parseDay(rawTo) : today();
    const from = rawFrom ? parseDay(rawFrom) : to && addDays(to, -29);
    if (!from || !to || from > to || addDays(from, METRICS_MAX_DAYS - 1) < to) {
      throw new HttpError(400, 'bad_range', `Khoảng ngày không hợp lệ (tối đa ${METRICS_MAX_DAYS} ngày).`);
    }
    const days = new Map();
    const blank = () => ({ visits: 0, withSummary: 0, summaries: 0, feedbackUp: 0, feedbackDown: 0, sent: 0, received: 0, waits: [], amended: 0 });
    const total = blank();
    for (const v of stmt.visits.all(admin.clinic_id, from, addDays(to, 1))) {
      const day = v.starts_at.slice(0, 10);
      if (!days.has(day)) days.set(day, blank());
      const rows = stmt.summaries.all(v.id);
      const sent = stmt.firstSent.get(v.id).at;
      const received = sent ? stmt.firstReceived.get(v.id, sent).at : null;
      const wait = received ? Math.round((Date.parse(received) - Date.parse(sent)) / 60_000) : null;
      for (const m of [days.get(day), total]) {
        m.visits++;
        if (rows.length) m.withSummary++;
        m.summaries += rows.length;
        m.feedbackUp += rows.filter((r) => r.feedback === 'up').length;
        m.feedbackDown += rows.filter((r) => r.feedback === 'down').length;
        if (sent) m.sent++;
        if (received) {
          m.received++;
          m.waits.push(wait);
        }
        if (stmt.amended.get(v.id)) m.amended++;
      }
    }
    const shape = (m) => {
      const waits = m.waits.sort((a, b) => a - b);
      const rated = m.feedbackUp + m.feedbackDown;
      const { waits: _, ...rest } = m;
      return { ...rest, upRate: rated ? m.feedbackUp / rated : null, medianMinutes: percentile(waits, 50), p90Minutes: percentile(waits, 90) };
    };
    audit(req, admin, 'pilot_metrics.view', { detail: { from, to } });
    return sendJson(res, 200, {
      from,
      to,
      totals: shape(total),
      days: [...days].map(([date, m]) => ({ date, ...shape(m) })),
    });
  }

  return { listStaff, createStaff, setActive, resetPassword, accessLogById, accessLogByCode, pilotMetrics };
}
