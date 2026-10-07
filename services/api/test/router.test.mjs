import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRouter } from '../src/router.mjs';

test('matches a static route', () => {
  const r = createRouter();
  r.get('/state', () => 'ok');
  const m = r.match('GET', '/state');
  assert.equal(m.handler(), 'ok');
  assert.deepEqual(m.params, {});
});

test('extracts :params and decodes them', () => {
  const r = createRouter();
  r.put('/items/:id', () => 1);
  const m = r.match('PUT', '/items/abc%3A1');
  assert.equal(m.params.id, 'abc:1');
});

test('distinguishes methods', () => {
  const r = createRouter();
  r.get('/x', () => 'g');
  r.post('/x', () => 'p');
  assert.equal(r.match('POST', '/x').handler(), 'p');
});

test('carries the public flag', () => {
  const r = createRouter();
  r.get('/health', () => 'h', { public: true });
  r.get('/me', () => 'm');
  assert.equal(r.match('GET', '/health').public, true);
  assert.equal(r.match('GET', '/me').public, false);
});

test('returns null for no match', () => {
  const r = createRouter();
  r.get('/x', () => 1);
  assert.equal(r.match('GET', '/nope'), null);
  assert.equal(r.match('DELETE', '/x'), null);
});

test('does not let :id span a slash', () => {
  const r = createRouter();
  r.get('/items/:id', () => 1);
  assert.equal(r.match('GET', '/items/a/b'), null);
});
