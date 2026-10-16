// Bước 17: makes the pre-visit summary in the background. The intake upload
// calls schedule(appointmentId) and answers at once; after a quiet time
// (SUMMARY_DEBOUNCE_MS) one run reads all answers of the visit. Answers that
// arrive during a run trigger one more run after it. In-process only: a
// restart forgets pending runs (the next upload schedules again).
//
// A run needs a live consent with 'intake'. It inserts a new visit_summary
// row (never updates one) unless the answers are the same as for the newest
// summary, and writes an audit_event 'summary.generate' (actor 'system').
// Logs carry counts and codes only.
import { createHash, randomUUID } from 'node:crypto';

import { localIso } from '../clinic/time.js';
import { summariseMock } from './mock.js';
import { PROMPT_VERSION, createOpenAISummariser } from './openai.js';
import { runSummary } from './pipeline.js';

const MAX_PARALLEL = 2;

const json = (text, fallback) => {
  try {
    return JSON.parse(text);
  } catch {
    return fallback;
  }
};

/** The summariser for config.summaryMode, or null when off. */
export function defaultSummariser(config, log) {
  if (config.summaryMode === 'openai') return createOpenAISummariser(config, { log });
  if (config.summaryMode === 'mock') return summariseMock;
  return null;
}

export function createSummaryWorker({ db, config, log = () => {}, summarise, debounceMs = config.summaryDebounceMs }) {
  const mode = config.summaryMode;
  const fn = summarise ?? defaultSummariser(config, log);
  const q = (sql) => db.prepare(sql);
  const stmt = {
    appointment: q(`SELECT a.id, a.patient_id, a.status, p.full_name, p.phone, p.insurance_code, p.address
      FROM appointment a JOIN patient p ON p.id = a.patient_id WHERE a.id = ?`),
    consent: q('SELECT * FROM consent WHERE appointment_id = ? ORDER BY granted_at DESC, rowid DESC LIMIT 1'),
    intake: q('SELECT id, channel, question, answer FROM intake_answer WHERE appointment_id = ? ORDER BY answered_at, id'),
    newest: q('SELECT input_hash, mode, prompt_version FROM visit_summary WHERE appointment_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1'),
    insert: q(`INSERT INTO visit_summary (id, appointment_id, sections, flags, mode, model, prompt_version, created_at, input_hash)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`),
    audit: q(`INSERT INTO audit_event (at, actor, action, patient_id, appointment_id, detail, ip)
      VALUES (?, 'system', 'summary.generate', ?, ?, ?, '')`),
  };

  const sharesIntake = (appointmentId) => {
    const c = stmt.consent.get(appointmentId);
    return Boolean(c && !c.revoked_at && c.expires_at > localIso() && json(c.scope, []).includes('intake'));
  };

  /**
   * One run for the visit. Returns { status, summaryId? }: 'created',
   * 'skipped' (with reason) or 'failed' (with code).
   */
  async function generate(appointmentId, { signal } = {}) {
    if (!fn) return { status: 'skipped', reason: 'off' };
    const a = stmt.appointment.get(appointmentId);
    if (!a) return { status: 'skipped', reason: 'not_found' };
    if (a.status === 'cancelled') return { status: 'skipped', reason: 'cancelled' };
    if (!sharesIntake(a.id)) return { status: 'skipped', reason: 'no_consent' };
    const rows = stmt.intake.all(a.id);
    if (!rows.length) return { status: 'skipped', reason: 'no_answers' };
    const hash = createHash('sha256').update(JSON.stringify(rows.map((r) => [r.id, r.channel, r.question, r.answer]))).digest('base64url');
    const newest = stmt.newest.get(a.id);
    if (newest && newest.input_hash === hash && newest.mode === mode && newest.prompt_version === PROMPT_VERSION) {
      return { status: 'skipped', reason: 'unchanged' };
    }
    const audit = (detail) => stmt.audit.run(localIso(), a.patient_id, a.id, JSON.stringify(detail));
    const started = Date.now();
    let out;
    try {
      out = await runSummary({
        rows,
        summarise: fn,
        pii: { name: a.full_name, phone: a.phone ?? '', insuranceCode: a.insurance_code, address: a.address },
        signal,
      });
    } catch (error) {
      const code = error?.code ?? 'internal';
      log('summary_generate', { result: 'failed', mode, code, latency_ms: Date.now() - started });
      audit({ result: 'failed', mode, code, promptVersion: PROMPT_VERSION });
      return { status: 'failed', code };
    }
    // Consent may have been withdrawn while the model was working.
    if (!sharesIntake(a.id)) return { status: 'skipped', reason: 'no_consent' };
    if (!out.sections.length && !out.flags.length) {
      log('summary_generate', { result: 'empty', mode, dropped: out.dropped.length });
      audit({ result: 'empty', mode, answers: rows.length, dropped: out.dropped.map((d) => d.reason), promptVersion: PROMPT_VERSION });
      return { status: 'skipped', reason: 'empty' };
    }
    const id = `s-${randomUUID()}`;
    const model = mode === 'openai' ? config.model : '';
    const flags = out.flags.map((f) => ({ text: f.text, sources: f.sources, signs: f.signs }));
    stmt.insert.run(id, a.id, JSON.stringify(out.sections), JSON.stringify(flags), mode, model, PROMPT_VERSION, localIso(), hash);
    const detail = {
      result: 'created', summaryId: id, mode, model, promptVersion: PROMPT_VERSION, answers: rows.length,
      sections: out.sections.map((s) => s.key), flags: flags.length, dropped: out.dropped.map((d) => `${d.key}:${d.reason}`),
    };
    audit(detail);
    log('summary_generate', {
      result: 'created', mode, sections: out.sections.length, flags: flags.length, dropped: out.dropped.length, latency_ms: Date.now() - started,
    });
    return { status: 'created', summaryId: id };
  }

  // ---- queue ---------------------------------------------------------------

  const timers = new Map();
  const running = new Map();
  const again = new Set();
  const waiting = [];
  const controllers = new Set();
  let active = 0;
  let closed = false;

  const slot = () => (active < MAX_PARALLEL ? Promise.resolve(active++) : new Promise((r) => waiting.push(r)).then(() => active++));
  const release = () => {
    active--;
    waiting.shift()?.();
  };

  function start(id) {
    if (closed) return;
    if (running.has(id)) {
      again.add(id);
      return;
    }
    const run = (async () => {
      await slot();
      const controller = new AbortController();
      controllers.add(controller);
      try {
        if (!closed) await generate(id, { signal: controller.signal });
      } catch (error) {
        log('summary_generate', { result: 'error', name: error?.name ?? 'Error' });
      } finally {
        controllers.delete(controller);
        release();
      }
    })().finally(() => {
      running.delete(id);
      if (again.delete(id)) start(id);
    });
    running.set(id, run);
  }

  /** Runs a summary for the visit after the quiet time; never throws, never waits. */
  function schedule(appointmentId) {
    if (closed || !fn) return;
    clearTimeout(timers.get(appointmentId));
    const t = setTimeout(() => {
      timers.delete(appointmentId);
      start(appointmentId);
    }, debounceMs);
    t.unref?.();
    timers.set(appointmentId, t);
  }

  return {
    mode,
    schedule,
    generate,
    /** Tests: start pending runs now. */
    flush() {
      for (const [id, t] of timers) {
        clearTimeout(t);
        timers.delete(id);
        start(id);
      }
    },
    /** Resolves when no run is pending or running (pending timers are waited for). */
    async idle() {
      while (timers.size || running.size) {
        if (running.size) await Promise.allSettled([...running.values()]);
        else await new Promise((r) => setTimeout(r, Math.min(debounceMs, 50) + 1));
      }
    },
    pending: () => timers.size + running.size,
    close() {
      closed = true;
      for (const t of timers.values()) clearTimeout(t);
      timers.clear();
      for (const c of controllers) c.abort();
    },
  };
}
