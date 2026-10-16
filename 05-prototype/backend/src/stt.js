import OpenAI from 'openai';
import { OpenAIRealtimeWS } from 'openai/realtime/ws';

/**
 * Upstream live transcription. `connect()` returns a small handle the audio
 * relay drives; events are normalised to:
 *   { type: 'committed', itemId } | { type: 'delta', itemId, text }
 *   { type: 'final', itemId, text } | { type: 'failed', itemId, code }
 *   { type: 'error', code }
 *
 * `gpt-live-transcribe` does not support server/semantic VAD, so
 * turn_detection is null and the app commits each turn (PRD §5.3).
 */
export function createOpenAIStt(config, { log = () => {} } = {}) {
  const client = new OpenAI({ apiKey: config.apiKey, maxRetries: 0 });
  return {
    available: true,
    connect({ onEvent }) {
      const rt = new OpenAIRealtimeWS({ intent: 'transcription' }, client);
      let open = false;
      const ready = new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(Object.assign(new Error('timeout'), { code: 'timeout' })), 10_000);
        rt.socket.once('open', () => {
          clearTimeout(timer);
          open = true;
          rt.send({
            type: 'session.update',
            session: {
              type: 'transcription',
              audio: {
                input: {
                  format: { type: 'audio/pcm', rate: 24000 },
                  transcription: { model: config.sttModel, languages: ['vi'] },
                  turn_detection: null,
                },
              },
            },
          });
          resolve();
        });
        rt.socket.once('error', () => {
          clearTimeout(timer);
          reject(Object.assign(new Error('network'), { code: 'network' }));
        });
      });
      rt.on('input_audio_buffer.committed', (e) => onEvent({ type: 'committed', itemId: e.item_id }));
      rt.on('conversation.item.input_audio_transcription.delta', (e) =>
        onEvent({ type: 'delta', itemId: e.item_id, text: e.delta ?? '' }));
      rt.on('conversation.item.input_audio_transcription.completed', (e) =>
        onEvent({ type: 'final', itemId: e.item_id, text: e.transcript ?? '' }));
      rt.on('conversation.item.input_audio_transcription.failed', (e) =>
        onEvent({ type: 'failed', itemId: e.item_id, code: e.error?.code ?? 'stt_failed' }));
      rt.on('error', (error) => {
        const code = error.error?.code ?? error.error?.type ?? 'stt_error';
        log('stt_error', { code });
        onEvent({ type: 'error', code: /auth|api_key|unauthorized/i.test(code) ? 'config' : code });
      });
      rt.socket.on('close', () => {
        open = false;
        onEvent({ type: 'closed' });
      });
      return {
        ready,
        get bufferedAmount() {
          return rt.socket.bufferedAmount;
        },
        append(chunk) {
          if (open) rt.send({ type: 'input_audio_buffer.append', audio: chunk.toString('base64') });
        },
        commit() {
          if (open) rt.send({ type: 'input_audio_buffer.commit' });
        },
        clear() {
          if (open) rt.send({ type: 'input_audio_buffer.clear' });
        },
        close() {
          open = false;
          try {
            rt.close({ code: 1000, reason: 'done' });
          } catch {
            rt.socket.terminate();
          }
        },
      };
    },
  };
}

/** Mock mode: no speech recognition. The app is told so instead of faking it. */
export const unavailableStt = { available: false };
