// Wardrobe Builder API entrypoint (nodejs20.x Lambda). Wires environment configuration
// into the app and exports the handler. The @aws-sdk/* packages are provided by
// the runtime; any other npm dependencies in package.json are installed by CI
// (npm ci --omit=dev) before Terraform zips this directory.
//
// Auth is defense-in-depth: even though API Gateway runs a Cognito JWT
// authorizer in front of us, this app re-verifies the token cryptographically
// and enforces a strict allow-list, so the endpoints stay gated even against a
// direct invoke or an authorizer misconfiguration.
import { createApp } from './src/app.mjs';
import { verifyJwt } from './src/auth.mjs';
import { createAwsDeps } from './src/aws.mjs';

const config = {
  env: process.env.ENV || 'dev',
  issuer: process.env.COGNITO_ISSUER || deriveIssuer(),
  clientIds: splitEnv(process.env.COGNITO_CLIENT_ID),
  allowedSubs: process.env.ALLOWED_SUBS || '',
  allowedEmails: process.env.ALLOWED_EMAILS || '',
  // Fail closed: with no allow-list configured, reject everyone rather than
  // fall back to "any pool member". The pool is admin-create-only, but the
  // allow-list is the real single-user gate and we require it.
  requireAllowlist: process.env.REQUIRE_ALLOWLIST !== 'false',
  corsOrigins: splitEnv(process.env.CORS_ORIGINS),
  // SSM parameter holding the AI provider key; read it with
  // ctx.secrets.get(ctx.config.aiApiKeyParam).
  aiApiKeyParam: process.env.AI_API_KEY_PARAM || '',
};

// DynamoDB, S3 media, the jobs queue and secrets — shared with worker.mjs.
const { data, media, jobs, secrets } = createAwsDeps();

// Bind the verifier to this pool's issuer/client so handlers just call verify(token).
const verify = (token) => verifyJwt(token, {
  issuer: config.issuer,
  clientIds: config.clientIds,
  // Accept both access and id tokens from this pool.
  allowedTokenUse: ['access', 'id'],
});

export const handler = createApp({ verify, data, media, jobs, secrets, config });

// Build the Cognito issuer URL from region + pool id if not supplied directly.
function deriveIssuer() {
  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION;
  const pool = process.env.COGNITO_USER_POOL;
  return region && pool ? `https://cognito-idp.${region}.amazonaws.com/${pool}` : '';
}

function splitEnv(v) {
  return String(v || '').split(',').map((x) => x.trim()).filter(Boolean);
}
