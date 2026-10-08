// Worker entrypoint (nodejs20.x Lambda, triggered by the jobs SQS queue). Shares
// the source package with the API (index.mjs). Register job types in `handlers`;
// each gets the job ({ id, type, sub, input }) and the shared AWS deps. Always
// scope reads/writes to job.sub — the API set it from the verified token.
import { createWorker } from './src/jobs.mjs';
import { createAwsDeps } from './src/aws.mjs';

const handlers = {
  // Pipeline check: enqueue { type: 'ping' } to confirm queue -> worker works.
  async ping(job) {
    return { pong: true, id: job.id };
  },
};

export const handler = createWorker({ handlers, deps: createAwsDeps() });
