provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "wardrobe-builder"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

module "stack" {
  source = "../../modules/app-stack"

  project                      = "wardrobe-builder"
  env                          = "prod"
  api_source_dir               = "${path.module}/../../../services/api"
  app_origins                  = var.app_origins
  auth_callback_urls           = var.auth_callback_urls
  auth_logout_urls             = var.auth_logout_urls
  enable_frontend              = var.enable_frontend
  frontend_domain_aliases      = var.frontend_domain_aliases
  frontend_acm_certificate_arn = var.frontend_acm_certificate_arn
  cognito_domain_prefix        = var.cognito_domain_prefix
  deletion_protection          = true
  custom_domain                = var.custom_domain
  custom_domain_ready          = var.custom_domain_ready
  allowed_subs                 = var.allowed_subs
  allowed_emails               = var.allowed_emails
  alert_email                  = var.alert_email
  budget_limit_usd             = var.budget_limit_usd
}
