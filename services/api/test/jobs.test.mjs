import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createJobQueue, createWorker } from '../src/jobs.mjs';
import { createSecrets } from '../src/secrets.mjs';

const quiet = { info() {}, error() {} };

test('createJobQueue returns null without a queue URL', () => {
  assert.equal(createJobQueue({ send: async () => {} }), null);
});

test('enqueue sends a job envelope with id, type, owner and input', async () => {
  const sent = [];
  const q = createJobQueue({ queueUrl: 'https://sqs/q', send: async (m) => sent.push(m) });
  const job = await q.enqueue('analyze-photo', 'sub-1', { photoId: 'p1' });
  assert.equal(sent[0].QueueUrl, 'https://sqs/q');
  const body = JSON.parse(sent[0].MessageBody);
  assert.equal(body.id, job.id);
  assert.equal(body.type, 'analyze-photo');
  assert.equal(body.sub, 'sub-1');
  assert.deepEqual(body.input, { photoId: 'p1' });
});

const record = (messageId, job) => ({ messageId, body: JSON.stringify(job) });

test('worker runs the matching handler with deps', async () => {
  const seen = [];
  const handler = createWorker({
    handlers: { ping: async (job, deps) => seen.push([job.id, deps.tag]) },
    deps: { tag: 'd' },
    log: quiet,
  });
  const res = await handler({ Records: [record('m1', { id: 'j1', type: 'ping', sub: 's' })] });
  assert.deepEqual(res, { batchItemFailures: [] });
  assert.deepEqual(seen, [['j1', 'd']]);
});

test('worker reports only the failed records so SQS retries just those', async () => {
  const handler = createWorker({
    handlers: {
      ok: async () => {},
      boom: async () => { throw new Error('model timeout'); },
    },
    log: quiet,
  });
  const res = await handler({ Records: [
    record('m1', { type: 'ok', sub: 's' }),
    record('m2', { type: 'boom', sub: 's' }),
    record('m3', { type: 'nope', sub: 's' }),
    record('m4', { type: 'ok' }), // no owner
    { messageId: 'm5', body: '{not json' },
  ] });
  assert.deepEqual(res.batchItemFailures.map((f) => f.itemIdentifier), ['m2', 'm3', 'm4', 'm5']);
});

test('secrets are fetched once and cached', async () => {
  let calls = 0;
  const secrets = createSecrets({ fetchParam: async () => { calls++; return 'sk-123'; } });
  assert.equal(await secrets.get('/p/k'), 'sk-123');
  assert.equal(await secrets.get('/p/k'), 'sk-123');
  assert.equal(calls, 1);
});

test('secrets refetch after the TTL', async () => {
  let t = 0; let calls = 0;
  const secrets = createSecrets({ fetchParam: async () => `v${++calls}`, ttlMs: 10, now: () => t });
  assert.equal(await secrets.get('k'), 'v1');
  t = 11;
  assert.equal(await secrets.get('k'), 'v2');
});

test('an unset or placeholder secret is an error, not a silent empty key', async () => {
  await assert.rejects(createSecrets({ fetchParam: async () => undefined }).get('k'), /not set/);
  await assert.rejects(createSecrets({ fetchParam: async () => 'REPLACE_ME' }).get('k'), /not set/);
  await assert.rejects(createSecrets({ fetchParam: async () => 'x' }).get(''), /not configured/);
});
