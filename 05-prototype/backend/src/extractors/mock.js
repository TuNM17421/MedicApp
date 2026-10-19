import {
  bookableDates,
  catalog,
  isoDate,
  normalize,
  parseIsoDate,
  weekdayIndex,
} from '../catalog.js';
import { emptyExtraction } from '../extraction.js';
import { urgentSigns } from '../urgent.js';

/**
 * Deterministic "Mô phỏng AI" extractor used when no API key is configured
 * and by the automated tests. It understands a small set of Vietnamese
 * phrases; it is not a medical triage tool.
 */

const DEPARTMENT_HINTS = {
  heart: ['tim mach', 'dau nguc', 'tuc nguc', 'huyet ap', 'hoi hop', 'danh trong nguc', 'tim dap nhanh'],
  bones: ['co xuong khop', 'khop', 'dau lung', 'dau goi', 'dau vai', 'cot song', 'thoai hoa', 'xuong'],
  ent: ['tai mui hong', 'dau hong', 'viem hong', 'nghet mui', 'chay mui', 'so mui', 'xoang', 'u tai', 'dau tai', 'nghe kem', 'ho nhieu', 'bi ho'],
  eyes: ['kham mat', 'dau mat', 'mo mat', 'mat mo', 'nhin mo', 'cay mat', 'do mat', 'chuyen khoa mat'],
  endocrine: ['noi tiet', 'tieu duong', 'duong huyet', 'tuyen giap', 'buou co'],
  children: ['nhi khoa'],
  general: ['noi tong quat', 'kham tong quat', 'kham suc khoe', 'met moi', 'sot', 'dau bung', 'chong mat', 'dau dau'],
};

const OUT_OF_SCOPE_HINTS = ['ke don', 'thuoc gi', 'uong thuoc', 'chan doan', 'toi bi benh gi'];

const FACILITY_HINTS = {
  anbinh: ['an binh', 'an phu', 'hoa sua'],
  songxanh: ['song xanh', 'tan my'],
  hoalac: ['hoa lac', 'cay gao'],
};

const SELF_HINTS = ['cho toi', 'cho minh', 'ban than', 'toi bi', 'toi dau', 'toi muon kham', 'toi can kham', 'toi hay bi'];

const WEEKDAY_WORDS = [
  [1, ['thu hai', 'thu 2']],
  [2, ['thu ba', 'thu 3']],
  [3, ['thu tu', 'thu 4']],
  [4, ['thu nam', 'thu 5']],
  [5, ['thu sau', 'thu 6']],
  [6, ['thu bay', 'thu 7']],
  [0, ['chu nhat']],
];

/** All [position, value] hits of `phrases` in `text`, on word boundaries. */
function hits(text, phrases, value) {
  const found = [];
  for (const phrase of phrases) {
    const re = new RegExp(`(^|\\s)${phrase.replace(/\s+/g, '\\s+')}(?=$|\\s)`, 'g');
    for (const match of text.matchAll(re)) found.push([match.index, value]);
  }
  return found;
}

/** The last mention wins: "sáng thứ Sáu... à không, chiều thứ Bảy". */
const last = (found) => (found.length ? found.reduce((a, b) => (b[0] >= a[0] ? b : a))[1] : null);

function resolveWeekday(today, weekday) {
  return bookableDates(today).find((d) => weekdayIndex(d) === weekday) ?? 'unavailable';
}

function addDays(today, n) {
  const date = parseIsoDate(today);
  date.setUTCDate(date.getUTCDate() + n);
  return isoDate(date);
}

export function extractMock({ utterances, profiles, today }) {
  const out = emptyExtraction();
  for (const utterance of utterances) {
    const t = normalize(utterance);
    if (!t) continue;

    const patient = last([
      ...hits(t, SELF_HINTS, profiles.find((p) => normalize(p.relationship) === 'ban than')?.id),
      ...profiles
        .filter((p) => normalize(p.relationship) !== 'ban than')
        .flatMap((p) => hits(t, [`cho ${normalize(p.relationship)}`, `${normalize(p.relationship)} toi`, `${normalize(p.relationship)} minh`], p.id)),
    ].filter((h) => h[1]));
    if (patient) out.patient_id = patient;

    const type = last([
      ...hits(t, ['bhyt', 'bao hiem y te', 'bao hiem'], 'insurance'),
      ...hits(t, ['dich vu', 'tu chi tra', 'tu tra tien', 'khong dung bao hiem', 'khong bao hiem'], 'service'),
    ]);
    if (type) out.visit_type = type;

    const fac = last(Object.entries(FACILITY_HINTS).flatMap(([id, words]) => hits(t, words, id)));
    if (fac) out.facility_id = fac;

    const dept = last(Object.entries(DEPARTMENT_HINTS).flatMap(([id, words]) => hits(t, words, id)));
    if (dept) {
      out.department_id = dept;
      out.department_reason = dept === 'general'
        ? 'Mô tả chung, nên bắt đầu ở Nội tổng quát.'
        : `Mô tả có nhắc tới vấn đề thường khám ở ${catalog.departments.find((d) => d.id === dept).name}.`;
      out.symptoms_summary = utterance.trim().slice(0, 300);
    }

    const doc = last(
      catalog.doctors.flatMap((d) => hits(t, [normalize(d.name.replace(/^BS\.\s*/, ''))], d.id)),
    );
    if (doc) out.doctor_id = doc;

    const when = last([
      ...hits(t, ['som nhat', 'cang som cang tot', 'luc nao cung duoc', 'gio nao cung duoc'], { kind: 'earliest' }),
      ...hits(t, ['ngay mai', 'sang mai', 'chieu mai'], { kind: 'date', date: addDays(today, 1) }),
      ...hits(t, ['hom nay', 'chieu nay', 'sang nay'], { kind: 'date', date: today }),
      ...WEEKDAY_WORDS.flatMap(([day, words]) =>
        hits(t, words, { kind: 'date', date: resolveWeekday(today, day) })),
    ]);
    if (when) {
      out.time_kind = when.kind;
      out.date = when.date ?? null;
    }
    const period = last([
      ...hits(t, ['buoi sang', 'sang mai', 'sang nay', 'vao sang', ...WEEKDAY_WORDS.flatMap(([, w]) => w.map((x) => `sang ${x}`))], 'morning'),
      ...hits(t, ['buoi chieu', 'chieu mai', 'chieu nay', 'vao chieu', ...WEEKDAY_WORDS.flatMap(([, w]) => w.map((x) => `chieu ${x}`))], 'afternoon'),
    ]);
    if (period) out.period = period;

    // Same mock list the orchestrator checks first (urgent-signs.json, PRD §11).
    if (urgentSigns([utterance]).length) out.urgent_signal = true;
    if (OUT_OF_SCOPE_HINTS.some((h) => hits(t, [h], true).length)) out.out_of_scope = true;
  }
  return out;
}
