import { readFileSync } from 'node:fs';

/**
 * Illustrative catalog shared with the Flutter app (`catalog/catalog.json`).
 * The Flutter test suite compares its BookingCatalog against this file so the
 * two cannot drift silently.
 */
export const catalog = Object.freeze(
  JSON.parse(readFileSync(new URL('../catalog/catalog.json', import.meta.url), 'utf8')),
);

export const facility = (id) => catalog.facilities.find((f) => f.id === id) ?? null;
export const department = (id) => catalog.departments.find((d) => d.id === id) ?? null;
export const doctor = (id) => catalog.doctors.find((d) => d.id === id) ?? null;
export const doctorsFor = (facilityId, departmentId) =>
  catalog.doctors.filter((d) => d.facilityId === facilityId && d.departmentId === departmentId);

/** Lower-case, strip Vietnamese diacritics and collapse whitespace. */
export function normalize(text) {
  return String(text ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/[^a-z0-9/\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const WEEKDAYS = ['Chủ nhật', 'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy'];

export function isoDate(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function parseIsoDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isNaN(date.getTime()) || isoDate(date) !== value ? null : date;
}

/** Same rule as BookingCatalog.dates: the next six days, Sundays closed. */
export function bookableDates(today) {
  const start = parseIsoDate(today);
  if (!start) throw new Error('today must be YYYY-MM-DD');
  const result = [];
  const date = new Date(start);
  while (result.length < catalog.schedule.daysAhead) {
    date.setUTCDate(date.getUTCDate() + 1);
    if (date.getUTCDay() !== 0) result.push(isoDate(date));
  }
  return result;
}

export function dateLabel(iso) {
  const date = parseIsoDate(iso);
  if (!date) return iso;
  return `${WEEKDAYS[date.getUTCDay()]} ${date.getUTCDate()}/${date.getUTCMonth() + 1}`;
}

export const weekdayIndex = (iso) => parseIsoDate(iso)?.getUTCDay() ?? null;
