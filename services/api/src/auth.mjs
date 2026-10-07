// Cryptographic JWT verification against a Cognito user pool — done IN THE APP
// (defense in depth), not just at the API Gateway authorizer. Zero dependencies:
// Node 20's built-in crypto verifies RS256 with a JWK-imported public key, and
// global fetch pulls the pool's JWKS.
//
// This means the endpoints stay gated even against a direct Lambda invoke or an
// authorizer misconfiguration — the token must be genuine, unexpired, from the
// right issuer, and for the right client, or the request is rejected.
import crypto from 'node:crypto';

export class AuthError extends Error {
  constructor(code, message) {
    super(message || code);
    this.name = 'AuthError';
    this.code = code; // machine-readable, e.g. 'token_expired'
  }
}

const b64urlToBuf = (s) => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
const decodeSegment = (s) => {
  try { return JSON.parse(b64urlToBuf(s).toString('utf8')); }
  catch { throw new AuthError('malformed_token', 'token segment is not valid JSON'); }
};

// ---- JWKS cache (per issuer). Refreshable on an unknown kid (key rotation). ----
const _jwksCache = new Map(); // issuer -> { keys, fetchedAt }
const JWKS_TTL_MS = 60 * 60 * 1000;

async function defaultJwksFetcher(issuer) {
  const url = `${issuer.replace(/\/$/, '')}/.well-known/jwks.json`;
  const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
  if (!res.ok) throw new AuthError('jwks_unavailable', `JWKS fetch failed: ${res.status}`);
  const body = await res.json();
  if (!body || !Array.isArray(body.keys)) throw new AuthError('jwks_invalid', 'JWKS has no keys');
  return body.keys;
}

async function getJwk(issuer, kid, fetcher, forceRefresh = false) {
  const cached = _jwksCache.get(issuer);
  const fresh = cached && Date.now() - cached.fetchedAt < JWKS_TTL_MS;
  let keys = fresh && !forceRefresh ? cached.keys : null;
  if (!keys) {
    keys = await fetcher(issuer);
    _jwksCache.set(issuer, { keys, fetchedAt: Date.now() });
  }
  const jwk = keys.find((k) => k.kid === kid);
  if (!jwk && !forceRefresh) return getJwk(issuer, kid, fetcher, true); // rotation: refetch once
  return jwk || null;
}

// Verify a compact JWS and validate the standard claims.
// opts: { issuer, clientIds:[...], now?, clockToleranceSec?, jwksFetcher?, allowedTokenUse? }
export async function verifyJwt(token, opts) {
  if (!token || typeof token !== 'string') throw new AuthError('missing_token', 'no bearer token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new AuthError('malformed_token', 'expected 3 JWT segments');
  const [h, p, s] = parts;

  const header = decodeSegment(h);
  if (header.alg !== 'RS256') throw new AuthError('bad_alg', `unsupported alg ${header.alg}`);
  if (!header.kid) throw new AuthError('bad_alg', 'missing kid');

  const issuer = opts.issuer.replace(/\/$/, '');
  const fetcher = opts.jwksFetcher || defaultJwksFetcher;
  const jwk = await getJwk(issuer, header.kid, fetcher);
  if (!jwk) throw new AuthError('unknown_key', 'no matching signing key');

  // RS256 = RSASSA-PKCS1-v1_5 with SHA-256.
  const pub = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const ok = crypto.verify('RSA-SHA256', Buffer.from(`${h}.${p}`), pub, b64urlToBuf(s));
  if (!ok) throw new AuthError('bad_signature', 'signature verification failed');

  const payload = decodeSegment(p);
  if (payload.iss !== issuer) throw new AuthError('bad_issuer', 'unexpected issuer');

  const nowSec = Math.floor((opts.now ?? Date.now()) / 1000);
  const tol = opts.clockToleranceSec ?? 60;
  if (typeof payload.exp === 'number' && nowSec > payload.exp + tol) throw new AuthError('token_expired', 'token expired');
  if (typeof payload.nbf === 'number' && nowSec < payload.nbf - tol) throw new AuthError('token_not_yet_valid', 'token not yet valid');

  const allowedUse = opts.allowedTokenUse || ['access', 'id'];
  if (payload.token_use && !allowedUse.includes(payload.token_use)) throw new AuthError('bad_token_use', `token_use ${payload.token_use} not allowed`);

  // Cognito ID tokens carry `aud`; access tokens carry `client_id`. Accept either.
  if (opts.clientIds && opts.clientIds.length) {
    const aud = payload.aud || payload.client_id;
    const audOk = Array.isArray(aud) ? aud.some((a) => opts.clientIds.includes(a)) : opts.clientIds.includes(aud);
    if (!audOk) throw new AuthError('bad_audience', 'token not for this client');
  }

  if (!payload.sub) throw new AuthError('no_subject', 'token has no subject');
  return payload;
}

// Pull the bearer token from the (case-insensitive) Authorization header.
export function bearerToken(headers = {}) {
  const h = headers.authorization || headers.Authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m ? m[1].trim() : null;
}
