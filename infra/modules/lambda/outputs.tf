output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "role_name" {
  value = aws_iam_role.lambda.name
}

output "invoke_arn" {
  description = "ARN used by API Gateway integration."
  value       = aws_lambda_function.this.invoke_arn
}
