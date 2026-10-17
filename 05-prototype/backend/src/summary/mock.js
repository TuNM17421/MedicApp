// "Mô phỏng AI" summariser: deterministic rules, no model. Each answer goes
// to one section by its question (or channel), and the first answers of a
// section are copied, trimmed, as its sentences. Same output shape as the
// model, so the same guard runs on it.
import { fold } from './text.js';

const PER_SECTION = 2;
const MAX_TEXT = 220;

const QUESTIONS = /muon hoi|hoi bac si|thac mac|can hoi|hoi gi/;
const COURSE = /thuoc|tu dung|tu uong|tu mua|tu xu ly|dien bien|nang hon|nhe hon|do hon|kem theo|trieu chung khac|bao lau|tu khi nao|thay doi/;
const CHIEF = /ly do|van de|kham gi|dang gap|kho chiu gi|trieu chung chinh|vi sao|vi dieu gi|di kham vi/;

/** Section key for one answer. */
export function sectionOf(a) {
  const q = fold(a.question ?? '');
  if (QUESTIONS.test(q)) return 'questions';
  if (COURSE.test(q)) return 'course';
  if (CHIEF.test(q) || a.channel === 'booking') return 'chief';
  // A free answer that is itself a question ("Có cần nội soi không ạ?").
  if (!q && /\?\s*$/.test(a.answer)) return 'questions';
  return 'course';
}

/** The answer, cut at a sentence (or word) end so no number is split. */
export function trimAnswer(text) {
  const t = text.replace(/\s+/g, ' ').trim();
  if (t.length <= MAX_TEXT) return t;
  const head = t.slice(0, MAX_TEXT);
  const stop = Math.max(head.lastIndexOf('. '), head.lastIndexOf('? '), head.lastIndexOf('! '));
  if (stop > MAX_TEXT / 3) return head.slice(0, stop + 1);
  return `${head.replace(/\s+\S*$/, '')}…`;
}

export async function summariseMock({ answers }) {
  const bySection = new Map();
  for (const a of answers) {
    const key = sectionOf(a);
    if (!bySection.has(key)) bySection.set(key, []);
    const list = bySection.get(key);
    if (list.length < PER_SECTION) list.push({ text: trimAnswer(a.answer), sources: [a.id] });
  }
  return { sections: [...bySection].map(([key, sentences]) => ({ key, sentences })) };
}
