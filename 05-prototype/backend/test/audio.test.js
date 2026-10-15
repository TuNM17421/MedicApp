import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import WebSocket from 'ws';

import { createApp } from '../src/server.js';
import { PROFILES, TODAY, config, mockExtractor, silentLog } from './helpers.js';

/** Fake upstream: every commit yields one committed + delta + final event. */
function fakeStt(script) {
  const state = { appended: 0, commits: 0, closed: 0 };
  return {
    state,
    available: true,
    connect({ onEvent }) {
      let item = 0;
      return {
        ready: Promise.resolve(),
        bufferedAmount: 0,
        append(chunk) { state.appended += chunk.length; },
        commit() {
          const id = `item_${++item}`;
          const text = script.shift() ?? '';
          state.commits++;
          setTimeout(() => {
            onEvent({ type: 'committed', itemId: id });
            onEvent({ type: 'delta', itemId: id, text: text.slice(0, 5) });
            onEvent({ type: 'final', itemId: id, text });
          }, 5);
        },
        clear() {},
        close() { state.closed++; },
      };
    },
  };
}

let server;
let base;
let stt;
before(async () => {
  stt = fakeStt(['Tôi muốn khám dịch vụ cho tôi, đau mắt', 'ở An Bình sớm nhất']);
  server = createApp({ config: config({ MAX_SESSION_AUDIO_SECONDS: '2' }), extractor: mockExtractor, stt, log: silentLog });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => new Promise((r) => server.close(r)));

async function open() {
  const res = await fetch(`${base}/v1/smart/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ today: TODAY, profiles: PROFILES }),
  });
  const { session_id: id, token } = await res.json();
  const ws = new WebSocket(`${base.replace('http', 'ws')}/v1/smart/sessions/${id}/audio?token=${token}`);
  const events = [];
  const waiters = [];
  ws.on('message', (d) => {
    const e = JSON.parse(d.toString());
    events.push(e);
    for (const w of [...waiters]) if (w.match(e)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(e); }
  });
  await new Promise((r) => ws.once('open', r));
  const until = (match) => {
    const hit = events.find(match);
    return hit ? Promise.resolve(hit) : new Promise((resolve) => waiters.push({ match, resolve }));
  };
  return { ws, events, until };
}

test('streams deltas, finals and auto-processes each committed turn (AC01)', async () => {
  const { ws, until } = await open();
  ws.send(JSON.stringify({ type: 'audio.start' }));
  await until((e) => e.type === 'session.ready');
  ws.send(Buffer.alloc(4800));
  ws.send(JSON.stringify({ type: 'turn.commit' }));
  const first = await until((e) => e.type === 'turn.result');
  assert.equal(first.status, 'ask');
  assert.equal(first.fields.department_id, 'eyes');
  ws.send(Buffer.alloc(4800));
  ws.send(JSON.stringify({ type: 'turn.commit' }));
  const final = await until((e) => e.type === 'transcript.final' && e.turn_id === 'a2');
  assert.equal(final.text, 'ở An Bình sớm nhất');
  const second = await until((e) => e.type === 'turn.result' && e.turn_id === 'a2');
  assert.equal(second.status, 'ready');
  ws.send(JSON.stringify({ type: 'audio.stop' }));
  await until((e) => e.type === 'audio.stopped');
  ws.close();
});

test('session audio limit stops capture and closes upstream (AC12)', async () => {
  const { ws, until } = await open();
  ws.send(JSON.stringify({ type: 'audio.start' }));
  await until((e) => e.type === 'session.ready');
  for (let i = 0; i < 3; i++) ws.send(Buffer.alloc(48_000));
  const stopped = await until((e) => e.type === 'audio.stopped');
  assert.equal(stopped.reason, 'session_limit');
  ws.close();
  await new Promise((r) => setTimeout(r, 30));
  assert.ok(stt.state.closed >= 1);
});

test('only one microphone connection per session', async () => {
  const res = await fetch(`${base}/v1/smart/sessions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ today: TODAY, profiles: PROFILES }),
  });
  const { session_id: id, token } = await res.json();
  const url = `${base.replace('http', 'ws')}/v1/smart/sessions/${id}/audio?token=${token}`;
  const a = new WebSocket(url);
  await new Promise((r) => a.once('open', r));
  const b = new WebSocket(url);
  const msg = await new Promise((r) => b.once('message', (d) => r(JSON.parse(d.toString()))));
  assert.equal(msg.code, 'busy');
  a.close();
});
