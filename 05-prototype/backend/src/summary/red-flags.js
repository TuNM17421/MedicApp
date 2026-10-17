// Red-flag signs in the patient's own answers, found by a phrase list in
// code (red-flags.json), never by the model. Matching ignores diacritics and
// skips a phrase negated in its own clause ("không đau ngực", "chưa bao giờ
// ngất"). When unsure it flags: a missed sign costs more than an extra note.
import { readFileSync } from 'node:fs';

import { clauses, findAll, phraseWords, sentences, tokens } from './text.js';

export const redFlagList = JSON.parse(readFileSync(new URL('./red-flags.json', import.meta.url), 'utf8'));

const SIGNS = redFlagList.signs.map((s) => ({
  code: s.code,
  label: s.label,
  phrases: s.phrases.map(phraseWords),
  except: (s.except ?? []).map(phraseWords),
}));

// Words that negate what follows in the clause. Plain (no-diacritic) forms
// count only when typed without diacritics: "cha" (father) is not "chả".
const NEG = new Set(['không', 'chẳng', 'chả', 'chưa', 'hông', 'hổng', 'khỏi']);
const NEG_PLAIN = new Set(['khong', 'ko', 'k', 'kh', 'khg', 'hong', 'hok', 'chang', 'chua']);
// "không biết có phải đau ngực không": uncertainty, not a denial.
const UNSURE = new Set(['biết', 'rõ', 'nhớ', 'chắc', 'hiểu']);
const UNSURE_PLAIN = new Set(['biet', 'ro', 'nho', 'chac', 'hieu']);
// Words that start a new statement inside a clause: "không sốt nhưng khó thở".
// "không đau ngực hay khó thở" keeps the denial: hay, hoặc, và are not breaks.
const BREAK = new Set(['nhưng', 'mà', 'vì', 'do', 'nên', 'thì', 'khi', 'lúc', 'sau', 'lại', 'rồi', 'còn', 'tuy', 'song', 'nay', 'thỉnh', 'đôi']);
const BREAK_PLAIN = new Set(['nhung', 'ma', 'vi', 'do', 'nen', 'thi', 'khi', 'luc', 'sau', 'lai', 'roi', 'tuy', 'song', 'nay', 'thinh', 'doi']);
const NEG_WINDOW = 6;

const is = (tok, withMarks, plain) => withMarks.has(tok.raw) || (tok.plain && plain.has(tok.folded));
const isNeg = (t) => is(t, NEG, NEG_PLAIN);
const isUnsure = (t) => is(t, UNSURE, UNSURE_PLAIN);
const isBreak = (t) => is(t, BREAK, BREAK_PLAIN);

/** True when the phrase starting at [i] is denied earlier in its clause. */
function negated(toks, i) {
  for (let j = i - 1; j >= 0 && i - j <= NEG_WINDOW; j--) {
    const t = toks[j];
    if (isNeg(t)) {
      const next = toks[j + 1];
      return !(next && j + 1 < i && isUnsure(next));
    }
    if (isBreak(t)) return false;
  }
  return false;
}

/** Signs (codes) stated, not denied, in one clause. */
function signsInClause(clause) {
  const toks = tokens(clause);
  const found = new Set();
  for (const sign of SIGNS) {
    const excluded = new Set();
    for (const ex of sign.except) {
      for (const at of findAll(toks, ex)) for (let k = 0; k < ex.length; k++) excluded.add(at + k);
    }
    for (const words of sign.phrases) {
      const hit = findAll(toks, words).some((at) => !words.some((_, k) => excluded.has(at + k)) && !negated(toks, at));
      if (hit) {
        found.add(sign.code);
        break;
      }
    }
  }
  return found;
}

const MAX_FLAG_TEXT = 300;

/**
 * Flags for the visit: one per answer that states a sign, as
 * { text, sources: [answerId], signs: [label] }. text is the answer's own
 * sentence(s) holding the sign, verbatim.
 */
export function detectRedFlags(answers) {
  const flags = [];
  for (const a of answers) {
    const codes = new Set();
    const hit = [];
    for (const s of sentences(a.answer)) {
      const inSentence = new Set(clauses(s).flatMap((c) => [...signsInClause(c)]));
      if (!inSentence.size) continue;
      hit.push(s);
      for (const c of inSentence) codes.add(c);
    }
    if (!codes.size) continue;
    let text = hit.join(' ');
    if (text.length > MAX_FLAG_TEXT) text = `${text.slice(0, MAX_FLAG_TEXT - 1).replace(/\s+\S*$/, '')}…`;
    flags.push({
      text,
      sources: [a.id],
      signs: SIGNS.filter((s) => codes.has(s.code)).map((s) => s.label),
      codes: [...codes],
    });
  }
  return flags;
}

/** Codes of the signs found in free text (eval and tests). */
export const signCodes = (text) => [...new Set(detectRedFlags([{ id: 'x', answer: text }]).flatMap((f) => f.codes))];
