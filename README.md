# Wardrobe Builder

A personal style app: learn what works for your body type and build a sense of
style, with AI help on top of your own photos and wardrobe.

## Repo layout

| Path            | What                                                                 |
|-----------------|----------------------------------------------------------------------|
| `web/`          | Frontend (placeholder page for now). See [web/README.md](web/README.md). |
| `services/api/` | Backend: API Lambda (`index.mjs`) + background worker (`worker.mjs`). See [services/api/README.md](services/api/README.md). |
| `infra/`        | Terraform for AWS. See [infra/README.md](infra/README.md).           |
| `.github/workflows/` | CI + deploys (keyless via GitHub OIDC).                         |

## Platform at a glance

- **Frontend:** static build on S3 + CloudFront; runtime config in `/config.js`.
- **Auth:** Cognito Hosted UI (Authorization Code + PKCE); the API re-verifies
  every token and only lets allow-listed users in.
- **API:** API Gateway HTTP API → Lambda (Node 20), ≤29s per request.
- **Data:** DynamoDB single table, every record scoped to the signed-in user.
- **Photos:** private S3 bucket; the browser uploads and downloads directly
  via short-lived presigned forms/URLs.
- **AI / slow work:** SQS queue → worker Lambda (≤5 min), with retries and a
  dead-letter queue. The AI API key is in SSM Parameter Store, read at runtime.
- **Ops:** CloudWatch alarms + a monthly budget, emailed to you.

## Deploying

1. One-time: `infra/bootstrap` (state bucket, lock table, GitHub deploy role),
   then set the repo Variables it prints.
2. **Actions → Terraform (infra)** → env.
3. Put the AI key in SSM (command in [infra/README.md](infra/README.md)).
4. **Actions → Frontend** → env.

Details in [infra/README.md](infra/README.md).
