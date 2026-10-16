import assert from 'node:assert/strict';
import { test } from 'node:test';

import OpenAI from 'openai';

import { ExtractorError, emptyExtraction } from '../src/extraction.js';
import { createOpenAIExtractor } from '../src/extractors/openai.js';
import { PROFILES, TODAY, config } from './helpers.js';

const cfg = config();
const input = { utterances: ['khám mắt'], profiles: PROFILES, today: TODAY, state: {} };
const client = (impl) => ({ responses: { create: impl } });

test('sends the configured budget model with strict schema and store=false', async () => {
  let seen;
  const extract = createOpenAIExtractor(cfg, {
    client: client(async (req) => {
      seen = req;
      return { status: 'completed', output: [], output_text: JSON.stringify(emptyExtraction()) };
    }),
  });
  await extract(input);
  assert.equal(seen.model, 'gpt-6-luna');
  assert.deepEqual(seen.reasoning, { effort: 'low' });
  assert.equal(seen.store, false);
  assert.equal(seen.max_output_tokens, 1200);
  assert.equal(seen.text.format.strict, true);
  assert.ok(!seen.input.includes('Văn Hòa'), 'no patient names in the prompt');
});

test('incomplete and refused responses are errors, not proposals', async () => {
  const inc = createOpenAIExtractor(cfg, { client: client(async () => ({ status: 'incomplete', output: [] })) });
  await assert.rejects(inc(input), (e) => e instanceof ExtractorError && e.code === 'incomplete');
  const ref = createOpenAIExtractor(cfg, {
    client: client(async () => ({ status: 'completed', output: [{ content: [{ type: 'refusal' }] }] })),
  });
  await assert.rejects(ref(input), (e) => e.code === 'refusal');
});

test('auth errors are not retried; transient errors retry once', async () => {
  let calls = 0;
  const auth = createOpenAIExtractor(cfg, {
    client: client(async () => {
      calls++;
      throw new OpenAI.AuthenticationError(401, { message: 'bad key' }, 'bad key', new Headers());
    }),
  });
  await assert.rejects(auth(input), (e) => e.code === 'config');
  assert.equal(calls, 1);
  calls = 0;
  const flaky = createOpenAIExtractor(cfg, {
    client: client(async () => {
      calls++;
      if (calls === 1) throw new OpenAI.APIConnectionError({ message: 'reset' });
      return { status: 'completed', output: [], output_text: JSON.stringify(emptyExtraction()) };
    }),
  });
  await flaky(input);
  assert.equal(calls, 2);
});
