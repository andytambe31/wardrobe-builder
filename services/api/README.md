# Wardrobe Builder API

Server-authoritative backend for the Wardrobe Builder PWA. Runs as a single AWS Lambda
(nodejs20.x) behind an API Gateway HTTP API. Zero npm dependencies — the
`@aws-sdk/*` packages are provided by the runtime, and everything else uses
Node's built-ins.

## Security model — gated for a single user

Authentication and authorization are **defense-in-depth**, so the endpoints stay
locked even if a layer is misconfigured:

1. **API Gateway Cognito authorizer** validates the JWT at the edge.
2. **The app re-verifies the token cryptographically** (`src/auth.mjs`):
   RS256 signature against the pool's JWKS, plus issuer, audience/client_id,
   expiry, `nbf`, and `token_use` checks. A direct Lambda invoke or an
   authorizer misconfiguration still can't get past this.
3. **Allow-list authorization** (`src/authz.mjs`): only principals on
   `ALLOWED_SUBS` / `ALLOWED_EMAILS` are admitted — a valid pool user who isn't
   on the list gets `403`. With `REQUIRE_ALLOWLIST=true` (the default) an empty
   allow-list **fails closed**. This is the strong "only me" gate.
4. **Owner-scoping** (`src/ddb.mjs`): every data path derives its DynamoDB
   partition from the caller's own `sub` (`USER#<sub>`). No endpoint accepts a
   user id, so there is no cross-user surface.

Responses carry strict security headers and `cache-control: no-store`; CORS is
locked to the configured origins.

## Endpoints

| Method | Path          | Auth   | Purpose                                          |
|--------|---------------|--------|--------------------------------------------------|
| GET    | `/health`     | public | Liveness for CI/smoke tests                      |
| GET    | `/me`         | gated  | Echo the authenticated principal                 |
| GET    | `/state`      | gated  | Bootstrap — everything in the user's partition   |
| GET    | `/settings`   | gated  | Read settings                                    |
| PUT    | `/settings`   | gated  | Upsert settings (optimistic concurrency)         |
| PUT    | `/items/:id`  | gated  | Upsert an item (optimistic concurrency)          |
| DELETE | `/items/:id`  | gated  | Delete an item                                   |
| POST   | `/photos`     | gated  | Presigned S3 upload form (`{ contentType }`)     |
| GET    | `/photos/:id` | gated  | Short-lived presigned download URL               |
| DELETE | `/photos/:id` | gated  | Delete a photo                                   |

### Photo uploads

`POST /photos` with `{ "contentType": "image/jpeg" }` (also `image/png`,
`image/webp`, `image/heic`) returns `{ id, upload: { url, fields }, maxBytes }`.
The browser then uploads directly to S3:

```js
const form = new FormData();
for (const [k, v] of Object.entries(upload.fields)) form.append(k, v);
form.append('file', file); // must be last
await fetch(upload.url, { method: 'POST', body: form }); // 204 on success
```

The signed policy fixes the key, type and size, so S3 rejects anything else.
Presigning is done in `src/presign.mjs` (SigV4, no SDK) and is checked against
AWS's published test vector.

### Optimistic concurrency

Mutating routes accept an `If-Match: <version>` header. On a version mismatch the
write is rejected with `409 version_conflict` — re-fetch and retry. Successful
writes return the new version in an `ETag` header. The server owns keys,
`version`, and `updatedAt`; any of those sent in a request body are ignored.

## Environment variables

| Var                 | Meaning                                                        |
|---------------------|---------------------------------------------------------------|
| `TABLE_NAME`        | DynamoDB single-table name                                     |
| `COGNITO_ISSUER`    | `https://cognito-idp.<region>.amazonaws.com/<pool_id>`         |
| `COGNITO_USER_POOL` | Pool id (used to derive the issuer if `COGNITO_ISSUER` unset)  |
| `COGNITO_CLIENT_ID` | App client id(s), comma-separated — checked as the audience    |
| `ALLOWED_SUBS`      | Comma-separated Cognito subject ids allowed in                 |
| `ALLOWED_EMAILS`    | Comma-separated emails allowed in (case-insensitive)           |
| `REQUIRE_ALLOWLIST` | `true` (default) fails closed when no allow-list is configured |
| `CORS_ORIGINS`      | Comma-separated allowed web origins                            |
| `MEDIA_BUCKET`      | S3 bucket for photos (unset = photo routes return 501)         |
| `MEDIA_MAX_BYTES`   | Largest upload the API will sign for (default 10 MB)           |
| `ENV`               | `dev` \| `prod`                                                |

Terraform wires all of these from `infra/modules/app-stack`.

## Tests

```
npm test        # node --test test/*.test.mjs
```

The suite generates a real RSA key pair, mints RS256 tokens, and drives the app
end-to-end with an in-memory data layer — no AWS and no network required. It
covers signature/issuer/audience/expiry rejection, the allow-list gate,
owner-scoping isolation, optimistic concurrency, and body-spoofing defenses.
