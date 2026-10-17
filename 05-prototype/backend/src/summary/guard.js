// Server-side checks on a proposed summary (model or mock). The proposal is
// { sections: [{ key, sentences: [{ text, sources: [answerId] }] }] }.
//  - A sentence with no sources, or citing an id that is not an answer of
//    this visit, is dropped.
//  - A section is dropped whole when one of its sentences states a number or
//    names a drug that its own cited answers do not contain: the model must
//    not compute (adherence, missed doses…) or add anything.
// What is left becomes the stored shape { key, text, sources }.
import { readFileSync } from 'node:fs';

import { containsPhrase, fold, numbersAllowedBy, numbersIn, phraseWords } from './text.js';

export const SECTION_KEYS = ['chief', 'course', 'questions'];
export const MAX_SENTENCES = 4;
export const MAX_SENTENCE = 300;

const drugList = JSON.parse(readFileSync(new URL('./drug-names.json', import.meta.url), 'utf8'));
const clinicCatalog = JSON.parse(readFileSync(new URL('../../catalog/clinic-catalog.json', import.meta.url), 'utf8'));
const NOT_A_NAME = new Set(['vitamin', 'calci', 'nhom', 'kem', 'gel']);

/** Groups of names that count as the same drug, as folded word lists. */
export const DRUG_GROUPS = (() => {
  const groups = drugList.groups.map((g) => g.map(phraseWords));
  const known = new Set(groups.flat().map((w) => w.join(' ')));
  for (const d of clinicCatalog.drugs) {
    const first = fold(d.name).split(/[^a-z0-9]+/)[0];
    if (first && first.length >= 5 && !NOT_A_NAME.has(first) && !known.has(first)) {
      known.add(first);
      groups.push([[first]]);
    }
  }
  return groups;
})();

/** Drug names in [text] (the alias as written), each with its group. */
export function drugsIn(text) {
  const out = [];
  for (const group of DRUG_GROUPS) {
    const alias = group.find((words) => containsPhrase(text, words));
    if (alias) out.push({ name: alias.join(' '), group });
  }
  return out;
}

const clean = (s) => s.replace(/\s+/g, ' ').trim();
const withStop = (s) => (/[.!?…]$/.test(s) ? s : `${s}.`);

/**
 * Why [sentence] is not supported by [cited] answers, or null. Numbers must
 * appear in the cited text (digits or number words); a drug must appear
 * under any name of its group.
 */
export function unsupported(sentence, cited) {
  const source = cited.map((a) => `${a.question ?? ''}\n${a.answer}`).join('\n');
  const allowed = numbersAllowedBy(source);
  const number = numbersIn(sentence).find((n) => !allowed.has(n));
  if (number !== undefined) return { reason: 'number', value: String(number) };
  const drug = drugsIn(sentence).find((d) => !d.group.some((words) => containsPhrase(source, words)));
  if (drug) return { reason: 'drug', value: drug.name };
  return null;
}

/**
 * Applies the checks to [proposal] against [answers] ({ id, question,
 * answer }). Returns { sections, detail, dropped }: `sections` in the stored
 * shape and in SECTION_KEYS order, `detail` the kept sentences with their own
 * sources, `dropped` what was removed and why (no patient text in it).
 */
export function guardSummary(proposal, answers) {
  const byId = new Map(answers.map((a) => [a.id, a]));
  const dropped = [];
  const merged = new Map();
  for (const section of Array.isArray(proposal?.sections) ? proposal.sections : []) {
    const key = section?.key;
    if (!SECTION_KEYS.includes(key)) {
      dropped.push({ key: String(key).slice(0, 40), reason: 'unknown_key' });
      continue;
    }
    if (!merged.has(key)) merged.set(key, []);
    for (const s of Array.isArray(section.sentences) ? section.sentences : []) {
      const text = typeof s?.text === 'string' ? clean(s.text) : '';
      const ids = Array.isArray(s?.sources) ? [...new Set(s.sources.filter((x) => typeof x === 'string'))] : [];
      if (!text) dropped.push({ key, reason: 'empty' });
      else if (text.length > MAX_SENTENCE) dropped.push({ key, reason: 'too_long' });
      else if (!ids.length) dropped.push({ key, reason: 'no_sources' });
      else if (ids.some((id) => !byId.has(id))) dropped.push({ key, reason: 'unknown_source' });
      else if (merged.get(key).length >= MAX_SENTENCES) dropped.push({ key, reason: 'too_many' });
      else merged.get(key).push({ text: withStop(text), sources: ids });
    }
  }
  const sections = [];
  const detail = [];
  for (const key of SECTION_KEYS) {
    const kept = merged.get(key);
    if (!kept?.length) continue;
    const bad = kept.map((s) => unsupported(s.text, s.sources.map((id) => byId.get(id)))).find(Boolean);
    if (bad) {
      dropped.push({ key, ...bad });
      continue;
    }
    detail.push({ key, sentences: kept });
    sections.push({ key, text: kept.map((s) => s.text).join(' '), sources: [...new Set(kept.flatMap((s) => s.sources))] });
  }
  return { sections, detail, dropped };
}
