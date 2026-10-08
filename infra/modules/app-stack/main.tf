terraform {
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.40" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

# The whole application stack for one environment, composed from the leaf
# modules. Each env root just calls this with env-specific inputs + backend.
locals {
  prefix = "${var.project}-${var.env}"
  tags = merge({
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }, var.tags)
}

data "aws_caller_identity" "current" {}

locals {
  # Origins that must be trusted for OAuth callbacks + CORS: the CloudFront
  # domain (once the frontend exists) and, optionally, a custom domain. Both are
  # appended automatically so sign-in works from whichever URL the app is served
  # at. module.frontend is count'd, so splat + one() (null when absent) is safe.
  cf_domain         = one(module.frontend[*].distribution_domain)
  cloudfront_origin = local.cf_domain != null ? "https://${local.cf_domain}" : ""

  # The custom domain is only trusted once it's live on CloudFront
  # (custom_domain_ready), i.e. after the ACM cert is validated + attached.
  custom_attached = var.custom_domain != "" && var.custom_domain_ready
  custom_origin   = local.custom_attached ? "https://${var.custom_domain}" : ""

  extra_origins   = compact([local.cloudfront_origin, local.custom_origin])
  extra_callbacks = [for o in local.extra_origins : "${o}/"]

  web_origins   = compact(concat(var.app_origins, local.extra_origins))
  callback_urls = compact(concat(var.auth_callback_urls, local.extra_callbacks))
  logout_base   = length(var.auth_logout_urls) > 0 ? var.auth_logout_urls : var.auth_callback_urls
  logout_urls   = compact(concat(local.logout_base, local.extra_callbacks))

  # ACM cert ARN for the custom domain (null until requested). one()+splat is
  # index-safe when the cert count is 0.
  custom_cert_arn = one(aws_acm_certificate.custom[*].arn)
}

# ACM certificate for the custom domain. Must be in us-east-1 for CloudFront —
# this stack's provider is us-east-1, so no aliased provider is needed. DNS
# validation; the validation record is exposed as an output to add at your DNS
# provider. Created as soon as custom_domain is set; attached to CloudFront only
# once custom_domain_ready flips true (after the cert is ISSUED).
resource "aws_acm_certificate" "custom" {
  count             = var.custom_domain == "" ? 0 : 1
  domain_name       = var.custom_domain
  validation_method = "DNS"
  tags              = local.tags
  lifecycle {
    create_before_destroy = true
  }
}

module "dynamodb" {
  source              = "../dynamodb"
  name                = "${local.prefix}-data"
  deletion_protection = var.deletion_protection
  tags                = local.tags
}

module "cognito" {
  source = "../cognito"
  name   = "${local.prefix}-users"
  # Exact OAuth redirect URLs (full app URL incl. path), NOT bare origins —
  # Cognito matches these exactly against the SPA's redirect_uri. CORS uses
  # app_origins separately (see the api module).
  callback_urls           = local.callback_urls
  logout_urls             = local.logout_urls
  hosted_ui_domain_prefix = var.cognito_domain_prefix
  tags                    = local.tags
}

module "media" {
  source             = "../media"
  bucket_name        = "${local.prefix}-media-${data.aws_caller_identity.current.account_id}"
  cors_allow_origins = local.web_origins
  enable_cors        = length(var.app_origins) > 0 || var.enable_frontend || local.custom_attached
  tags               = local.tags
}

# --- AI provider credentials ---------------------------------------------------
# The AI API key lives in an SSM SecureString parameter that Terraform does NOT
# manage: a managed parameter is read back (decrypted) into state on every
# refresh, which would put the key in the state file. Terraform only fixes the
# name and grants the Lambdas read access; create the parameter once, out of
# band (see infra/README.md). The Lambdas get the NAME and read the value at
# runtime.
data "aws_region" "current" {}

locals {
  ai_api_key_param     = "/${var.project}/${var.env}/ai-api-key"
  ai_api_key_param_arn = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.ai_api_key_param}"
}

locals {
  # Read the key. No kms grant is needed: the parameter is encrypted with the
  # AWS-managed aws/ssm key, whose key policy already lets principals in this
  # account decrypt through SSM (and only through SSM).
  secret_read_statements = [
    {
      sid       = "ReadAiApiKey"
      actions   = ["ssm:GetParameter"]
      resources = [local.ai_api_key_param_arn]
    },
  ]

  # Settings both Lambdas share. They run from the same source package.
  shared_env = {
    ENV               = var.env
    COGNITO_USER_POOL = module.cognito.user_pool_id
    COGNITO_CLIENT_ID = module.cognito.client_id
    COGNITO_ISSUER    = module.cognito.issuer

    MEDIA_BUCKET     = module.media.bucket_name
    MEDIA_MAX_BYTES  = tostring(var.media_max_bytes)
    JOBS_QUEUE_URL   = module.jobs.queue_url
    AI_API_KEY_PARAM = local.ai_api_key_param
    NODE_OPTIONS     = "--enable-source-maps"
  }
}

# --- Background jobs (AI work that outlives API Gateway's 30s limit) ----------
module "jobs" {
  source                 = "../jobs"
  name                   = local.prefix
  worker_timeout_seconds = var.worker_timeout_seconds
  tags                   = local.tags
}

module "worker" {
  source           = "../lambda"
  name             = "${local.prefix}-worker"
  source_dir       = var.api_source_dir
  handler          = "worker.handler"
  timeout          = var.worker_timeout_seconds
  memory_size      = var.worker_memory_mb
  table_name       = module.dynamodb.table_name
  table_arn        = module.dynamodb.table_arn
  table_gsi_arn    = module.dynamodb.gsi1_arn
  enable_media     = true
  media_bucket_arn = module.media.bucket_arn
  extra_statements = concat(local.secret_read_statements, [
    {
      sid       = "ConsumeJobs"
      actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
      resources = [module.jobs.queue_arn]
    },
  ])
  environment = local.shared_env
  tags        = local.tags
}

# The queue -> worker trigger lives here (not in modules/jobs) so it can wait
# for the whole worker module: Lambda checks the role's SQS permissions when the
# mapping is created, and the role policy itself needs the queue ARN.
resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn = module.jobs.queue_arn
  function_name    = module.worker.function_arn
  # One message per invocation (AI jobs are slow and independent), partial-
  # batch failure reporting, and a concurrency cap so a burst of jobs can't fan
  # out into a burst of paid model calls.
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config {
    maximum_concurrency = var.worker_max_concurrency
  }
  depends_on = [module.worker]
}

module "lambda" {
  source           = "../lambda"
  name             = "${local.prefix}-api"
  source_dir       = var.api_source_dir
  handler          = "index.handler"
  table_name       = module.dynamodb.table_name
  table_arn        = module.dynamodb.table_arn
  table_gsi_arn    = module.dynamodb.gsi1_arn
  enable_media     = true
  media_bucket_arn = module.media.bucket_arn
  # Just under API Gateway's 30s integration limit; anything slower belongs on
  # the job queue.
  timeout = 29
  extra_statements = concat(local.secret_read_statements, [
    {
      sid       = "EnqueueJobs"
      actions   = ["sqs:SendMessage"]
      resources = [module.jobs.queue_arn]
    },
  ])
  environment = merge(local.shared_env, {
    # The strong single-user gate: only these principals get past authz, even
    # with a valid pool token. Fail closed when the list is empty.
    ALLOWED_SUBS      = join(",", var.allowed_subs)
    ALLOWED_EMAILS    = join(",", var.allowed_emails)
    REQUIRE_ALLOWLIST = tostring(var.require_allowlist)
    CORS_ORIGINS      = join(",", local.web_origins)
  })
  tags = local.tags
}

module "api" {
  source               = "../apigateway"
  name                 = "${local.prefix}-http"
  lambda_invoke_arn    = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name
  cognito_issuer       = module.cognito.issuer
  cognito_client_id    = module.cognito.client_id
  cors_allow_origins   = length(local.web_origins) > 0 ? local.web_origins : ["*"]
  tags                 = local.tags
}

module "frontend" {
  count       = var.enable_frontend ? 1 : 0
  source      = "../frontend"
  bucket_name = "${local.prefix}-web-${data.aws_caller_identity.current.account_id}"
  # Attach the custom domain + its cert only once it's validated & ready.
  domain_aliases      = local.custom_attached ? [var.custom_domain] : var.frontend_domain_aliases
  acm_certificate_arn = local.custom_attached ? local.custom_cert_arn : var.frontend_acm_certificate_arn
  tags                = local.tags
}

module "observability" {
  source               = "../observability"
  name                 = local.prefix
  lambda_function_name = module.lambda.function_name
  api_id               = module.api.api_id
  table_name           = module.dynamodb.table_name
  enable_worker_alarms = true
  worker_function_name = module.worker.function_name
  dlq_name             = module.jobs.dlq_name
  alert_email          = var.alert_email
  budget_limit_usd     = var.budget_limit_usd
  tags                 = local.tags
}
