output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}

output "client_id" {
  value = aws_cognito_user_pool_client.spa.id
}

output "region" {
  value = data.aws_region.current.name
}

output "issuer" {
  description = "OIDC issuer URL — the JWT authorizer audience/issuer the API validates against."
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "hosted_ui_domain" {
  description = "Hosted UI host, e.g. wardrobe-builder-prod-users-ab12cd.auth.us-east-1.amazoncognito.com — this is the `domain` value for the front-end auth-config."
  value       = "${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "hosted_ui_url" {
  description = "Full https base URL of the Hosted UI."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}
