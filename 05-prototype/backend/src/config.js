import { existsSync } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/** The backend folder; relative paths in `.env` are resolved against it. */
export const backendDir = fileURLToPath(new URL('..', import.meta.url));
const envFile = fileURLToPath(new URL('../.env', import.meta.url));

function path(env, name, fallback) {
  const raw = (env[name] ?? '').trim() || fallback;
  return isAbsolute(raw) ? resolve(raw) : resolve(backendDir, raw);
}

function origin(env, name) {
  const raw = (env[name] ?? '').trim();
  if (!raw) return null;
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    parsed = null;
  }
  if (!parsed || !['http:', 'https:'].includes(parsed.protocol) || parsed.origin !== raw.replace(/\/$/, '')) {
    throw new Error(`${name} phải là một origin, ví dụ http://localhost:5000.`);
  }
  return parsed.origin;
}

/** Reads `.env` (if present) without overriding variables already set. */
export function loadEnvFile(path = envFile) {
  if (existsSync(path)) process.loadEnvFile(path);
}

function int(env, name, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const raw = env[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`${name} phải là số nguyên trong khoảng ${min}–${max}.`);
  }
  return value;
}

/**
 * Builds the validated configuration. The API key is kept in a closure-free
 * field that is never serialised: `describe()` is the only view that leaves
 * the process, and it reports only whether a key is present.
 */
export function readConfig(env = process.env) {
  const apiKey = (env.OPENAI_API_KEY ?? '').trim();
  const requested = (env.SMART_MODE ?? 'auto').trim().toLowerCase();
  if (!['auto', 'mock', 'openai'].includes(requested)) {
    throw new Error('SMART_MODE chỉ nhận auto, mock hoặc openai.');
  }
  if (requested === 'openai' && !apiKey) {
    throw new Error('SMART_MODE=openai cần OPENAI_API_KEY trong backend/.env.');
  }
  const mode = requested === 'auto' ? (apiKey ? 'openai' : 'mock') : requested;
  const host = (env.HOST ?? '127.0.0.1').trim();
  if (!['127.0.0.1', 'localhost', '::1'].includes(host) && env.ALLOW_NON_LOCAL_HOST !== '1') {
    throw new Error('Backend dev chỉ bind localhost. Đặt ALLOW_NON_LOCAL_HOST=1 nếu thật sự cần.');
  }
  const effort = (env.OPENAI_REASONING_EFFORT ?? 'low').trim();
  if (!['none', 'minimal', 'low', 'medium', 'high'].includes(effort)) {
    throw new Error('OPENAI_REASONING_EFFORT không hợp lệ.');
  }
  const maxRecordingSeconds = int(env, 'MAX_RECORDING_SECONDS', 60, { max: 300 });
  const config = {
    mode,
    host,
    port: int(env, 'PORT', 8080, { max: 65535 }),
    model: (env.OPENAI_MODEL ?? 'gpt-6-luna').trim(),
    reasoningEffort: effort,
    sttModel: (env.OPENAI_STT_MODEL ?? 'gpt-live-transcribe').trim(),
    maxOutputTokens: int(env, 'MAX_OUTPUT_TOKENS', 1200, { min: 200, max: 8000 }),
    maxRecordingSeconds,
    // PCM16 mono at 24 kHz is 48 000 bytes per second.
    maxTurnAudioBytes: Math.min(
      int(env, 'MAX_AUDIO_BYTES', 5 * 1024 * 1024),
      maxRecordingSeconds * 48_000,
    ),
    maxSessionAudioSeconds: int(env, 'MAX_SESSION_AUDIO_SECONDS', 300, { max: 1800 }),
    modelCallsPerMinute: int(env, 'MODEL_CALLS_PER_MINUTE', 12, { max: 120 }),
    modelTimeoutMs: int(env, 'MODEL_TIMEOUT_MS', 20_000, { min: 1000 }),
    sessionIdleMs: int(env, 'SESSION_IDLE_MINUTES', 30, { max: 240 }) * 60_000,
    maxSessions: int(env, 'MAX_SESSIONS', 20, { max: 500 }),
    // Clinic database and doctor web (bước 14).
    clinicDb: path(env, 'CLINIC_DB', 'data/clinic.db'),
    doctorWebDir: path(env, 'DOCTOR_WEB_DIR', '../doctor_web/build/web'),
    doctorWebDevOrigin: origin(env, 'DOCTOR_WEB_DEV_ORIGIN'),
    // Set when the server sits behind HTTPS: the staff cookie gets `Secure`.
    https: env.HTTPS === '1',
  };
  Object.defineProperty(config, 'apiKey', { value: apiKey, enumerable: false });
  return Object.freeze(config);
}

/** Public, key-free description used by `/health` and the startup log. */
export function describe(config) {
  return {
    mode: config.mode,
    model: config.model,
    reasoning_effort: config.reasoningEffort,
    stt_model: config.sttModel,
    key_configured: Boolean(config.apiKey),
    limits: {
      turn_audio_seconds: config.maxRecordingSeconds,
      session_audio_seconds: config.maxSessionAudioSeconds,
      model_calls_per_minute: config.modelCallsPerMinute,
      max_output_tokens: config.maxOutputTokens,
    },
  };
}
