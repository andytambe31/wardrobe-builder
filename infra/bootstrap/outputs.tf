output "state_bucket" {
  description = "S3 bucket holding Terraform remote state. Put this in each env's backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table for state locking. Put this in each env's backend.hcl."
  value       = aws_dynamodb_table.locks.name
}

output "ci_role_arn" {
  description = "IAM role ARN for GitHub Actions to assume via OIDC. Set as the AWS_ROLE_ARN repo variable / secret."
  value       = aws_iam_role.ci.arn
}

output "github_oidc_provider_arn" {
  description = "The GitHub OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "ci_deploy_policy_arn" {
  description = "Least-privilege deploy policy attached to the CI role (null when use_power_user_access = true)."
  value       = var.use_power_user_access ? null : aws_iam_policy.ci_deploy[0].arn
}

output "deploy_guardrail_policy_arn" {
  description = "Deny policy that blocks infra mutation outside the deploy role. Attach to human IAM groups (guardrail_attach_group_names) to enforce."
  value       = aws_iam_policy.deploy_guardrail.arn
}

output "deploy_guardrail_enforced_on" {
  description = "IAM groups currently subject to the guardrail (empty = created but not enforced)."
  value       = var.guardrail_attach_group_names
}
