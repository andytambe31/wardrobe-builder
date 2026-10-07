// Authorization — the "only me" gate on top of authentication.
//
// Two layers:
//  1. An explicit allow-list of subjects/emails. Configure ALLOWED_SUBS and/or
//     ALLOWED_EMAILS and only those principals get in — a valid Cognito user who
//     isn't on the list is rejected with 403. This is the strong single-user gate.
//  2. Owner-scoping: every data path derives its DynamoDB partition from the
//     caller's own `sub` (USER#<sub>). No endpoint accepts a user id, so a caller
//     can only ever read/write their own data — there is no cross-tenant surface.

export class ForbiddenError extends Error {
  constructor(message) { super(message || 'forbidden'); this.name = 'ForbiddenError'; this.code = 'forbidden'; }
}

const parseList = (v) => String(v || '').split(',').map((x) => x.trim().toLowerCase()).filter(Boolean);

// config: { allowedSubs: string, allowedEmails: string, requireAllowlist: bool }
// Returns { sub, email } on success; throws ForbiddenError otherwise.
export function authorize(claims, config = {}) {
  const subs = parseList(config.allowedSubs);
  const emails = parseList(config.allowedEmails);
  const sub = claims.sub;
  const email = (claims.email || '').toLowerCase();

  // If no allow-list is configured, fall back to the pool's admin-only signup
  // (only invited users exist). Set requireAllowlist=true to hard-fail instead —
  // the strictest posture.
  if (subs.length === 0 && emails.length === 0) {
    if (config.requireAllowlist) throw new ForbiddenError('no allow-list configured');
    return { sub, email };
  }

  if (sub && subs.includes(sub.toLowerCase())) return { sub, email };
  if (email && emails.includes(email)) return { sub, email };
  throw new ForbiddenError('principal not on the allow-list');
}
