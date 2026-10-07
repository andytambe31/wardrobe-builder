import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { presignUrl, presignPost, uriEncode } from '../src/presign.mjs';
import { createS3Media, photoKey } from '../src/media.mjs';

// AWS's published SigV4 example ("Authenticating Requests: Using Query
// Parameters", S3 API reference) — a GET for examplebucket/test.txt.
const AWS_EXAMPLE_CREDS = {
  accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
};

test('presignUrl matches the AWS SigV4 documentation vector', () => {
  const url = presignUrl({
    method: 'GET',
    bucket: 'examplebucket',
    key: 'test.txt',
    region: 'us-east-1',
    host: 'examplebucket.s3.amazonaws.com',
    credentials: AWS_EXAMPLE_CREDS,
    expiresIn: 86400,
    now: new Date('2013-05-24T00:00:00Z'),
  });
  assert.equal(url,
    'https://examplebucket.s3.amazonaws.com/test.txt'
    + '?X-Amz-Algorithm=AWS4-HMAC-SHA256'
    + '&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request'
    + '&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host'
    + '&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404');
});

test('presignUrl signs the session token and encodes the key per segment', () => {
  const url = new URL(presignUrl({
    bucket: 'b', key: 'users/abc/photos/a b', region: 'us-east-1',
    credentials: { ...AWS_EXAMPLE_CREDS, sessionToken: 'tok/en+=' },
  }));
  assert.equal(url.host, 'b.s3.us-east-1.amazonaws.com');
  assert.equal(url.pathname, '/users/abc/photos/a%20b');
  assert.equal(url.searchParams.get('X-Amz-Security-Token'), 'tok/en+=');
  assert.match(url.searchParams.get('X-Amz-Signature'), /^[0-9a-f]{64}$/);
});

test('uriEncode escapes the characters encodeURIComponent leaves alone', () => {
  assert.equal(uriEncode("a!'()*b"), 'a%21%27%28%29%2Ab');
});

test('presignPost pins key, content type and size range in a signed policy', () => {
  const now = new Date('2026-01-01T00:00:00Z');
  const { url, fields } = presignPost({
    bucket: 'media', key: 'users/s1/photos/p1', region: 'us-east-1',
    credentials: { ...AWS_EXAMPLE_CREDS, sessionToken: 'tok' },
    contentType: 'image/jpeg', maxBytes: 1000, expiresIn: 300, now,
  });
  assert.equal(url, 'https://media.s3.us-east-1.amazonaws.com/');
  assert.equal(fields.key, 'users/s1/photos/p1');
  assert.equal(fields['x-amz-security-token'], 'tok');

  const policy = JSON.parse(Buffer.from(fields.policy, 'base64').toString('utf8'));
  assert.equal(policy.expiration, '2026-01-01T00:05:00.000Z');
  assert.deepEqual(policy.conditions.slice(0, 4), [
    { bucket: 'media' },
    ['eq', '$key', 'users/s1/photos/p1'],
    ['eq', '$Content-Type', 'image/jpeg'],
    ['content-length-range', 1, 1000],
  ]);
  assert.ok(policy.conditions.some((c) => c['x-amz-security-token'] === 'tok'));

  // Signature = HMAC(SigV4 signing key, base64 policy).
  const h = (k, s) => crypto.createHmac('sha256', k).update(s).digest();
  const key = h(h(h(h(`AWS4${AWS_EXAMPLE_CREDS.secretAccessKey}`, '20260101'), 'us-east-1'), 's3'), 'aws4_request');
  assert.equal(fields['x-amz-signature'], h(key, fields.policy).toString('hex'));
});

test('createS3Media returns null without a bucket', () => {
  assert.equal(createS3Media({}), null);
});

test('media.remove sends a signed DELETE and accepts 204', async () => {
  const calls = [];
  const media = createS3Media({
    bucket: 'media', region: 'us-east-1', credentials: AWS_EXAMPLE_CREDS,
    fetchImpl: async (url, opts) => { calls.push({ url, opts }); return { status: 204 }; },
  });
  await media.remove(photoKey('s1', 'p1'));
  assert.equal(calls[0].opts.method, 'DELETE');
  assert.match(calls[0].url, /^https:\/\/media\.s3\.us-east-1\.amazonaws\.com\/users\/s1\/photos\/p1\?/);

  const failing = createS3Media({
    bucket: 'media', region: 'us-east-1', credentials: AWS_EXAMPLE_CREDS,
    fetchImpl: async () => ({ status: 403 }),
  });
  await assert.rejects(() => failing.remove('users/s1/photos/p1'));
});
