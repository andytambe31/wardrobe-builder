// Application composition. Builds the router and returns an async Lambda
// handler. Every request runs through the same pipeline:
//
//   1. CORS preflight (OPTIONS) short-circuits.
//   2. Route match (404 if none).
//   3. Public routes (e.g. /health) skip auth entirely.
//   4. Otherwise: extract bearer token -> verify it cryptographically
//      (defense in depth, independent of the API Gateway authorizer) ->
//      run the allow-list authz gate -> derive the owner sub.
//   5. Parse the JSON body, build ctx, invoke the handler.
//
// Dependencies (verify, data, media, jobs, secrets) are injected so the whole app can be tested with
// no AWS and no network.
import { createRouter } from './router.mjs';
import { bearerToken, AuthError } from './auth.mjs';
import { authorize, ForbiddenError } from './authz.mjs';
import { corsHeaders, json, error } from './response.mjs';
import * as h from './handlers.mjs';

export function createApp({ verify, data, media = null, jobs = null, secrets = null, config = {} }) {
  const router = createRouter();

  router.get('/health', h.health, { public: true });
  router.get('/me', h.me);
  router.get('/state', h.getState);
  router.get('/settings', h.getSettings);
  router.put('/settings', h.putSettings);
  router.put('/items/:id', h.putItem);
  router.del('/items/:id', h.deleteItem);
  router.post('/photos', h.postPhoto);
  router.get('/photos/:id', h.getPhoto);
  router.del('/photos/:id', h.deletePhoto);

  const allowedOrigins = config.corsOrigins || [];

  return async function handler(event) {
    const method = event?.requestContext?.http?.method || event?.httpMethod || 'GET';
    const path = event?.rawPath || event?.path || '/';
    const headers = normalizeHeaders(event?.headers);
    const origin = headers.origin || headers.Origin;
    const cors = corsHeaders(origin, allowedOrigins);

    // CORS preflight — never needs auth.
    if (method === 'OPTIONS') {
      return { statusCode: 204, headers: cors, body: '' };
    }

    const route = router.match(method, path);
    if (!route) return error(404, 'not_found', `no route for ${method} ${path}`, cors);

    let sub, claims;
    if (!route.public) {
      try {
        const token = bearerToken(headers);
        claims = await verify(token);
        ({ sub } = authorize(claims, config));
      } catch (err) {
        if (err instanceof AuthError) return error(401, err.code, 'authentication failed', cors);
        if (err instanceof ForbiddenError) return error(403, err.code, 'not authorized', cors);
        return error(500, 'auth_error', 'authentication error', cors);
      }
    }

    let body;
    try {
      body = parseBody(event);
    } catch {
      return error(400, 'bad_json', 'request body is not valid JSON', cors);
    }

    const ctx = { event: { ...event, headers }, params: route.params, body, sub, claims: claims || {}, data, media, jobs, secrets, config };

    try {
      const res = await route.handler(ctx);
      return { ...res, headers: { ...res.headers, ...cors } };
    } catch (err) {
      // Last-resort catch — never leak internals.
      return error(500, 'internal_error', 'unexpected error', cors);
    }
  };
}

function normalizeHeaders(headers = {}) {
  const out = {};
  for (const [k, v] of Object.entries(headers || {})) out[k.toLowerCase()] = v;
  return out;
}

function parseBody(event) {
  if (event == null || event.body == null || event.body === '') return undefined;
  let raw = event.body;
  if (event.isBase64Encoded) raw = Buffer.from(raw, 'base64').toString('utf8');
  if (typeof raw !== 'string') return raw; // already an object (tests)
  return JSON.parse(raw);
}
