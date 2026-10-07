import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.mjs';
import { verifyJwt } from '../src/auth.mjs';
import { signToken, jwksFetcher, memoryData, ISSUER, CLIENT_ID } from './helpers.mjs';

const SUB = 'sub-123';

function buildApp({ allowedSubs = SUB, requireAllowlist = true, corsOrigins = ['https://wardrobe-builder.example'], media = fakeMedia() } = {}) {
  const data = memoryData();
  const verify = (token) => verifyJwt(token, { issuer: ISSUER, clientIds: [CLIENT_ID], jwksFetcher: jwksFetcher() });
  const app = createApp({ verify, data, media, config: { env: 'test', allowedSubs, requireAllowlist, corsOrigins } });
  return { app, data, media };
}

// Records which keys the API asks the media store to sign or delete.
function fakeMedia() {
  const removed = [];
  return {
    maxBytes: 1000,
    expiresIn: 300,
    removed,
    uploadForm: (key, contentType) => ({ url: 'https://media.example/', fields: { key, 'Content-Type': contentType } }),
    downloadUrl: (key) => `https://media.example/${key}?signed`,
    remove: async (key) => { removed.push(key); return true; },
  };
}

function req(method, path, { token, body, headers = {}, origin } = {}) {
  const h = { ...headers };
  if (token) h.authorization = `Bearer ${token}`;
  if (origin) h.origin = origin;
  return {
    rawPath: path,
    requestContext: { http: { method } },
    headers: h,
    body: body === undefined ? undefined : JSON.stringify(body),
  };
}

test('health is public — no token needed', async () => {
  const { app } = buildApp();
  const res = await app(req('GET', '/health'));
  assert.equal(res.statusCode, 200);
  assert.equal(JSON.parse(res.body).ok, true);
});

test('guarded route rejects with no token', async () => {
  const { app } = buildApp();
  const res = await app(req('GET', '/state'));
  assert.equal(res.statusCode, 401);
});

test('guarded route accepts a valid allow-listed token', async () => {
  const { app } = buildApp();
  const res = await app(req('GET', '/state', { token: signToken({ sub: SUB }) }));
  assert.equal(res.statusCode, 200);
  assert.deepEqual(JSON.parse(res.body), { items: [] });
});

test('valid token but NOT on the allow-list gets 403', async () => {
  const { app } = buildApp({ allowedSubs: 'someone-else' });
  const res = await app(req('GET', '/state', { token: signToken({ sub: SUB }) }));
  assert.equal(res.statusCode, 403);
});

test('/me echoes the principal', async () => {
  const { app } = buildApp();
  const res = await app(req('GET', '/me', { token: signToken({ sub: SUB, email: 'me@x.com' }) }));
  const body = JSON.parse(res.body);
  assert.equal(body.sub, SUB);
  assert.equal(body.email, 'me@x.com');
});

test('PUT then GET settings round-trips, version increments', async () => {
  const { app } = buildApp();
  const t = signToken({ sub: SUB });
  const put = await app(req('PUT', '/settings', { token: t, body: { theme: 'dark' } }));
  assert.equal(put.statusCode, 200);
  const saved = JSON.parse(put.body);
  assert.equal(saved.version, 1);
  assert.equal(saved.theme, 'dark');
  assert.equal(put.headers.etag, '"1"');

  const get = await app(req('GET', '/settings', { token: t }));
  assert.equal(JSON.parse(get.body).theme, 'dark');
});

test('If-Match enforces optimistic concurrency', async () => {
  const { app } = buildApp();
  const t = signToken({ sub: SUB });
  await app(req('PUT', '/settings', { token: t, body: { a: 1 } })); // version -> 1
  // Stale write with wrong expected version.
  const stale = await app(req('PUT', '/settings', { token: t, body: { a: 2 }, headers: { 'if-match': '0' } }));
  assert.equal(stale.statusCode, 409);
  // Correct expected version succeeds.
  const ok = await app(req('PUT', '/settings', { token: t, body: { a: 3 }, headers: { 'if-match': '1' } }));
  assert.equal(ok.statusCode, 200);
  assert.equal(JSON.parse(ok.body).version, 2);
});

test('items are owner-scoped — two users never collide', async () => {
  const { app } = buildApp({ allowedSubs: `${SUB},sub-two` });
  const t1 = signToken({ sub: SUB });
  const t2 = signToken({ sub: 'sub-two' });
  await app(req('PUT', '/items/x', { token: t1, body: { note: 'mine' } }));
  await app(req('PUT', '/items/x', { token: t2, body: { note: 'theirs' } }));
  const s1 = JSON.parse((await app(req('GET', '/state', { token: t1 }))).body);
  const s2 = JSON.parse((await app(req('GET', '/state', { token: t2 }))).body);
  assert.equal(s1.items.length, 1);
  assert.equal(s1.items[0].note, 'mine');
  assert.equal(s2.items[0].note, 'theirs');
});

test('DELETE /items/:id removes it', async () => {
  const { app } = buildApp();
  const t = signToken({ sub: SUB });
  await app(req('PUT', '/items/z', { token: t, body: { n: 1 } }));
  const del = await app(req('DELETE', '/items/z', { token: t }));
  assert.equal(del.statusCode, 200);
  const state = JSON.parse((await app(req('GET', '/state', { token: t }))).body);
  assert.equal(state.items.length, 0);
});

test('client cannot spoof version/keys via the body', async () => {
  const { app } = buildApp();
  const t = signToken({ sub: SUB });
  const res = await app(req('PUT', '/items/spoof', {
    token: t,
    body: { version: 999, PK: 'USER#attacker', SK: 'ITEM#other', note: 'x' },
  }));
  const saved = JSON.parse(res.body);
  assert.equal(saved.version, 1); // server-assigned, not 1000
  assert.equal(saved.PK, undefined);
});

test('OPTIONS preflight returns 204 with CORS headers', async () => {
  const { app } = buildApp();
  const res = await app(req('OPTIONS', '/state', { origin: 'https://wardrobe-builder.example' }));
  assert.equal(res.statusCode, 204);
  assert.equal(res.headers['access-control-allow-origin'], 'https://wardrobe-builder.example');
});

test('unknown route is 404', async () => {
  const { app } = buildApp();
  const res = await app(req('GET', '/nope', { token: signToken({ sub: SUB }) }));
  assert.equal(res.statusCode, 404);
});

test('malformed JSON body is 400', async () => {
  const { app } = buildApp();
  const res = await app({
    rawPath: '/settings',
    requestContext: { http: { method: 'PUT' } },
    headers: { authorization: `Bearer ${signToken({ sub: SUB })}` },
    body: '{not json',
  });
  assert.equal(res.statusCode, 400);
});

test('POST /photos signs an upload under the caller\'s own prefix', async () => {
  const { app } = buildApp();
  const res = await app(req('POST', '/photos', { token: signToken({ sub: SUB }), body: { contentType: 'image/jpeg' } }));
  assert.equal(res.statusCode, 201);
  const body = JSON.parse(res.body);
  assert.match(body.id, /^[0-9a-f-]{36}$/);
  assert.equal(body.upload.fields.key, `users/${SUB}/photos/${body.id}`);
  assert.equal(body.upload.fields['Content-Type'], 'image/jpeg');
  assert.equal(body.maxBytes, 1000);
});

test('POST /photos rejects non-image content types', async () => {
  const { app } = buildApp();
  const res = await app(req('POST', '/photos', { token: signToken({ sub: SUB }), body: { contentType: 'text/html' } }));
  assert.equal(res.statusCode, 400);
});

test('photo routes are gated', async () => {
  const { app } = buildApp();
  const res = await app(req('POST', '/photos', { body: { contentType: 'image/jpeg' } }));
  assert.equal(res.statusCode, 401);
});

test('GET /photos/:id signs a download for the caller\'s key only', async () => {
  const { app } = buildApp();
  const res = await app(req('GET', '/photos/abc', { token: signToken({ sub: SUB }) }));
  assert.equal(res.statusCode, 200);
  assert.equal(JSON.parse(res.body).url, `https://media.example/users/${SUB}/photos/abc?signed`);
});

test('photo ids cannot escape the user prefix', async () => {
  const { app } = buildApp();
  const res = await app(req('GET', '/photos/..%2F..%2Fother', { token: signToken({ sub: SUB }) }));
  assert.equal(res.statusCode, 400);
});

test('DELETE /photos/:id removes the caller\'s object', async () => {
  const { app, media } = buildApp();
  const res = await app(req('DELETE', '/photos/abc', { token: signToken({ sub: SUB }) }));
  assert.equal(res.statusCode, 200);
  assert.deepEqual(media.removed, [`users/${SUB}/photos/abc`]);
});

test('photo routes answer 501 when media storage is not configured', async () => {
  const { app } = buildApp({ media: null });
  const res = await app(req('POST', '/photos', { token: signToken({ sub: SUB }), body: { contentType: 'image/jpeg' } }));
  assert.equal(res.statusCode, 501);
});
