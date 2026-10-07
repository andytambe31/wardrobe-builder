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

module "lambda" {
  source        = "../lambda"
  name          = "${local.prefix}-api"
  source_dir    = var.api_source_dir
  handler       = "index.handler"
  table_name    = module.dynamodb.table_name
  table_arn     = module.dynamodb.table_arn
  table_gsi_arn = module.dynamodb.gsi1_arn
  environment = {
    ENV               = var.env
    COGNITO_USER_POOL = module.cognito.user_pool_id
    COGNITO_CLIENT_ID = module.cognito.client_id
    COGNITO_ISSUER    = module.cognito.issuer

    # The strong single-user gate: only these principals get past authz, even
    # with a valid pool token. Fail closed when the list is empty.
    ALLOWED_SUBS      = join(",", var.allowed_subs)
    ALLOWED_EMAILS    = join(",", var.allowed_emails)
    REQUIRE_ALLOWLIST = tostring(var.require_allowlist)
    CORS_ORIGINS      = join(",", local.web_origins)
  }
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
  alert_email          = var.alert_email
  budget_limit_usd     = var.budget_limit_usd
  tags                 = local.tags
}
