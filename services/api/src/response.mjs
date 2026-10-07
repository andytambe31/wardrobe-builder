// HTTP response helpers for API Gateway HTTP API (payload format 2.0).
// Security headers on every response; CORS locked to configured origins.

const SECURITY_HEADERS = {
  'content-type': 'application/json',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'cache-control': 'no-store',
  'strict-transport-security': 'max-age=63072000; includeSubDomains',
};

// allowedOrigins: array; '*' allowed but discouraged. Reflects the request
// origin only when it's in the allow-list (so credentials stay safe).
export function corsHeaders(origin, allowedOrigins) {
  if (!allowedOrigins || allowedOrigins.length === 0) return {};
  const allow = allowedOrigins.includes('*')
    ? '*'
    : (origin && allowedOrigins.includes(origin) ? origin : allowedOrigins[0]);
  return {
    'access-control-allow-origin': allow,
    'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type,if-match',
    'access-control-max-age': '3600',
    'vary': 'Origin',
  };
}

export function json(statusCode, body, extraHeaders = {}) {
  return {
    statusCode,
    headers: { ...SECURITY_HEADERS, ...extraHeaders },
    body: JSON.stringify(body),
  };
}

// Never leak internals in error bodies — a stable machine code + safe message.
export function error(statusCode, code, message, extraHeaders = {}) {
  return json(statusCode, { error: code, message: message || code }, extraHeaders);
}
