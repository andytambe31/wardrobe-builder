// Production wiring for the AWS-backed dependencies both entrypoints share.
// The @aws-sdk/* clients are provided by the nodejs20.x Lambda runtime.
import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';
import { SSMClient, GetParameterCommand } from '@aws-sdk/client-ssm';
import { createDynamoData } from './ddb.mjs';
import { createS3Media } from './media.mjs';
import { createJobQueue } from './jobs.mjs';
import { createSecrets } from './secrets.mjs';

export function createAwsDeps(env = process.env) {
  const region = env.AWS_REGION || env.AWS_DEFAULT_REGION;
  const sqs = new SQSClient({});
  const ssm = new SSMClient({});
  return {
    data: createDynamoData({ tableName: env.TABLE_NAME }),
    // null when MEDIA_BUCKET is unset — the photo routes answer 501.
    media: createS3Media({
      bucket: env.MEDIA_BUCKET,
      region,
      maxBytes: Number(env.MEDIA_MAX_BYTES) || undefined,
    }),
    jobs: createJobQueue({
      queueUrl: env.JOBS_QUEUE_URL,
      send: (input) => sqs.send(new SendMessageCommand(input)),
    }),
    secrets: createSecrets({
      fetchParam: async (name) => {
        const res = await ssm.send(new GetParameterCommand({ Name: name, WithDecryption: true }));
        return res.Parameter && res.Parameter.Value;
      },
    }),
    aiApiKeyParam: env.AI_API_KEY_PARAM || '',
  };
}
