import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyJwt, bearerToken, AuthError } from '../src/auth.mjs';
import { signToken, forgeToken, jwksFetcher, ISSUER, CLIENT_ID } from './helpers.mjs';

const opts = () => ({ issuer: ISSUER, clientIds: [CLIENT_ID], jwksFetcher: jwksFetcher() });

test('accepts a valid access token', async () => {
  const payload = await verifyJwt(signToken(), opts());
  assert.equal(payload.sub, 'sub-123');
  assert.equal(payload.token_use, 'access');
});

test('accepts a valid id token (aud instead of client_id)', async () => {
  const token = signToken({ token_use: 'id', aud: CLIENT_ID, client_id: undefined });
  const payload = await verifyJwt(token, opts());
  assert.equal(payload.token_use, 'id');
});

test('rejects an expired token', async () => {
  const token = signToken({ exp: Math.floor(Date.now() / 1000) - 3600 });
  await assert.rejects(verifyJwt(token, opts()), (e) => e instanceof AuthError && e.code === 'token_expired');
});

test('rejects a wrong issuer', async () => {
  const token = signToken({ iss: 'https://evil.example.com/pool' });
  await assert.rejects(verifyJwt(token, opts()), (e) => e.code === 'bad_issuer');
});

test('rejects a wrong audience', async () => {
  const token = signToken({ client_id: 'some-other-client' });
  await assert.rejects(verifyJwt(token, opts()), (e) => e.code === 'bad_audience');
});

test('rejects a forged signature (different key)', async () => {
  await assert.rejects(verifyJwt(forgeToken(), opts()), (e) => e.code === 'bad_signature');
});

test('rejects a tampered payload', async () => {
  const parts = signToken().split('.');
  const tampered = Buffer.from(JSON.stringify({ sub: 'attacker', iss: ISSUER, client_id: CLIENT_ID, exp: 9999999999 }))
    .toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  await assert.rejects(verifyJwt(`${parts[0]}.${tampered}.${parts[2]}`, opts()), (e) => e.code === 'bad_signature');
});

test('rejects alg=none', async () => {
  const token = signToken({}, { alg: 'none' });
  await assert.rejects(verifyJwt(token, opts()), (e) => e.code === 'bad_alg');
});

test('rejects a missing/malformed token', async () => {
  await assert.rejects(verifyJwt(undefined, opts()), (e) => e.code === 'missing_token');
  await assert.rejects(verifyJwt('a.b', opts()), (e) => e.code === 'malformed_token');
});

test('rejects an unknown kid after a rotation refetch', async () => {
  const token = signToken({}, { kid: 'nonexistent-kid' });
  await assert.rejects(verifyJwt(token, opts()), (e) => e.code === 'unknown_key');
});

test('bearerToken parses case-insensitively', () => {
  assert.equal(bearerToken({ Authorization: 'Bearer abc.def.ghi' }), 'abc.def.ghi');
  assert.equal(bearerToken({ authorization: 'bearer xyz' }), 'xyz');
  assert.equal(bearerToken({}), null);
});
