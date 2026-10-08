output "api_endpoint" {
  description = "Base URL of the HTTP API."
  value       = module.api.api_endpoint
}

# The DNS record to add at your DNS provider (Namecheap) to validate the ACM
# cert for the custom domain. Null when no custom_domain is set. The for-over-
# resource + one() form is index-safe when the cert count is 0.
output "acm_validation_record" {
  description = "CNAME to add at your DNS host to validate the custom-domain cert."
  value = one([
    for c in aws_acm_certificate.custom : {
      name  = tolist(c.domain_validation_options)[0].resource_record_name
      type  = tolist(c.domain_validation_options)[0].resource_record_type
      value = tolist(c.domain_validation_options)[0].resource_record_value
    }
  ])
}

output "custom_domain_target" {
  description = "CNAME target for the custom domain (point wardrobe-builder.<domain> here once ready)."
  value       = var.enable_frontend ? one(module.frontend[*].distribution_domain) : null
}

output "media_bucket" {
  description = "Private S3 bucket holding user photos (users/<sub>/...)."
  value       = module.media.bucket_name
}

output "jobs_queue_url" {
  value = module.jobs.queue_url
}

output "jobs_dlq_name" {
  description = "Dead-letter queue: jobs that failed every retry. Inspect, then redrive from the SQS console."
  value       = module.jobs.dlq_name
}

output "ai_api_key_parameter" {
  description = "SSM parameter to put the AI API key in (see the README)."
  value       = local.ai_api_key_param
}

output "table_name" {
  value = module.dynamodb.table_name
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_client_id" {
  value = module.cognito.client_id
}

output "cognito_issuer" {
  value = module.cognito.issuer
}

output "cognito_region" {
  value = module.cognito.region
}

output "cognito_hosted_ui_domain" {
  description = "Hosted UI host — the `domain` value for the front-end auth-config."
  value       = module.cognito.hosted_ui_domain
}

output "cognito_hosted_ui_url" {
  value = module.cognito.hosted_ui_url
}

# Everything the front-end js/auth-config.js needs, in one place. After apply:
#   terraform output -json frontend_auth_config
output "frontend_auth_config" {
  description = "Paste these into js/auth-config.js (BUILTIN) or the login screen's Configure form."
  value = {
    region     = module.cognito.region
    userPoolId = module.cognito.user_pool_id
    clientId   = module.cognito.client_id
    domain     = module.cognito.hosted_ui_domain
  }
}

output "frontend_domain" {
  description = "CloudFront domain serving the PWA (null if frontend disabled)."
  value       = var.enable_frontend ? module.frontend[0].distribution_domain : null
}

output "frontend_bucket" {
  value = var.enable_frontend ? module.frontend[0].bucket_name : null
}

output "frontend_distribution_id" {
  value = var.enable_frontend ? module.frontend[0].distribution_id : null
}
