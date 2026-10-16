import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';

import { WebSocketServer } from 'ws';

import { attachAudio } from './audio-relay.js';
import { catalog, parseIsoDate } from './catalog.js';
import { describe, loadEnvFile, readConfig } from './config.js';
import { extractMock } from './extractors/mock.js';
import { createOpenAIExtractor } from './extractors/openai.js';
import { createSessionState, handleUserValue, handleUtterance, reply } from './orchestrator.js';
import { createOpenAIStt, unavailableStt } from './stt.js';
import { CLINIC_PREFIXES, createClinicApi } from './clinic/api.js';
import { SECURITY_HEADERS, serveDoctorWeb } from './clinic/static.js';
import { HttpError, readJson, sendJson } from './http.js';

/** Technical log only: never key, transcript, symptoms, profiles or tokens. */
export function createLogger(write = (line) => console.log(line)) {
  return (event, fields = {}) => write(JSON.stringify({ t: new Date().toISOString(), event, ...fields }));
}

function parseContext(body) {
  const today = typeof body.today === 'string' && parseIsoDate(body.today) ? body.today : null;
  if (!today) throw new HttpError(400, 'bad_context', 'Thiếu ngày hiện tại hợp lệ.');
  const profiles = Array.isArray(body.profiles) ? body.profiles : [];
  if (!profiles.length || profiles.length > 20) throw new HttpError(400, 'bad_context', 'Danh sách người khám không hợp lệ.');
  const clean = profiles.map((p) => {
    const ok = p && typeof p.id === 'string' && p.id.length <= 64 && typeof p.relationship === 'string'
      && p.relationship.length <= 40 && Number.isInteger(p.age) && p.age >= 0 && p.age <= 130;
    if (!ok) throw new HttpError(400, 'bad_context', 'Hồ sơ người khám không hợp lệ.');
    // Names, birth dates and phone numbers are not needed here and not accepted.
    return { id: p.id, relationship: p.relationship.trim(), age: p.age };
  });
  const known = body.known ?? {};
  return {
    today,
    profiles: clean,
    known: { patientId: known.patient_id, type: known.visit_type, facilityId: known.facility_id },
  };
}

export function createApp({ config, extractor, stt, log = createLogger(), db = null }) {
  const sessions = new Map();
  const clinic = db ? createClinicApi({ db, config, log }) : null;

  const sweep = setInterval(() => {
    const now = Date.now();
    for (const [id, s] of sessions) if (now - s.lastSeen > config.sessionIdleMs) close(id, 'expired');
  }, 60_000);
  sweep.unref();

  function close(id, reason) {
    const s = sessions.get(id);
    if (!s) return;
    s.inflight?.abort();
    s.audio?.close(1000, reason);
    sessions.delete(id);
    log('session_closed', { reason });
  }

  function authorize(id, token) {
    const s = sessions.get(id);
    if (!s || typeof token !== 'string') throw new HttpError(404, 'session_not_found', 'Phiên đã hết hạn. Vui lòng bắt đầu lại.');
    const a = Buffer.from(s.token);
    const b = Buffer.from(token);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new HttpError(404, 'session_not_found', 'Phiên đã hết hạn. Vui lòng bắt đầu lại.');
    }
    s.lastSeen = Date.now();
    return s;
  }

  /** Dev only: CORS for `flutter run -d web-server` on DOCTOR_WEB_DEV_ORIGIN, never `*`. */
  function cors(req, res) {
    const origin = config.doctorWebDevOrigin;
    if (!origin) return false;
    res.setHeader('vary', 'Origin');
    if (req.headers.origin !== origin) return false;
    res.setHeader('access-control-allow-origin', origin);
    res.setHeader('access-control-allow-credentials', 'true');
    if (req.method !== 'OPTIONS') return false;
    res.writeHead(204, {
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'access-control-allow-headers': 'content-type',
      'access-control-max-age': '600',
    });
    res.end();
    return true;
  }

  async function route(req, res) {
    const url = new URL(req.url, 'http://localhost');
    const parts = url.pathname.split('/').filter(Boolean);
    if (cors(req, res)) return;
    const read = req.method === 'GET' || req.method === 'HEAD';
    if (read && (url.pathname === '/' || url.pathname === '/doctor')) {
      res.writeHead(302, { location: '/doctor/', 'cache-control': 'no-store', ...SECURITY_HEADERS });
      res.end();
      return;
    }
    if (read && url.pathname.startsWith('/doctor/')) return serveDoctorWeb(req, res, url.pathname, config.doctorWebDir);
    if (parts[0] === 'v1' && CLINIC_PREFIXES.includes(parts[1])) {
      if (!clinic) throw new HttpError(503, 'clinic_unavailable', 'Chưa mở cơ sở dữ liệu phòng khám.');
      return clinic.handle(req, res, url);
    }
    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, { status: 'ok', ...describe(config), catalog_version: catalog.version, sessions: sessions.size });
    }
    if (parts[0] !== 'v1' || parts[1] !== 'smart' || parts[2] !== 'sessions') {
      throw new HttpError(404, 'not_found', 'Không tìm thấy.');
    }
    if (req.method === 'POST' && parts.length === 3) {
      if (sessions.size >= config.maxSessions) throw new HttpError(503, 'busy', 'Máy chủ đang bận, vui lòng thử lại.');
      const context = parseContext(await readJson(req));
      const id = randomUUID();
      const session = createSessionState({ id, ...context });
      session.token = randomBytes(24).toString('base64url');
      session.lastSeen = Date.now();
      sessions.set(id, session);
      log('session_created', { mode: config.mode });
      return sendJson(res, 201, {
        session_id: id,
        token: session.token,
        mode: config.mode,
        voice_available: stt.available,
        expires_in_seconds: config.sessionIdleMs / 1000,
        reply: reply(session, { mode: config.mode }),
      });
    }
    const session = authorize(parts[3], req.headers['x-session-token']);
    if (req.method === 'DELETE' && parts.length === 4) {
      close(session.id, 'client');
      res.writeHead(204).end();
      return;
    }
    if (req.method === 'POST' && parts[4] === 'turns' && parts.length === 5) {
      const body = await readJson(req);
      const turnId = typeof body.client_turn_id === 'string' ? body.client_turn_id.slice(0, 40) : null;
      if (body.kind === 'text') {
        const text = typeof body.text === 'string' ? body.text.trim() : '';
        if (!text || text.length > 1000) throw new HttpError(400, 'bad_turn', 'Nội dung trống hoặc quá dài.');
        const result = await handleUtterance(session, text, {
          extractor,
          mode: config.mode,
          limit: config.modelCallsPerMinute,
          turnId,
          log,
        });
        return sendJson(res, 200, result);
      }
      if (body.kind === 'choice' || body.kind === 'edit') {
        const result = handleUserValue(session, body.field, body.value ?? null, {
          mode: config.mode,
          source: body.kind === 'edit' ? 'manual' : 'choice',
        });
        if (!result) throw new HttpError(400, 'bad_value', 'Lựa chọn không hợp lệ.');
        return sendJson(res, 200, { ...result, turn_id: turnId });
      }
      throw new HttpError(400, 'bad_turn', 'Loại lượt không hợp lệ.');
    }
    throw new HttpError(404, 'not_found', 'Không tìm thấy.');
  }

  const server = createServer((req, res) => {
    route(req, res).catch((error) => {
      const status = error instanceof HttpError ? error.status : 500;
      if (status === 500) log('http_error', { name: error.name });
      // No stack traces or provider payloads leave the server.
      sendJson(res, status, {
        error: {
          code: error instanceof HttpError ? error.code : 'internal',
          message: error instanceof HttpError ? error.message : 'Có lỗi máy chủ. Vui lòng thử lại.',
          ...(error instanceof HttpError && error.fields ? { fields: error.fields } : {}),
        },
      });
    });
  });

  const wss = new WebSocketServer({ noServer: true, maxPayload: 256 * 1024 });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://localhost');
    const parts = url.pathname.split('/').filter(Boolean);
    let session;
    try {
      if (parts.length !== 5 || parts[4] !== 'audio') throw new Error();
      session = authorize(parts[3], url.searchParams.get('token'));
    } catch {
      socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => attachAudio(ws, session, { config, stt, extractor, log }));
  });

  server.on('close', () => {
    clearInterval(sweep);
    clinic?.close();
    for (const id of [...sessions.keys()]) close(id, 'shutdown');
  });
  server.sessions = sessions;
  server.clinic = clinic;
  return server;
}

export function createDefaultDeps(config, log) {
  if (config.mode === 'openai') {
    return { extractor: createOpenAIExtractor(config, { log }), stt: createOpenAIStt(config, { log }) };
  }
  return { extractor: async (input) => extractMock(input), stt: unavailableStt };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  loadEnvFile();
  const config = readConfig();
  const log = createLogger();
  // Imported here so the smart-scheduling tests do not load node:sqlite.
  const { openDatabase } = await import('./db/index.js');
  const db = openDatabase(config.clinicDb);
  if (!db.prepare('SELECT count(*) AS n FROM practitioner').get().n) log('clinic_db_empty', { hint: 'npm run seed' });
  const server = createApp({ config, ...createDefaultDeps(config, log), log, db });
  server.listen(config.port, config.host, () => {
    log('listening', { host: config.host, port: config.port, ...describe(config) });
    log('doctor_web', { url: `http://${config.host}:${config.port}/doctor/` });
    if (config.mode === 'mock') log('mock_mode', { note: 'Mô phỏng AI: chưa gọi OpenAI, chưa nhận giọng.' });
  });
}
