// Background jobs. The API enqueues { type, sub, input } onto SQS and returns at
// once; the worker Lambda (worker.mjs) runs the matching handler with a long
// timeout. Use this for anything that can outlive API Gateway's 30s limit —
// AI photo analysis, outfit generation, style reports.
//
// Each SQS record is processed independently. A handler that throws marks only
// that record as failed (ReportBatchItemFailures), so SQS retries it and, after
// the queue's max receive count, moves it to the dead-letter queue.
import crypto from 'node:crypto';

// Enqueue side. `send` is injected (SQS in prod, an array in tests).
export function createJobQueue({ queueUrl, send }) {
  if (!queueUrl) return null; // queue not configured
  return {
    async enqueue(type, sub, input = {}) {
      const job = { id: crypto.randomUUID(), type, sub, input, enqueuedAt: new Date().toISOString() };
      await send({ QueueUrl: queueUrl, MessageBody: JSON.stringify(job) });
      return job;
    },
  };
}

// Consume side. handlers: { [type]: async (job, deps) => result }.
export function createWorker({ handlers, deps = {}, log = console }) {
  return async function handler(event) {
    const batchItemFailures = [];
    for (const record of event?.Records || []) {
      try {
        const job = JSON.parse(record.body);
        const run = handlers[job.type];
        if (!run) throw new Error(`unknown job type: ${job.type}`);
        if (!job.sub) throw new Error('job has no owner sub');
        await run(job, deps);
        log.info(JSON.stringify({ msg: 'job done', id: job.id, type: job.type }));
      } catch (err) {
        log.error(JSON.stringify({ msg: 'job failed', messageId: record.messageId, error: String(err && err.message || err) }));
        batchItemFailures.push({ itemIdentifier: record.messageId });
      }
    }
    return { batchItemFailures };
  };
}
