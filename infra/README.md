# Wardrobe Builder infrastructure (Terraform)

Enterprise-grade AWS backend for Wardrobe Builder, as Terraform. Nothing here is deployed
yet — this is the full IaC, ready to `plan`/`apply` once you point it at an AWS
account. Runtime is deliberately lean (serverless, ~$0–5/mo for one user); the
"enterprise" is in the scaffolding: remote state, keyless CI via OIDC/WIF,
least-privilege IAM, observability, and dev/prod separation.

## Architecture

```
 PWA ──▶ CloudFront + S3 (private, OAC)            [modules/frontend]  (optional)
   │  JWT (Cognito)
   ▼
 API Gateway HTTP API ──▶ Cognito JWT authorizer   [modules/apigateway, cognito]
   │
   ▼
 Lambda (Node 20) ──▶ DynamoDB single-table        [modules/lambda, dynamodb]
   │                    (PK=USER#sub, GSI1, PITR, deletion protection)
   ├─ signs uploads/downloads ──▶ S3 media bucket   [modules/media]
   │    (private, users/<sub>/photos/*; browser POSTs/GETs via presigned forms/URLs)
   └─ CloudWatch logs/alarms + budget              [modules/observability]

 State:  S3 + DynamoDB lock                         [bootstrap]
 CI/CD:  GitHub Actions → AWS via OIDC/WIF          [.github/workflows/deploy-infra.yml]
```

## Layout

```
infra/
  bootstrap/            # remote state bucket + lock + GitHub OIDC role (run ONCE, local state)
  modules/
    app-stack/          # composes the leaf modules for one environment
    dynamodb/  cognito/  lambda/  apigateway/  frontend/  media/  observability/
  envs/dev/  envs/prod/ # thin roots: provider + backend + one app-stack call
services/api/           # the Lambda source (auth/authz platform + generic owner-scoped CRUD)
```

## One-time bootstrap

Creates the state backend and the CI role. Uses **local** state.

```bash
cd infra/bootstrap
terraform init
terraform apply \
  -var 'state_bucket_name=wardrobe-builder-tfstate-<your-unique-suffix>' \
  -var 'github_owner=andytambe31' -var 'github_repo=wardrobe-builder'
terraform output   # note state_bucket, lock_table, ci_role_arn
```

Then set GitHub repo **Variables** (Settings → Secrets and variables → Actions):
`AWS_ROLE_ARN` = `ci_role_arn`, `TF_STATE_BUCKET` = `state_bucket`,
`TF_LOCK_TABLE` = `lock_table`.

## Deploy an environment (dev shown)

```bash
cd infra/envs/dev
cp backend.hcl.example backend.hcl           # fill in state_bucket
cp terraform.tfvars.example terraform.tfvars # adjust region/email/origins
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
terraform output   # api_endpoint, cognito ids, frontend_domain
```

Create your user (self-signup is off):

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$(terraform output -raw cognito_user_pool_id)" \
  --username you@example.com --user-attributes Name=email,Value=you@example.com Name=email_verified,Value=true
```

### Wire the front-end login wall

Cognito is configured for the browser's **Authorization Code + PKCE** flow via
the Hosted UI (a `*.auth.<region>.amazoncognito.com` domain is provisioned
automatically). After `apply`, copy the client settings into the PWA:

```bash
terraform output -json frontend_auth_config
# -> { "region", "userPoolId", "clientId", "domain" }
```

The `deploy-frontend` workflow writes these into `config.js`
(`window.__WARDROBE_CONFIG__`) automatically; for local testing, wire them into
the app's auth config by hand. The app client's callback URLs are `auth_callback_urls` (the
full app URL incl. path — the SPA's `redirect_uri` must match exactly), and the
API's CORS uses `app_origins` (bare origins). Lock the app to yourself by setting
`allowed_subs` / `allowed_emails` (the API fails closed with neither set).

If `enable_frontend = true`, publish the PWA:

```bash
aws s3 sync ../../../ "s3://$(terraform output -raw frontend_bucket)" \
  --exclude '.git/*' --exclude 'infra/*' --exclude 'services/*' --exclude 'scratch-tests/*'
aws cloudfront create-invalidation \
  --distribution-id "$(terraform output -raw frontend_distribution_id)" --paths '/*'
```

## CI/CD

`.github/workflows/deploy-infra.yml`:

- **On a PR** touching `infra/**` or `services/api/**`: the API unit tests, plus
  `fmt` (advisory) and `validate` for dev and prod. No AWS access — PRs can't
  assume the deploy role.
- **On workflow_dispatch** (Actions → Terraform (infra) → Run workflow → env):
  API tests first, then `plan` + `apply` through the OIDC role (no stored keys),
  then a smoke test that `GET /health` on the new API returns 200.

It won't run on ordinary pushes, so nothing deploys until you wire the AWS
account and trigger it.

## Notes / deliberate choices

- **Server-authoritative + Cognito**: the API is the source of truth; the browser
  keeps an IndexedDB read-through cache (client work, not in this repo yet).
- **DynamoDB single-table** (PK/SK + GSI1).
- **The API is real** (`services/api/`) — cryptographic JWT re-verification, an
  allow-list authz gate, owner-scoped DynamoDB, and CRUD (`/state`, `/items`,
  `/settings`) with `If-Match` optimistic concurrency. See
  `services/api/README.md`.
- **Photos go straight to S3, never through the Lambda**: `POST /photos` returns
  a presigned POST form whose signed policy pins the exact key
  (`users/<sub>/photos/<uuid>`), the image Content-Type and a size cap
  (`media_max_bytes`, 10 MB by default), so S3 itself rejects anything else.
  `GET /photos/:id` returns a 5-minute download URL. The Lambda role can only
  read/write/delete under `users/*`; the bucket is private, TLS-only, encrypted
  and versioned (old versions expire after 30 days).
- **Auth is Hosted UI + PKCE**: the SPA client has no secret; a Cognito domain
  is auto-created so the login flow works out of the box. The app re-verifies
  tokens itself, so gateway + app both enforce.
- **Deploy only through the CI role (guardrail)**: bootstrap also creates a
  `wardrobe-builder-deploy-only-guardrail` Deny policy that blocks infra-mutating actions
  (and IAM changes, to stop escalation) for every principal except the deploy
  role, your break-glass admin (`guardrail_break_glass_arns`), and AWS
  service-linked roles. Reads still work. Attach it to your human IAM group(s)
  via `guardrail_attach_group_names` to enforce — it's created but attached to
  no one by default. Caveat: this is a **standalone account**, so nothing here
  can bind the root user or future principals — pair it with giving humans
  read-only and not creating other admin credentials. For account-wide,
  root-inclusive, future-proof enforcement, enable **AWS Organizations** and
  promote this same policy JSON to a **Service Control Policy** attached to the
  account/OU (an SCP the root user can't override).
  As an SCP it would also bind the Lambda role, so exempt
  `role/wardrobe-builder-*-api-exec` (or scope the S3 deny away from the media
  bucket) first — otherwise photo uploads and deletes stop working.
- **Least-privilege deploy role (default)**: the GitHub Actions OIDC role gets a
  hand-scoped policy (`wardrobe-builder-ci-deploy`) that grants only the services these
  stacks manage — DynamoDB/Lambda/Cognito/API Gateway/S3/CloudFront/SNS/
  CloudWatch/Logs/Budgets — and, where the service supports it, only ARNs under
  the `wardrobe-builder-*` namespace (plus the remote-state bucket/lock table and the KMS
  key reachable through S3). A leaked OIDC credential can't touch EC2, RDS, IAM
  users, billing, or anything outside the project. IAM management is a separate
  grant scoped to `role/wardrobe-builder-*`. If a future resource type isn't yet covered,
  set `use_power_user_access = true` to fall back to the broad AWS-managed
  `PowerUserAccess` (admin minus IAM) as an escape hatch. Lambda's own runtime
  role stays least-privilege (logs + X-Ray + this table only).
- Run `terraform fmt -recursive` before your first commit to satisfy the (advisory)
  format check.
```
