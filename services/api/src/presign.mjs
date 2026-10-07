// Zero-dependency S3 presigning (AWS Signature Version 4), so the API stays
// SDK-free. Two primitives:
//   presignUrl  — a query-string signed URL for GET/DELETE on one object.
//   presignPost — a browser upload form whose signed POST policy pins the exact
//                 key, Content-Type and a size range; S3 rejects anything else.
// Credentials come from the Lambda environment (role session creds include a
// session token, which is signed in as X-Amz-Security-Token).
import crypto from 'node:crypto';

const ALGORITHM = 'AWS4-HMAC-SHA256';

const sha256Hex = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');
const hmac = (key, s) => crypto.createHmac('sha256', key).update(s, 'utf8').digest();

// RFC 3986 encoding as SigV4 requires (encodeURIComponent leaves !'()* alone).
export function uriEncode(s) {
  return encodeURIComponent(s).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

const encodeKey = (key) => key.split('/').map(uriEncode).join('/');

// 2013-05-24T00:00:00.000Z -> { amzDate: 20130524T000000Z, dateStamp: 20130524 }
function stamps(now) {
  const amzDate = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  return { amzDate, dateStamp: amzDate.slice(0, 8) };
}

function signingKey(secret, dateStamp, region, service = 's3') {
  return hmac(hmac(hmac(hmac(`AWS4${secret}`, dateStamp), region), service), 'aws4_request');
}

export function bucketHost(bucket, region) {
  return `${bucket}.s3.${region}.amazonaws.com`;
}

export function presignUrl({ method = 'GET', bucket, key, region, credentials, expiresIn = 300, now = new Date(), host }) {
  const h = host || bucketHost(bucket, region);
  const { amzDate, dateStamp } = stamps(now);
  const scope = `${dateStamp}/${region}/s3/aws4_request`;

  const params = {
    'X-Amz-Algorithm': ALGORITHM,
    'X-Amz-Credential': `${credentials.accessKeyId}/${scope}`,
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': String(expiresIn),
    'X-Amz-SignedHeaders': 'host',
  };
  if (credentials.sessionToken) params['X-Amz-Security-Token'] = credentials.sessionToken;

  const query = Object.keys(params).sort()
    .map((k) => `${uriEncode(k)}=${uriEncode(params[k])}`)
    .join('&');
  const path = '/' + encodeKey(key);
  const canonicalRequest = [method, path, query, `host:${h}`, '', 'host', 'UNSIGNED-PAYLOAD'].join('\n');
  const stringToSign = [ALGORITHM, amzDate, scope, sha256Hex(canonicalRequest)].join('\n');
  const signature = hmac(signingKey(credentials.secretAccessKey, dateStamp, region), stringToSign).toString('hex');

  return `https://${h}${path}?${query}&X-Amz-Signature=${signature}`;
}

export function presignPost({ bucket, key, region, credentials, contentType, maxBytes, expiresIn = 300, now = new Date() }) {
  const { amzDate, dateStamp } = stamps(now);
  const credential = `${credentials.accessKeyId}/${dateStamp}/${region}/s3/aws4_request`;

  const fields = {
    key,
    'Content-Type': contentType,
    'x-amz-algorithm': ALGORITHM,
    'x-amz-credential': credential,
    'x-amz-date': amzDate,
  };
  if (credentials.sessionToken) fields['x-amz-security-token'] = credentials.sessionToken;

  const policy = {
    expiration: new Date(now.getTime() + expiresIn * 1000).toISOString(),
    conditions: [
      { bucket },
      ['eq', '$key', key],
      ['eq', '$Content-Type', contentType],
      ['content-length-range', 1, maxBytes],
      ...Object.entries(fields)
        .filter(([k]) => k.startsWith('x-amz-'))
        .map(([k, v]) => ({ [k]: v })),
    ],
  };
  const policyB64 = Buffer.from(JSON.stringify(policy), 'utf8').toString('base64');
  fields.policy = policyB64;
  fields['x-amz-signature'] = hmac(signingKey(credentials.secretAccessKey, dateStamp, region), policyB64).toString('hex');

  return { url: `https://${bucketHost(bucket, region)}/`, fields };
}
