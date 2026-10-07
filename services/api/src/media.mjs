// S3-backed media store for user photos. Mirrors the ddb.mjs pattern: the API
// gets an injected object, tests swap in a fake. Keys are always built from the
// caller's sub, so a user can only ever sign for their own prefix.
import { presignUrl, presignPost } from './presign.mjs';

export const photoKey = (sub, id) => `users/${sub}/photos/${id}`;

export function createS3Media({ bucket, region, credentials, maxBytes = 10 * 1024 * 1024, expiresIn = 300, fetchImpl = fetch } = {}) {
  if (!bucket) return null; // media not configured — handlers answer 501
  const creds = () => credentials || {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    sessionToken: process.env.AWS_SESSION_TOKEN,
  };

  return {
    maxBytes,
    expiresIn,

    uploadForm(key, contentType) {
      return presignPost({ bucket, key, region, credentials: creds(), contentType, maxBytes, expiresIn });
    },

    downloadUrl(key) {
      return presignUrl({ method: 'GET', bucket, key, region, credentials: creds(), expiresIn });
    },

    // The Lambda signs and sends its own DELETE — same signer, no SDK.
    async remove(key) {
      const url = presignUrl({ method: 'DELETE', bucket, key, region, credentials: creds(), expiresIn: 60 });
      const res = await fetchImpl(url, { method: 'DELETE' });
      if (res.status !== 204 && res.status !== 200) throw new Error(`s3 delete failed: ${res.status}`);
      return true;
    },
  };
}
