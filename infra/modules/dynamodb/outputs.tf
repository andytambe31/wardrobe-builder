output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "gsi1_arn" {
  description = "ARN of GSI1 (for IAM policies that need index access)."
  value       = "${aws_dynamodb_table.this.arn}/index/GSI1"
}
