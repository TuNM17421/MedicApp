// Vietnamese text helpers shared by the red-flag rules and the summary guard.
// Patients often type without diacritics ("kho tho"), so matching runs on a
// folded form; words whose meaning depends on the diacritics (negations,
// clause breaks, number words) are checked on the original token first.

/** Lower case without diacritics; đ -> d. */
export function fold(text) {
  return text.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[đĐ]/g, 'd').toLowerCase();
}

/**
 * Word tokens of [text]: [{ raw, folded, plain }], `plain` when the token has
 * no diacritics (then the folded form is all we know about it).
 */
export function tokens(text) {
  return text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean).map((raw) => {
    const folded = fold(raw);
    return { raw, folded, plain: raw === folded };
  });
}

/** Sentences of an answer, keeping their punctuation. */
export function sentences(text) {
  return text.replace(/\s+/g, ' ').trim().split(/(?<=[.!?…])\s+/).map((s) => s.trim()).filter(Boolean);
}

/** Clauses inside a sentence: commas, semicolons, colons, dashes and brackets end one. */
export const clauses = (sentence) => sentence.split(/[.,;:!?…()\n]+|\s[-–—]\s/).map((c) => c.trim()).filter(Boolean);

/** Positions where the folded word sequence [needle] starts in [toks]. */
export function findAll(toks, needle) {
  const out = [];
  for (let i = 0; i + needle.length <= toks.length; i++) {
    if (needle.every((w, k) => toks[i + k].folded === w)) out.push(i);
  }
  return out;
}

export const phraseWords = (phrase) => tokens(phrase).map((t) => t.folded);

/** True when [needle] (a folded word list) occurs in [text]. */
export const containsPhrase = (text, needle) => findAll(tokens(text), needle).length > 0;

// ---- numbers -------------------------------------------------------------

const DIGITS = /\d+(?:[.,]\d+)?/g;

/** Number words written with diacritics (unambiguous enough in a summary). */
const STRICT_WORDS = { hai: 2, bốn: 4, lăm: 5, sáu: 6, bảy: 7, tám: 8, chín: 9, mười: 10, mươi: 10 };
/** Folded number words: generous, used only to widen what a source allows. */
const LOOSE_WORDS = { mot: 1, hai: 2, ba: 3, bon: 4, tu: 4, nam: 5, lam: 5, sau: 6, bay: 7, tam: 8, chin: 9, muoi: 10 };

const digitValues = (text) => (text.match(DIGITS) ?? []).map((d) => Number(d.replace(',', '.')));

/**
 * Values of number words in [toks]; compounds are read whole ("hai mươi lăm"
 * = 25, "mười hai" = 12). [generous] also keeps each word's own value.
 */
function wordValues(toks, lookup, generous = false) {
  const out = [];
  for (let i = 0; i < toks.length; i++) {
    const v = lookup(toks[i]);
    if (v === undefined) continue;
    const next = toks[i + 1] ? lookup(toks[i + 1]) : undefined;
    if (v < 10 && next === 10) {
      const unit = toks[i + 2] ? lookup(toks[i + 2]) : undefined;
      const tail = unit !== undefined && unit < 10;
      out.push(v * 10 + (tail ? unit : 0));
      if (generous) out.push(v, 10, ...(tail ? [unit] : []));
      i += tail ? 2 : 1;
    } else if (v === 10 && next !== undefined && next < 10) {
      out.push(10 + next);
      if (generous) out.push(10, next);
      i += 1;
    } else {
      out.push(v);
    }
  }
  return out;
}

/** Numbers a summary sentence states (digits, and number words with diacritics). */
export function numbersIn(text) {
  return [...new Set([...digitValues(text), ...wordValues(tokens(text), (t) => STRICT_WORDS[t.raw])])];
}

/** Every number [text] could be read as stating; used for the cited answers. */
export function numbersAllowedBy(text) {
  return new Set([...digitValues(text), ...wordValues(tokens(text), (t) => LOOSE_WORDS[t.folded], true)]);
}
