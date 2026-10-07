import { test } from 'node:test';
import assert from 'node:assert/strict';
import { authorize, ForbiddenError } from '../src/authz.mjs';

test('allows a sub on the allow-list', () => {
  const { sub } = authorize({ sub: 'sub-123' }, { allowedSubs: 'sub-123,sub-999' });
  assert.equal(sub, 'sub-123');
});

test('allows an email on the allow-list (case-insensitive)', () => {
  const { email } = authorize({ sub: 's', email: 'Me@Example.com' }, { allowedEmails: 'me@example.com' });
  assert.equal(email, 'me@example.com');
});

test('rejects a principal not on the allow-list', () => {
  assert.throws(
    () => authorize({ sub: 'intruder', email: 'x@y.com' }, { allowedSubs: 'sub-123', allowedEmails: 'me@example.com' }),
    (e) => e instanceof ForbiddenError && e.code === 'forbidden',
  );
});

test('fails closed when requireAllowlist and no list configured', () => {
  assert.throws(() => authorize({ sub: 's' }, { requireAllowlist: true }), (e) => e instanceof ForbiddenError);
});

test('falls back to any authenticated user when no list and not required', () => {
  const { sub } = authorize({ sub: 's' }, {});
  assert.equal(sub, 's');
});
