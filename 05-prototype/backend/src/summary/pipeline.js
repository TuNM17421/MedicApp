// One summary run over a visit's intake answers: redact, give the answers
// short ids, ask the summariser (mock or model), guard the proposal, map the
// ids back, and find red flags with the phrase list. Pure apart from the
// summariser call, so the eval script runs exactly this.
import { guardSummary } from './guard.js';
import { detectRedFlags } from './red-flags.js';

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Removes what identifies the person from an answer before it leaves the
 * server: their name, phone, insurance code and address as stored, and any
 * phone-like number or insurance-like code.
 */
export function redact(text, { name = '', phone = '', insuranceCode = '', address = '' } = {}) {
  let out = text;
  for (const [value, mask] of [[name, '[tên]'], [address, '[địa chỉ]'], [insuranceCode, '[mã BHYT]']]) {
    if (value && value.trim().length >= 3) out = out.replace(new RegExp(escape(value.trim()), 'giu'), mask);
  }
  if (phone) out = out.replace(new RegExp(phone.split('').map(escape).join('[\\s.-]?'), 'g'), '[số điện thoại]');
  out = out.replace(/\b[A-Z]{2}\d{13}\b/gi, '[mã BHYT]');
  out = out.replace(/(?<!\d)(?:\+?84|0)(?:[\s.-]?\d){9}(?!\d)/g, '[số điện thoại]');
  return out;
}

/**
 * [rows]: intake answers { id, channel, question, answer } of one visit.
 * [summarise]: async ({ answers, signal }) -> proposal. [pii]: see redact.
 * Returns { sections, flags, detail, dropped } with real answer ids.
 */
export async function runSummary({ rows, summarise, pii = {}, signal }) {
  const shortId = new Map();
  const realId = new Map();
  rows.forEach((r, i) => {
    shortId.set(r.id, `a${i + 1}`);
    realId.set(`a${i + 1}`, r.id);
  });
  const modelAnswers = rows.map((r) => ({
    id: shortId.get(r.id),
    channel: r.channel,
    question: redact(r.question ?? '', pii),
    answer: redact(r.answer, pii),
  }));
  const proposal = await summarise({ answers: modelAnswers, signal });
  // The guard checks against the answers as the person wrote them.
  const guardAnswers = rows.map((r) => ({ ...r, id: shortId.get(r.id) }));
  const { sections, detail, dropped } = guardSummary(proposal, guardAnswers);
  const back = (ids) => ids.map((id) => realId.get(id));
  return {
    sections: sections.map((s) => ({ ...s, sources: back(s.sources) })),
    detail: detail.map((d) => ({ key: d.key, sentences: d.sentences.map((s) => ({ ...s, sources: back(s.sources) })) })),
    dropped,
    flags: detectRedFlags(rows),
  };
}
