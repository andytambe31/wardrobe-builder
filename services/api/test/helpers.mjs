// Test helpers — mint real RS256 JWTs with a locally generated key pair, and a
// matching in-memory JWKS fetcher, so auth can be tested without a network or a
// real Cognito pool.
import crypto from 'node:crypto';

const b64url = (buf) => Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64urlJson = (obj) => b64url(Buffer.from(JSON.stringify(obj), 'utf8'));

// One key pair for the whole suite. kid identifies it in the JWKS.
export const KID = 'test-key-1';
const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

export const jwk = { ...publicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256', use: 'sig' };

// A fetcher that returns our JWKS regardless of issuer.
export function jwksFetcher() {
  return async () => [jwk];
}

// Sign a JWT with our private key. Pass claim overrides; sensible defaults.
export function signToken(claims = {}, { kid = KID, alg = 'RS256' } = {}) {
  const nowSec = Math.floor(Date.now() / 1000);
  const payload = {
    iss: 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_TEST',
    sub: 'sub-123',
    token_use: 'access',
    client_id: 'client-abc',
    exp: nowSec + 3600,
    iat: nowSec,
    ...claims,
  };
  const header = { alg, kid, typ: 'JWT' };
  const signingInput = `${b64urlJson(header)}.${b64urlJson(payload)}`;
  if (alg === 'none') return `${signingInput}.`;
  const sig = crypto.sign('RSA-SHA256', Buffer.from(signingInput), privateKey);
  return `${signingInput}.${b64url(sig)}`;
}

export const ISSUER = 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_TEST';
export const CLIENT_ID = 'client-abc';

// Forge a token with a *different* key (valid structure, bad signature).
export function forgeToken(claims = {}) {
  const other = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
  const nowSec = Math.floor(Date.now() / 1000);
  const payload = { iss: ISSUER, sub: 'sub-123', token_use: 'access', client_id: CLIENT_ID, exp: nowSec + 3600, ...claims };
  const header = { alg: 'RS256', kid: KID, typ: 'JWT' };
  const signingInput = `${b64urlJson(header)}.${b64urlJson(payload)}`;
  const sig = crypto.sign('RSA-SHA256', Buffer.from(signingInput), other);
  return `${signingInput}.${b64url(sig)}`;
}

import { VersionConflict } from '../src/errors.mjs';

// A minimal in-memory data layer implementing the ddb.mjs contract, for app tests.
export function memoryData() {
  const store = new Map(); // `${sub}|${sk}` -> item
  const key = (sub, sk) => `${sub}|${sk}`;
  return {
    _store: store,
    async queryUser(sub) {
      return [...store.entries()].filter(([k]) => k.startsWith(`${sub}|`)).map(([, v]) => v);
    },
    async getItem(sub, sk) { return store.get(key(sub, sk)) || null; },
    async putItem(sub, sk, attrs, { expectedVersion } = {}) {
      const cur = store.get(key(sub, sk));
      if (typeof expectedVersion === 'number' && cur && cur.version !== expectedVersion) {
        throw new VersionConflict();
      }
      const nextVersion = (typeof expectedVersion === 'number' ? expectedVersion : (attrs.version || 0)) + 1;
      const item = { ...attrs, version: nextVersion, updatedAt: new Date().toISOString() };
      store.set(key(sub, sk), item);
      return item;
    },
    async deleteItem(sub, sk) { store.delete(key(sub, sk)); return true; },
    async bulkPut(sub, records) {
      const now = new Date().toISOString();
      for (const { sk, attrs } of records) {
        if (!sk || !attrs) continue;
        store.set(key(sub, sk), { ...attrs, version: 1, updatedAt: now });
      }
      return records.length;
    },
  };
}
