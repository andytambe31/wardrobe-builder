// Route handlers. Each receives a ctx built by app.mjs:
//   { event, params, body, sub, claims, data, config }
// Handlers never see another user's partition — `data` is owner-scoped to
// ctx.sub, and no handler reads a user id from the request.
import { json, error } from './response.mjs';
import { VersionConflict } from './errors.mjs';

// SK conventions for the single-table layout.
const SK = {
  settings: 'SETTINGS',
  item: (id) => `ITEM#${id}`,
};

// GET /health — public. No auth, no data access. Used by CI/smoke tests.
export function health(ctx) {
  return json(200, {
    ok: true,
    service: 'wardrobe-builder-api',
    env: ctx.config.env || 'dev',
    time: new Date().toISOString(),
  });
}

// GET /me — echoes the authenticated principal. Confirms the gate works and
// lets the client learn its own sub without decoding the token.
export function me(ctx) {
  return json(200, {
    sub: ctx.sub,
    email: ctx.claims.email || null,
    tokenUse: ctx.claims.token_use || null,
  });
}

// GET /state — one query returns everything in the user's partition. This is
// the client bootstrap.
export async function getState(ctx) {
  const items = await ctx.data.queryUser(ctx.sub);
  return json(200, { items });
}

// GET /settings
export async function getSettings(ctx) {
  const s = await ctx.data.getItem(ctx.sub, SK.settings);
  return json(200, s || { type: 'settings', version: 0 });
}

// PUT /settings — optimistic concurrency via If-Match: <version>.
export async function putSettings(ctx) {
  const expectedVersion = ifMatch(ctx);
  const attrs = { ...sanitize(ctx.body), type: 'settings' };
  return withConflict(() => ctx.data.putItem(ctx.sub, SK.settings, attrs, { expectedVersion }));
}

// PUT /items/:id — upsert a single item.
export async function putItem(ctx) {
  const id = ctx.params.id;
  if (!validId(id)) return error(400, 'bad_id', 'invalid item id');
  const expectedVersion = ifMatch(ctx);
  const attrs = { ...sanitize(ctx.body), type: 'item', id };
  return withConflict(() => ctx.data.putItem(ctx.sub, SK.item(id), attrs, { expectedVersion }));
}

// DELETE /items/:id
export async function deleteItem(ctx) {
  const id = ctx.params.id;
  if (!validId(id)) return error(400, 'bad_id', 'invalid item id');
  await ctx.data.deleteItem(ctx.sub, SK.item(id));
  return json(200, { deleted: id });
}

// ---- helpers ----

// Parse an If-Match header into a numeric expected version, or undefined for an
// unconditional write. We accept a bare number or a quoted ETag ("3").
function ifMatch(ctx) {
  const h = ctx.event?.headers || {};
  const raw = h['if-match'] ?? h['If-Match'];
  if (raw == null || raw === '' || raw === '*') return undefined;
  const n = Number(String(raw).replace(/"/g, '').trim());
  return Number.isFinite(n) ? n : undefined;
}

async function withConflict(fn) {
  try {
    const saved = await fn();
    return json(200, saved, { etag: `"${saved.version}"` });
  } catch (err) {
    if (err instanceof VersionConflict) {
      return error(409, 'version_conflict', 'the item was modified by another write; re-fetch and retry');
    }
    throw err;
  }
}

// Strip attributes the client must never control — the server owns keys,
// versioning, and timestamps.
function sanitize(body) {
  const b = body && typeof body === 'object' ? { ...body } : {};
  delete b.PK; delete b.SK; delete b.GSI1PK; delete b.GSI1SK;
  delete b.version; delete b.updatedAt;
  return b;
}

const validId = (id) => typeof id === 'string' && /^[A-Za-z0-9_.:-]{1,128}$/.test(id);
