import { handleUtterance } from './orchestrator.js';

const BYTES_PER_SECOND = 48_000; // PCM16 mono 24 kHz
const MAX_UPSTREAM_BUFFER = 1024 * 1024;

const STT_MESSAGES = {
  stt_unavailable: 'Chế độ Mô phỏng AI chưa nhận giọng nói. Bạn có thể nhập tay hoặc chọn nhanh.',
  config: 'Dịch vụ nhận giọng chưa được cấu hình đúng. Bạn có thể nhập tay hoặc chọn nhanh.',
  network: 'Mất kết nối dịch vụ nhận giọng. Phần chưa xử lý cần nói hoặc nhập lại.',
  timeout: 'Dịch vụ nhận giọng không phản hồi. Vui lòng thử lại hoặc nhập tay.',
  network_slow: 'Mạng chậm nên micro đã dừng. Phần chưa xử lý cần nói hoặc nhập lại.',
  busy: 'Micro đang được dùng ở một kết nối khác của phiên này.',
};

/**
 * Bridges one app WebSocket to one upstream transcription session.
 * App → server: binary PCM16 frames and JSON {type: audio.start | turn.commit
 * | turn.cancel | audio.stop}. Server → app: session.ready, transcript.delta,
 * transcript.final, turn.result, turn.empty, limit.warning, audio.stopped,
 * session.error. Audio is held only in flight and never written to disk.
 */
export function attachAudio(ws, session, { config, stt, extractor, log }) {
  const send = (event) => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(event));
  };
  const fail = (code, { close = false } = {}) => {
    send({ type: 'session.error', code, message: STT_MESSAGES[code] ?? STT_MESSAGES.network });
    if (close) stop('error');
  };

  if (!stt.available) {
    fail('stt_unavailable');
    ws.close(1000, 'stt_unavailable');
    return;
  }
  if (session.audio) {
    fail('busy');
    ws.close(1000, 'busy');
    return;
  }
  session.audio = ws;
  session.audioBytes ??= 0;
  const sessionLimit = config.maxSessionAudioSeconds * BYTES_PER_SECOND;

  let upstream = null;
  let ready = false;
  let warned = false;
  let turnSeq = 0;
  let open = null; // { id, bytes, itemId, text }
  const turns = []; // committed turns waiting for a final transcript

  const newTurn = () => (open = { id: `a${++turnSeq}`, bytes: 0, itemId: null, text: '' });
  const turnFor = (itemId) => {
    let turn = turns.find((t) => t.itemId === itemId) ?? (open?.itemId === itemId ? open : null);
    if (!turn) {
      turn = turns.find((t) => !t.itemId) ?? (open && !open.itemId ? open : null);
      if (turn) turn.itemId = itemId;
    }
    return turn;
  };

  function stop(reason) {
    if (open?.bytes) commit();
    send({ type: 'audio.stopped', reason });
    open = null;
    ready = false;
    if (!turns.length) closeUpstream();
  }
  function closeUpstream() {
    upstream?.close();
    upstream = null;
  }
  function commit() {
    if (!open || !open.bytes) return;
    upstream?.commit();
    turns.push(open);
    newTurn();
  }

  async function onUpstream(event) {
    if (event.type === 'committed') {
      const turn = turns.find((t) => !t.itemId);
      if (turn) turn.itemId = event.itemId;
    } else if (event.type === 'delta') {
      const turn = turnFor(event.itemId);
      if (!turn) return;
      turn.text += event.text;
      send({ type: 'transcript.delta', turn_id: turn.id, text: turn.text });
    } else if (event.type === 'final' || event.type === 'failed') {
      const turn = turnFor(event.itemId);
      if (!turn) return;
      turns.splice(turns.indexOf(turn), 1);
      if (!ready && !turns.length) closeUpstream();
      const text = event.type === 'final' ? event.text.trim() : '';
      if (!text) {
        send({ type: 'turn.empty', turn_id: turn.id, code: event.type === 'failed' ? event.code : 'no_speech' });
        return;
      }
      send({ type: 'transcript.final', turn_id: turn.id, text });
      const result = await handleUtterance(session, text, {
        extractor,
        mode: config.mode,
        limit: config.modelCallsPerMinute,
        turnId: turn.id,
        log,
      });
      send({ type: 'turn.result', ...result });
    } else if (event.type === 'error') {
      fail(event.code === 'config' ? 'config' : 'network', { close: true });
    } else if (event.type === 'closed' && upstream) {
      upstream = null;
      if (ready || turns.length) {
        turns.length = 0;
        fail('network', { close: true });
      }
    }
  }

  async function start() {
    if (session.audioBytes >= sessionLimit) {
      send({ type: 'audio.stopped', reason: 'session_limit' });
      return;
    }
    if (!upstream) {
      upstream = stt.connect({ onEvent: (e) => void onUpstream(e) });
      try {
        await upstream.ready;
      } catch (error) {
        closeUpstream();
        fail(error.code === 'timeout' ? 'timeout' : 'network');
        return;
      }
    }
    ready = true;
    newTurn();
    send({ type: 'session.ready', turn_id: open.id });
  }

  ws.on('message', (data, isBinary) => {
    if (isBinary) {
      if (!ready || !open || !upstream) return;
      const chunk = Buffer.isBuffer(data) ? data : Buffer.concat(data);
      if (upstream.bufferedAmount > MAX_UPSTREAM_BUFFER) {
        fail('network_slow');
        stop('network_slow');
        return;
      }
      if (open.bytes + chunk.length > config.maxTurnAudioBytes) {
        commit();
        send({ type: 'limit.warning', reason: 'turn_limit' });
      }
      if (session.audioBytes + chunk.length > sessionLimit) {
        stop('session_limit');
        return;
      }
      upstream.append(chunk);
      open.bytes += chunk.length;
      session.audioBytes += chunk.length;
      const remaining = (sessionLimit - session.audioBytes) / BYTES_PER_SECOND;
      if (!warned && remaining <= 15) {
        warned = true;
        send({ type: 'limit.warning', reason: 'session_ending', remaining_seconds: Math.ceil(remaining) });
      }
      return;
    }
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (message.type === 'audio.start') void start();
    else if (message.type === 'turn.commit') commit();
    else if (message.type === 'turn.cancel') {
      upstream?.clear();
      if (open) open.bytes = 0;
    } else if (message.type === 'audio.stop') stop('user');
  });

  ws.on('close', () => {
    if (session.audio === ws) session.audio = null;
    turns.length = 0;
    open = null;
    ready = false;
    closeUpstream();
  });
}
