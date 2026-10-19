// Bước 17 evaluation: runs the 30 sample conversations of summary-cases.json
// through the same pipeline as the server (src/summary/pipeline.js) and
// checks, per case:
//   - sources: every kept sentence cites at least one answer, all of this case;
//   - grounded: no number or drug name in a sentence that its cited answers
//     do not contain;
//   - flags: every expected red flag is found, none of the negated ones, and
//     nothing else.
// Mode: openai when CLINIC_AI_SUMMARY resolves to openai (key in .env),
// otherwise mock. `--mock` forces mock. Exits 1 when a check fails.
//
//   npm run eval:summary
//   npm run eval:summary -- --mock
import { readFileSync } from 'node:fs';

import { loadEnvFile, readConfig } from '../src/config.js';
import { unsupported } from '../src/summary/guard.js';
import { summariseMock } from '../src/summary/mock.js';
import { createOpenAISummariser } from '../src/summary/openai.js';
import { runSummary } from '../src/summary/pipeline.js';

loadEnvFile();
const config = readConfig();
const forceMock = process.argv.includes('--mock');
const mode = !forceMock && config.summaryMode === 'openai' ? 'openai' : 'mock';
const summarise = mode === 'openai' ? createOpenAISummariser(config) : summariseMock;
const { cases } = JSON.parse(readFileSync(new URL('./summary-cases.json', import.meta.url), 'utf8'));

const rows = [];
let failed = 0;
const totals = { sentences: 0, sourced: 0, grounded: 0, expected: 0, caught: 0, negated: 0, falseFlags: 0, dropped: 0 };

for (const c of cases) {
  const problems = [];
  let out;
  try {
    out = await runSummary({ rows: c.answers, summarise });
  } catch (error) {
    problems.push(`error ${error.code ?? error.name}`);
    out = { detail: [], sections: [], flags: [], dropped: [] };
  }
  const byId = new Map(c.answers.map((a) => [a.id, a]));
  const kept = out.detail.flatMap((d) => d.sentences);
  const sourced = kept.filter((s) => s.sources.length && s.sources.every((id) => byId.has(id)));
  const grounded = sourced.filter((s) => !unsupported(s.text, s.sources.map((id) => byId.get(id))));
  // The stored section (text + union of sources) must hold as well.
  for (const s of out.sections) {
    const bad = unsupported(s.text, s.sources.map((id) => byId.get(id)).filter(Boolean));
    if (bad) problems.push(`section ${s.key}: ${bad.reason} ${bad.value}`);
  }
  if (sourced.length !== kept.length) problems.push(`${kept.length - sourced.length} sentence(s) without valid sources`);
  if (grounded.length !== sourced.length) problems.push(`${sourced.length - grounded.length} ungrounded sentence(s)`);

  const got = new Set(out.flags.flatMap((f) => f.codes));
  const missed = c.expectFlags.filter((code) => !got.has(code));
  const onNegated = (c.negated ?? []).filter((code) => got.has(code));
  const extra = [...got].filter((code) => !c.expectFlags.includes(code) && !onNegated.includes(code));
  if (missed.length) problems.push(`missed flag ${missed.join(',')}`);
  if (onNegated.length) problems.push(`flag on negated ${onNegated.join(',')}`);
  if (extra.length) problems.push(`unexpected flag ${extra.join(',')}`);
  for (const f of out.flags) if (!f.sources.length || !f.sources.every((id) => byId.has(id))) problems.push('flag without valid source');

  totals.sentences += kept.length;
  totals.sourced += sourced.length;
  totals.grounded += grounded.length;
  totals.expected += c.expectFlags.length;
  totals.caught += c.expectFlags.length - missed.length;
  totals.negated += (c.negated ?? []).length;
  totals.falseFlags += onNegated.length + extra.length;
  totals.dropped += out.dropped.length;
  if (problems.length) failed++;
  rows.push({
    id: c.id,
    title: c.title.length > 44 ? `${c.title.slice(0, 43)}…` : c.title,
    sections: out.sections.map((s) => s.key[0] + s.key[1]).join(' ') || '-',
    sent: `${kept.length}`,
    drop: `${out.dropped.length}`,
    flags: `${[...got].sort().join(',') || '-'}`,
    result: problems.length ? `FAIL ${problems.join('; ')}` : 'ok',
  });
}

const cols = ['id', 'title', 'sections', 'sent', 'drop', 'flags', 'result'];
const width = Object.fromEntries(cols.map((k) => [k, Math.max(k.length, ...rows.map((r) => r[k].length))]));
const line = (r) => cols.map((k) => (k === 'result' ? r[k] : r[k].padEnd(width[k]))).join(' | ');
console.log(`Tóm tắt trước khám: eval ${cases.length} ca, chế độ ${mode}${mode === 'openai' ? ` (${config.model})` : ''}\n`);
console.log(line(Object.fromEntries(cols.map((k) => [k, k]))));
console.log(cols.map((k) => '-'.repeat(k === 'result' ? 6 : width[k])).join('-|-'));
for (const r of rows) console.log(line(r));
const pct = (a, b) => (b ? `${((100 * a) / b).toFixed(1)}%` : 'n/a');
console.log(`
Câu giữ lại có nguồn hợp lệ: ${totals.sourced}/${totals.sentences} (${pct(totals.sourced, totals.sentences)})
Câu không có số/tên thuốc ngoài nguồn: ${totals.grounded}/${totals.sentences} (${pct(totals.grounded, totals.sentences)})
Cờ bắt được: ${totals.caught}/${totals.expected} (${pct(totals.caught, totals.expected)}); cờ sai (phủ định hoặc thừa): ${totals.falseFlags} trên ${totals.negated} câu phủ định
Mục/câu bị bộ kiểm tra bỏ: ${totals.dropped}
Kết quả: ${failed ? `${failed} ca KHÔNG ĐẠT` : 'tất cả đạt'}`);
process.exit(failed ? 1 : 0);
