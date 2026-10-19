// Liên kết hai máy (FAMILY-API.md): a caregiver's phone (owner) links one
// family profile with that person's own phone (member) through a one-time
// code shown as a QR. Each side then holds its own token and the two phones
// exchange appointments (both ways) and prescriptions (owner to member, so
// the person's own phone rings for them) through a mailbox per link. The
// member's phone also sends its dose schedule, only so the owner can be told
// about a missed or skipped dose; the owner's own medicines never travel.
// Logs carry event names only, never names, medicines or tokens.
import { createHash, randomBytes, randomUUID } from 'node:crypto';

import { createLimiter } from '../clinic/patient.js';
import { localIso } from '../clinic/time.js';
import { HttpError, notFound, readJson, sendJson } from '../http.js';

export const INVITE_MINUTES = 15;
export const CLAIMS_PER_MINUTE = 10;
export const MISSED_AFTER_MIN = 60;
export const MAX_EVENTS = 50;
export const MAX_DOSES = 200;
export const EVENTS_PAGE = 100;
/** Prescriptions can be larger than the 16 KiB of other bodies. */
export const EVENT_BODY = 256 * 1024;
/** Unambiguous letters and digits (no 0/O, 1/I/L). */
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const KEEP_DOSE_DAYS = 7;

/** Kinds each side may send; the server adds dose.* and link.ended. */
const SENDABLE = {
  owner: ['appointment.upsert', 'appointment.cancel', 'result.upsert'],
  member: ['appointment.upsert', 'appointment.cancel'],
};
const REASONS = ['forgot', 'outOfStock', 'unwell', 'other'];
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;

const sha256 = (text) => createHash('sha256').update(text).digest('base64url');
const isText = (v, max, min = 1) => typeof v === 'string' && v.trim().length >= min && v.length <= max;
const isoTime = (v) => typeof v === 'string' && ISO_TIME.test(v) && !Number.isNaN(Date.parse(v));
const json = (text, fallback) => {
  try {
    return JSON.parse(text);
  } catch {
    return fallback;
  }
};

const unauthenticated = () => new HttpError(401, 'unauthenticated', 'Liên kết này không còn hiệu lực trên máy bạn.');
const badCode = () => new HttpError(404, 'bad_code', 'Mã liên kết không đúng hoặc đã hết hạn.');
const ended = () => new HttpError(409, 'link_ended', 'Liên kết này đã được hủy.');
const forbidden = () => new HttpError(403, 'forbidden', 'Máy này không được gửi mục này.');
const invalid = (fields) => new HttpError(400, 'bad_request', 'Dữ liệu gửi lên không hợp lệ.', fields);
const rateLimited = () => new HttpError(429, 'rate_limited', 'Bạn thử quá nhiều lần. Vui lòng đợi rồi thử lại.');

/** "ABCD-EF23": 8 characters from [ALPHABET], with a dash for reading aloud. */
export function newInviteCode() {
  const bytes = randomBytes(8);
  const chars = [...bytes].map((b) => ALPHABET[b % ALPHABET.length]).join('');
  return `${chars.slice(0, 4)}-${chars.slice(4)}`;
}

/** Upper-case, without spaces or dashes; null when it cannot be a code. */
export function normalizeInviteCode(raw) {
  if (typeof raw !== 'string') return null;
  const s = raw.toUpperCase().replace(/[\s-]/g, '');
  return s.length === 8 && [...s].every((c) => ALPHABET.includes(c)) ? s : null;
}

function readProfile(p) {
  if (!p || typeof p !== 'object') return null;
  if (!isText(p.name, 80) || !isText(p.relationship, 40)) return null;
  if (p.birthYear != null && !(Number.isInteger(p.birthYear) && p.birthYear > 1900 && p.birthYear < 2100)) return null;
  if (p.gender != null && p.gender !== 'Nam' && p.gender !== 'Nữ') return null;
  return { name: p.name.trim(), relationship: p.relationship.trim(), birthYear: p.birthYear ?? null, gender: p.gender ?? null };
}

export function createFamilyApi({ db, log, now = () => Date.now() }) {
  const q = (sql) => db.prepare(sql);
  const claims = createLimiter(60_000, CLAIMS_PER_MINUTE);

  const stmt = {
    insertLink: q(`INSERT INTO family_link (id, owner_token_hash, owner_name, profile, created_at)
      VALUES (?, ?, ?, ?, ?)`),
    link: q('SELECT * FROM family_link WHERE id = ?'),
    dropInvites: q('DELETE FROM family_invite WHERE link_id = ?'),
    insertInvite: q('INSERT INTO family_invite (code_hash, link_id, expires_at) VALUES (?, ?, ?)'),
    invite: q('SELECT * FROM family_invite WHERE code_hash = ?'),
    claim: q(`UPDATE family_link SET member_token_hash = ?, member_name = ?, share_missed = ?, claimed_at = ?
      WHERE id = ? AND member_token_hash IS NULL AND ended_at IS NULL`),
    end: q('UPDATE family_link SET ended_at = ? WHERE id = ? AND ended_at IS NULL'),
    setShare: q('UPDATE family_link SET share_missed = ? WHERE id = ?'),
    insertEvent: q('INSERT INTO family_event (link_id, from_role, kind, ref_id, body, at) VALUES (?, ?, ?, ?, ?, ?)'),
    events: q(`SELECT * FROM family_event WHERE link_id = ? AND from_role = ? AND seq > ?
      ORDER BY seq LIMIT ${EVENTS_PAGE}`),
    upsertDose: q(`INSERT INTO family_dose (link_id, key, at, label, meds) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT (link_id, key) DO UPDATE SET at = excluded.at, label = excluded.label, meds = excluded.meds`),
    dose: q('SELECT * FROM family_dose WHERE link_id = ? AND key = ?'),
    upcomingOpen: q(`SELECT key FROM family_dose WHERE link_id = ? AND mark IS NULL AND alerted = 0 AND at > ?`),
    dropDose: q('DELETE FROM family_dose WHERE link_id = ? AND key = ?'),
    markDose: q('UPDATE family_dose SET mark = ?, reason = ?, marked_at = ?, alerted = ? WHERE link_id = ? AND key = ?'),
    dueOpen: q(`SELECT * FROM family_dose WHERE link_id = ? AND mark IS NULL AND alerted = 0 AND at <= ? ORDER BY at`),
    setAlerted: q('UPDATE family_dose SET alerted = 1 WHERE link_id = ? AND key = ?'),
    dropOld: q('DELETE FROM family_dose WHERE link_id = ? AND at < ?'),
  };

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

  const ipOf = (req) => req.socket.remoteAddress ?? '';
  const bearer = (req) => {
    const m = /^Bearer\s+([A-Za-z0-9_-]{20,100})\s*$/.exec(req.headers.authorization ?? '');
    return m ? m[1] : null;
  };

  /** The link and which side the token belongs to. */
  function requireSide(req, id, { live = true } = {}) {
    const token = bearer(req);
    const link = token ? stmt.link.get(id) : null;
    const hash = token ? sha256(token) : null;
    const role = !link ? null : link.owner_token_hash === hash ? 'owner' : link.member_token_hash === hash ? 'member' : null;
    if (!role) throw unauthenticated();
    if (live && link.ended_at) throw ended();
    return { link, role };
  }

  const status = (link) => (link.ended_at ? 'ended' : link.member_token_hash ? 'linked' : 'pending');
  const linkJson = (link, role) => ({
    id: link.id,
    role,
    status: status(link),
    ownerName: link.owner_name,
    memberName: link.member_name,
    profile: json(link.profile, {}),
    shareMissed: !!link.share_missed,
  });

  function invite(linkId) {
    const code = newInviteCode();
    const expiresAt = localIso(now() + INVITE_MINUTES * 60_000);
    stmt.dropInvites.run(linkId);
    stmt.insertInvite.run(sha256(normalizeInviteCode(code)), linkId, expiresAt);
    return { code, expiresAt };
  }

  const addEvent = (link, from, kind, refId = '', body = {}) =>
    stmt.insertEvent.run(link.id, from, kind, refId, JSON.stringify(body), localIso(now()));

  const doseBody = (d, extra = {}) => ({ at: d.at, label: d.label, meds: json(d.meds, []), ...extra });

  /** Turns the member's doses left unmarked past [MISSED_AFTER_MIN] into events for the owner. */
  function sweepMissed(link) {
    if (!link.share_missed || !link.member_token_hash || link.ended_at) return;
    const t = now();
    atomically(() => {
      for (const d of stmt.dueOpen.all(link.id, localIso(t - MISSED_AFTER_MIN * 60_000))) {
        addEvent(link, 'member', 'dose.missed', d.key, doseBody(d));
        stmt.setAlerted.run(link.id, d.key);
      }
      stmt.dropOld.run(link.id, localIso(t - KEEP_DOSE_DAYS * 86_400_000));
    });
  }

  // ---- linking -------------------------------------------------------------

  async function create(req, res) {
    const body = await readJson(req);
    const profile = readProfile(body.profile);
    const bad = [];
    if (!profile) bad.push('profile');
    if (!isText(body.ownerName, 80)) bad.push('ownerName');
    if (bad.length) throw invalid(bad);
    const id = `fl-${randomUUID()}`;
    const token = randomBytes(32).toString('base64url');
    const out = atomically(() => {
      stmt.insertLink.run(id, sha256(token), body.ownerName.trim(), JSON.stringify(profile), localIso(now()));
      return invite(id);
    });
    log('family_link', { result: 'created' });
    return sendJson(res, 201, { link: linkJson(stmt.link.get(id), 'owner'), token, invite: out });
  }

  function reinvite(req, res, id) {
    const { link, role } = requireSide(req, id);
    if (role !== 'owner') throw forbidden();
    if (link.member_token_hash) throw new HttpError(409, 'already_linked', 'Hồ sơ này đã liên kết với một máy.');
    return sendJson(res, 200, { invite: atomically(() => invite(id)) });
  }

  /** Who is asking, before the member agrees; does not use up the code. */
  async function peek(req, res) {
    if (!claims.hit(ipOf(req))) throw rateLimited();
    const body = await readJson(req);
    const code = normalizeInviteCode(body.code);
    const row = code ? stmt.invite.get(sha256(code)) : null;
    const link = row && row.expires_at > localIso(now()) ? stmt.link.get(row.link_id) : null;
    if (!link || link.member_token_hash || link.ended_at) throw badCode();
    return sendJson(res, 200, { ownerName: link.owner_name, profile: json(link.profile, {}) });
  }

  async function claim(req, res) {
    if (!claims.hit(ipOf(req))) throw rateLimited();
    const body = await readJson(req);
    const code = normalizeInviteCode(body.code);
    if (!isText(body.memberName, 80)) throw invalid(['memberName']);
    const row = code ? stmt.invite.get(sha256(code)) : null;
    if (!row || row.expires_at <= localIso(now())) {
      log('family_claim', { result: 'bad_code' });
      throw badCode();
    }
    const token = randomBytes(32).toString('base64url');
    const ok = atomically(() => {
      stmt.dropInvites.run(row.link_id);
      return stmt.claim.run(sha256(token), body.memberName.trim(), body.shareMissed === false ? 0 : 1,
        localIso(now()), row.link_id).changes;
    });
    if (!ok) throw badCode();
    const link = stmt.link.get(row.link_id);
    addEvent(link, 'member', 'link.claimed', '', { memberName: link.member_name });
    log('family_claim', { result: 'ok' });
    return sendJson(res, 200, { link: linkJson(link, 'member'), token });
  }

  function view(req, res, id) {
    const { link, role } = requireSide(req, id, { live: false });
    return sendJson(res, 200, linkJson(link, role));
  }

  function unlink(req, res, id) {
    const { link, role } = requireSide(req, id, { live: false });
    if (!link.ended_at) {
      atomically(() => {
        stmt.end.run(localIso(now()), id);
        stmt.dropInvites.run(id);
        addEvent(link, role, 'link.ended');
      });
      log('family_link', { result: 'ended' });
    }
    return sendJson(res, 200, linkJson(stmt.link.get(id), role));
  }

  async function settings(req, res, id) {
    const { link, role } = requireSide(req, id);
    if (role !== 'member') throw forbidden();
    const body = await readJson(req);
    if (typeof body.shareMissed !== 'boolean') throw invalid(['shareMissed']);
    stmt.setShare.run(body.shareMissed ? 1 : 0, id);
    addEvent(link, 'member', 'link.settings', '', { shareMissed: body.shareMissed });
    return sendJson(res, 200, linkJson(stmt.link.get(id), role));
  }

  // ---- mailbox -------------------------------------------------------------

  async function post(req, res, id) {
    const { link, role } = requireSide(req, id);
    if (!link.member_token_hash) throw new HttpError(409, 'not_linked', 'Máy người thân chưa nhận liên kết.');
    const body = await readJson(req, EVENT_BODY);
    const events = body.events;
    if (!Array.isArray(events) || !events.length || events.length > MAX_EVENTS) throw invalid(['events']);
    const bad = [];
    events.forEach((e, i) => {
      if (!e || typeof e !== 'object') return bad.push(`events[${i}]`);
      if (!SENDABLE[role].includes(e.kind)) bad.push(`events[${i}].kind`);
      if (!isText(e.id, 160)) bad.push(`events[${i}].id`);
      if (e.body != null && (typeof e.body !== 'object' || Array.isArray(e.body))) bad.push(`events[${i}].body`);
      return undefined;
    });
    if (bad.length) {
      if (bad.every((f) => f.endsWith('.kind'))) throw forbidden();
      throw invalid(bad);
    }
    atomically(() => events.forEach((e) => addEvent(link, role, e.kind, e.id, e.body ?? {})));
    log('family_events', { from: role, n: events.length });
    return sendJson(res, 200, { accepted: events.length });
  }

  function read(req, res, id, url) {
    const { link, role } = requireSide(req, id, { live: false });
    if (role === 'owner') sweepMissed(link);
    const after = Number.parseInt(url.searchParams.get('after') ?? '0', 10);
    const rows = stmt.events.all(id, role === 'owner' ? 'member' : 'owner', Number.isFinite(after) ? after : 0);
    return sendJson(res, 200, {
      status: status(stmt.link.get(id)),
      cursor: rows.length ? rows[rows.length - 1].seq : Math.max(after || 0, 0),
      more: rows.length === EVENTS_PAGE,
      events: rows.map((r) => ({ seq: r.seq, kind: r.kind, id: r.ref_id, body: json(r.body, {}), at: r.at })),
    });
  }

  /** The member's upcoming doses and the marks made on them (member only). */
  async function putDoses(req, res, id) {
    const { link, role } = requireSide(req, id);
    if (role !== 'member') throw forbidden();
    const body = await readJson(req, EVENT_BODY);
    const doses = body.doses ?? [];
    const marks = body.marks ?? [];
    const bad = [];
    if (!Array.isArray(doses) || doses.length > MAX_DOSES) bad.push('doses');
    if (!Array.isArray(marks) || marks.length > MAX_DOSES) bad.push('marks');
    if (bad.length) throw invalid(bad);
    doses.forEach((d, i) => {
      if (!d || !isText(d.key, 200) || !isoTime(d.at) || !isText(d.label, 120)) bad.push(`doses[${i}]`);
      else if (!Array.isArray(d.meds) || d.meds.length > 20 || !d.meds.every((m) => isText(m, 120))) bad.push(`doses[${i}].meds`);
    });
    marks.forEach((m, i) => {
      if (!m || !isText(m.key, 200) || (m.mark !== 'taken' && m.mark !== 'skipped') || !isoTime(m.at)) bad.push(`marks[${i}]`);
      else if (m.reason != null && !REASONS.includes(m.reason)) bad.push(`marks[${i}].reason`);
    });
    if (bad.length) throw invalid(bad);
    const t = localIso(now());
    let alerts = 0;
    atomically(() => {
      const keys = new Set(doses.map((d) => d.key));
      for (const row of stmt.upcomingOpen.all(id, t)) if (!keys.has(row.key)) stmt.dropDose.run(id, row.key);
      for (const d of doses) stmt.upsertDose.run(id, d.key, localIso(Date.parse(d.at)), d.label.trim(), JSON.stringify(d.meds));
      for (const m of marks) {
        const d = stmt.dose.get(id, m.key);
        if (!d || (d.mark === m.mark && d.reason === (m.reason ?? null))) continue;
        let alerted = d.alerted;
        if (link.share_missed && m.mark === 'skipped' && !d.alerted) {
          addEvent(link, 'member', 'dose.skipped', d.key, doseBody(d, { reason: m.reason ?? null }));
          alerted = 1;
          alerts++;
        } else if (link.share_missed && m.mark === 'taken' && d.alerted) {
          // Taken after the owner was told it was missed or skipped.
          addEvent(link, 'member', 'dose.taken', d.key, doseBody(d, { takenAt: localIso(Date.parse(m.at)) }));
          alerts++;
        }
        stmt.markDose.run(m.mark, m.mark === 'skipped' ? (m.reason ?? null) : null, localIso(Date.parse(m.at)), alerted, id, m.key);
      }
    });
    log('family_doses', { n: doses.length, marks: marks.length, alerts });
    return sendJson(res, 200, { doses: doses.length, alerts });
  }

  /** Answers `/v1/family/...`; [parts] are the decoded path segments. */
  async function handle(req, res, parts, url) {
    const [, , area, id, sub] = parts;
    const m = req.method;
    if (area === 'links' && parts.length === 3 && m === 'POST') return create(req, res);
    if (area === 'claim' && parts.length === 3 && m === 'POST') return claim(req, res);
    if (area === 'peek' && parts.length === 3 && m === 'POST') return peek(req, res);
    if (area === 'links' && parts.length === 4) {
      if (m === 'GET') return view(req, res, id);
      if (m === 'DELETE') return unlink(req, res, id);
    }
    if (area === 'links' && parts.length === 5) {
      if (sub === 'invite' && m === 'POST') return reinvite(req, res, id);
      if (sub === 'settings' && m === 'PUT') return settings(req, res, id);
      if (sub === 'events' && m === 'POST') return post(req, res, id);
      if (sub === 'events' && m === 'GET') return read(req, res, id, url);
      if (sub === 'doses' && m === 'PUT') return putDoses(req, res, id);
    }
    throw notFound();
  }

  return {
    handle,
    /** Tests only: forget the claim rate-limit window. */
    resetLimits: () => claims.reset(),
    close: () => claims.close(),
  };
}
