terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.40" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

data "aws_region" "current" {}

# Cognito user pool — single user today, but a real identity provider so the API
# is JWT-guarded and this is multi-tenant-ready. Email sign-in, strong password
# policy, self-signup off (you invite yourself), tokens short-lived.
resource "aws_cognito_user_pool" "this" {
  name                     = var.name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = var.mfa_configuration

  # If MFA is OPTIONAL/ON, Cognito requires at least one method to be enabled.
  # Enable TOTP (authenticator app) — no SMS costs, and the right default for a
  # security-first setup. Omitted entirely when MFA is OFF (a config block with
  # it enabled would conflict).
  dynamic "software_token_mfa_configuration" {
    for_each = var.mfa_configuration == "OFF" ? [] : [1]
    content {
      enabled = true
    }
  }

  # No open sign-up: an admin creates the user.
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = var.tags
}

# Public SPA client — no client secret (a browser can't keep one). The front-end
# uses the Authorization Code + PKCE flow via the Hosted UI, so we enable the
# `code` grant and the OIDC scopes the app requests. SRP stays enabled as an
# alternative (e.g. a future custom login form). Short access/id tokens, longer
# refresh — matching the client's 30-day session window.
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.name}-spa"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  supported_identity_providers = ["COGNITO"]

  # OAuth (Hosted UI + PKCE) is on whenever callback URLs are configured.
  allowed_oauth_flows_user_pool_client = length(var.callback_urls) > 0
  allowed_oauth_flows                  = length(var.callback_urls) > 0 ? ["code"] : []
  allowed_oauth_scopes                 = length(var.callback_urls) > 0 ? ["email", "openid", "profile"] : []
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# A short random suffix so the Hosted UI domain prefix is globally unique
# without the operator having to guess an available name. Stable across applies
# (only regenerates if the pool name changes). Ignored when an explicit prefix
# is supplied.
resource "random_string" "domain_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
  keepers = { pool = var.name }
}

locals {
  # A valid Cognito domain prefix: lowercase, digits, hyphens. Derive one from
  # the pool name + random suffix unless the operator pinned an explicit prefix.
  domain_prefix = var.hosted_ui_domain_prefix != "" ? var.hosted_ui_domain_prefix : "${replace(lower(var.name), "_", "-")}-${random_string.domain_suffix.result}"
}

# Hosted UI domain (the *.auth.<region>.amazoncognito.com login page the SPA
# redirects to). Always provisioned so the login flow works out of the box.
resource "aws_cognito_user_pool_domain" "this" {
  domain       = local.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}
