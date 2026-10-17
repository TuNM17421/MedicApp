// Clinic time. The clinic runs on Asia/Ho_Chi_Minh (UTC+7, no daylight
// saving), so times are stored as ISO-8601 text with a fixed "+07:00" and a
// day is the "yyyy-MM-dd" prefix of that text.

const OFFSET_MS = 7 * 3600_000;
export const TZ = '+07:00';

const pad = (n) => String(n).padStart(2, '0');

/** "yyyy-MM-dd" when valid, otherwise null. */
export function parseDay(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const d = new Date(`${value}T00:00:00Z`);
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value ? null : value;
}

/** [ms] (default now) as clinic-local "yyyy-MM-ddTHH:mm:ss+07:00". */
export function localIso(ms = Date.now()) {
  return `${new Date(ms + OFFSET_MS).toISOString().slice(0, 19)}${TZ}`;
}

export const today = (ms = Date.now()) => localIso(ms).slice(0, 10);

export function addDays(day, n) {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Local time on [day] as stored text, e.g. at('2026-10-16', '08:30'). */
export const at = (day, hhmm) => `${day}T${hhmm.length === 5 ? `${hhmm}:00` : hhmm}${TZ}`;

/** Whole years from [birthDate] to [onDay]. */
export function ageOn(birthDate, onDay) {
  const [by, bm, bd] = birthDate.split('-').map(Number);
  const [y, m, d] = onDay.split('-').map(Number);
  return y - by - (m < bm || (m === bm && d < bd) ? 1 : 0);
}

/** Same calendar date [years] earlier (29 Feb becomes 28 Feb). */
export function minusYears(day, years) {
  const [y, m, d] = day.split('-').map(Number);
  const yy = y - years;
  const leap = (yy % 4 === 0 && yy % 100 !== 0) || yy % 400 === 0;
  return `${yy}-${pad(m)}-${pad(m === 2 && d === 29 && !leap ? 28 : d)}`;
}
