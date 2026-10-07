provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "wardrobe-builder"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

module "stack" {
  source = "../../modules/app-stack"

  project             = "wardrobe-builder"
  env                 = "dev"
  api_source_dir      = "${path.module}/../../../services/api"
  app_origins         = var.app_origins
  auth_callback_urls  = var.auth_callback_urls
  auth_logout_urls    = var.auth_logout_urls
  enable_frontend     = var.enable_frontend
  deletion_protection = false # dev can be torn down freely
  allowed_subs        = var.allowed_subs
  allowed_emails      = var.allowed_emails
  alert_email         = var.alert_email
  budget_limit_usd    = var.budget_limit_usd
}
