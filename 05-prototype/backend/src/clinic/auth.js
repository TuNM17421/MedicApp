// Staff sign-in: scrypt password hashes and in-memory sessions in an
// HttpOnly cookie. Nothing here logs an email, a password or a token.
import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

export const COOKIE = 'mc_staff';
export const IDLE_MS = 30 * 60_000;
export const ABSOLUTE_MS = 12 * 3600_000;
export const MAX_FAILED = 5;
export const LOCK_MS = 15 * 60_000;
export const MIN_PASSWORD = 10;
export const MAX_PASSWORD = 256;

const KEY_LEN = 32;
const PARAMS = { N: 16384, r: 8, p: 1 };

function derive(password, salt, { N, r, p } = PARAMS) {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, KEY_LEN, { N, r, p, maxmem: 64 * 1024 * 1024 }, (error, key) => (error ? reject(error) : resolve(key)));
  });
}

/** "scrypt$N$r$p$<salt>$<hash>", base64url, with a fresh 16-byte salt. */
export async function hashPassword(password) {
  const salt = randomBytes(16);
  const key = await derive(String(password), salt);
  return ['scrypt', PARAMS.N, PARAMS.r, PARAMS.p, salt.toString('base64url'), key.toString('base64url')].join('$');
}

export async function verifyPassword(password, stored) {
  const parts = typeof stored === 'string' ? stored.split('$') : [];
  if (parts.length !== 6 || parts[0] !== 'scrypt') {
    await derive(String(password), randomBytes(16)); // same cost either way
    return false;
  }
  const [, N, r, p, salt, hash] = parts;
  const expected = Buffer.from(hash, 'base64url');
  const key = await derive(String(password), Buffer.from(salt, 'base64url'), { N: +N, r: +r, p: +p });
  return key.length === expected.length && timingSafeEqual(key, expected);
}

/**
 * Bước 18 password rule: at least 10 characters, at most 256, not the email
 * (ignoring case and spaces). Returns a Vietnamese reason, or null when ok.
 */
export function passwordProblem(password, email = '') {
  if (typeof password !== 'string' || password.length < MIN_PASSWORD) return `Mật khẩu cần ít nhất ${MIN_PASSWORD} ký tự.`;
  if (password.length > MAX_PASSWORD) return 'Mật khẩu quá dài.';
  const norm = (v) => String(v).trim().toLowerCase();
  if (email && norm(password) === norm(email)) return 'Mật khẩu không được trùng email.';
  return null;
}

// Crockford base32 without look-alikes: easy to read out and type.
const TEMP_ALPHABET = '23456789abcdefghjkmnpqrstvwxyz';

/** One-time password for a new or reset account, e.g. "k7mq-4xr2-9dpt" (14 characters). */
export function temporaryPassword() {
  const out = [];
  while (out.length < 12) {
    for (const b of randomBytes(16)) {
      // 240 = 8 × 30: reject the tail so every character is equally likely.
      if (b < 240 && out.length < 12) out.push(TEMP_ALPHABET[b % 30]);
    }
  }
  return `${out.slice(0, 4).join('')}-${out.slice(4, 8).join('')}-${out.slice(8).join('')}`;
}

/** Sessions keyed by a random 32-byte token: 30 min sliding, 12 h at most. */
export function createSessionStore({ now = () => Date.now() } = {}) {
  const sessions = new Map();

  const alive = (s, t) => t - s.lastSeen < IDLE_MS && t - s.createdAt < ABSOLUTE_MS;

  const sweep = setInterval(() => {
    const t = now();
    for (const [token, s] of sessions) if (!alive(s, t)) sessions.delete(token);
  }, 60_000);
  sweep.unref();

  return {
    sessions,
    create(staff) {
      const token = randomBytes(32).toString('base64url');
      const t = now();
      sessions.set(token, { staffId: staff.id, clinicId: staff.clinic_id, createdAt: t, lastSeen: t });
      return token;
    },
    /** The live session for [token], touched; null when missing or expired. */
    get(token) {
      if (typeof token !== 'string' || !token) return null;
      const s = sessions.get(token);
      if (!s) return null;
      const t = now();
      if (!alive(s, t)) {
        sessions.delete(token);
        return null;
      }
      s.lastSeen = t;
      return s;
    },
    delete(token) {
      sessions.delete(token);
    },
    /** Ends every session of [staffId] except [keep]; returns how many ended. */
    endFor(staffId, keep = null) {
      let n = 0;
      for (const [token, s] of sessions) {
        if (s.staffId === staffId && token !== keep) {
          sessions.delete(token);
          n++;
        }
      }
      return n;
    },
    close() {
      clearInterval(sweep);
      sessions.clear();
    },
  };
}

export function readCookie(req, name = COOKIE) {
  const header = req.headers.cookie;
  if (typeof header !== 'string') return null;
  for (const part of header.split(';')) {
    const i = part.indexOf('=');
    if (i > 0 && part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return null;
}

/**
 * Session cookie (no Max-Age: the server enforces idle and absolute
 * limits). SameSite=Strict also works for `flutter run` on another
 * localhost port, because ports do not change the site.
 */
export function sessionCookie(token, { secure }) {
  return `${COOKIE}=${token}; HttpOnly; SameSite=Strict; Path=/${secure ? '; Secure' : ''}`;
}

export function clearCookie({ secure }) {
  return `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0${secure ? '; Secure' : ''}`;
}
