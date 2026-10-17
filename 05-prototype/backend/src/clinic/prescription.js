// Result drafts and prescriptions. Items keep medic_core's PrescriptionItem
// JSON (packages/medic_core/lib/src/visit_result.dart) so the app reads them
// with PrescriptionItem.fromJson unchanged.
import { randomBytes } from 'node:crypto';

import { HttpError } from '../http.js';
import { parseDay } from './time.js';

export const SLOTS = ['morning', 'noon', 'afternoon', 'evening'];
export const MEALS = ['before', 'after', 'any'];
export const MAX_ITEMS = 20;
export const MAX_DIAGNOSES = 10;
const LIMITS = { name: 120, strength: 40, form: 20, route: 20, note: 300, code: 16, label: 200, advice: 2000, internalNote: 2000 };

const isText = (v, max) => typeof v === 'string' && v.length <= max;

/**
 * Checks types and lengths of a draft body and returns the stored shape.
 * Missing parts get empty values: a draft may be incomplete. Wrong types
 * answer 400 `bad_draft` with the offending field paths.
 */
export function parseDraft(body) {
  const bad = [];
  const text = (v, max, path) => {
    if (v === undefined || v === null) return '';
    if (!isText(v, max)) bad.push(path);
    return typeof v === 'string' ? v.trim().slice(0, max) : '';
  };

  let diagnosis = [];
  if (body.diagnosis !== undefined && body.diagnosis !== null) {
    if (!Array.isArray(body.diagnosis) || body.diagnosis.length > MAX_DIAGNOSES) bad.push('diagnosis');
    else {
      diagnosis = body.diagnosis.map((d, i) => {
        if (!Array.isArray(d) || d.length !== 2 || !isText(d[0], LIMITS.code) || !isText(d[1], LIMITS.label)) {
          bad.push(`diagnosis[${i}]`);
          return ['', ''];
        }
        return [d[0].trim().toUpperCase(), d[1].trim()];
      });
    }
  }

  let items = [];
  if (body.items !== undefined && body.items !== null) {
    if (!Array.isArray(body.items) || body.items.length > MAX_ITEMS) bad.push('items');
    else items = body.items.map((raw, i) => parseItem(raw, `items[${i}]`, bad, text));
  }

  const followUp = body.followUpDate ?? null;
  if (followUp !== null && !parseDay(followUp)) bad.push('followUpDate');

  const draft = {
    diagnosis,
    items,
    advice: text(body.advice, LIMITS.advice, 'advice'),
    followUpDate: followUp !== null && parseDay(followUp) ? followUp : null,
    internalNote: text(body.internalNote, LIMITS.internalNote, 'internalNote'),
  };
  if (bad.length) throw new HttpError(400, 'bad_draft', 'Dữ liệu đơn thuốc không hợp lệ.', bad);
  return draft;
}

function parseItem(raw, path, bad, text) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    bad.push(path);
    return null;
  }
  const int = (v, key, max) => {
    if (v === undefined || v === null) return 0;
    if (!Number.isInteger(v) || v < 0 || v > max) bad.push(`${path}.${key}`);
    return Number.isInteger(v) ? v : 0;
  };
  const doses = [];
  if (raw.doses !== undefined && raw.doses !== null) {
    if (!Array.isArray(raw.doses) || raw.doses.length > SLOTS.length) bad.push(`${path}.doses`);
    else {
      const seen = new Set();
      raw.doses.forEach((d, k) => {
        const ok = d && SLOTS.includes(d.slot) && !seen.has(d.slot)
          && typeof d.amount === 'number' && Number.isFinite(d.amount) && d.amount >= 0 && d.amount <= 100;
        if (!ok) {
          bad.push(`${path}.doses[${k}]`);
          return;
        }
        seen.add(d.slot);
        doses.push({ slot: d.slot, amount: d.amount });
      });
      doses.sort((a, b) => SLOTS.indexOf(a.slot) - SLOTS.indexOf(b.slot));
    }
  }
  const meal = raw.meal ?? 'any';
  if (!MEALS.includes(meal)) bad.push(`${path}.meal`);
  return {
    name: text(raw.name, LIMITS.name, `${path}.name`),
    strength: text(raw.strength, LIMITS.strength, `${path}.strength`),
    form: text(raw.form, LIMITS.form, `${path}.form`) || 'viên',
    quantity: int(raw.quantity, 'quantity', 10_000),
    route: text(raw.route, LIMITS.route, `${path}.route`) || 'Uống',
    doses,
    meal: MEALS.includes(meal) ? meal : 'any',
    days: int(raw.days, 'days', 365),
    note: text(raw.note, LIMITS.note, `${path}.note`),
  };
}

/** What sending needs. Returns the missing field paths (empty when complete). */
export function missingForSend(draft) {
  const missing = [];
  if (!draft.diagnosis.length) missing.push('diagnosis');
  draft.diagnosis.forEach((d, i) => {
    if (!d[0] || !d[1]) missing.push(`diagnosis[${i}]`);
  });
  draft.items.forEach((item, i) => {
    if (!item.name) missing.push(`items[${i}].name`);
    if (!(item.quantity >= 1)) missing.push(`items[${i}].quantity`);
    if (!item.doses.some((d) => d.amount > 0) || item.doses.some((d) => !(d.amount > 0))) missing.push(`items[${i}].doses`);
    if (!(item.days >= 1 && item.days <= 365)) missing.push(`items[${i}].days`);
  });
  return missing;
}

// ---- claim codes -------------------------------------------------------

export const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export const CLAIM_LENGTH = 10;

/** 10 random Crockford base32 characters (50 bits). */
export function newClaimCode() {
  const bytes = randomBytes(CLAIM_LENGTH);
  // 256 is a multiple of 32, so the low five bits are uniform.
  return Array.from(bytes, (b) => CROCKFORD[b & 31]).join('');
}

/** Upper-case, without dashes or spaces, with Crockford's look-alikes mapped; null when not a code. */
export function normalizeClaimCode(input) {
  if (typeof input !== 'string' || input.length > 40) return null;
  const code = input.toUpperCase().replace(/[\s-]/g, '').replace(/O/g, '0').replace(/[IL]/g, '1');
  return code.length === CLAIM_LENGTH && [...code].every((c) => CROCKFORD.includes(c)) ? code : null;
}

/** "K7MQ4XR29D" -> "K7MQ-4XR2-9D". */
export const formatClaimCode = (code) => (code ? `${code.slice(0, 4)}-${code.slice(4, 8)}-${code.slice(8)}` : null);
