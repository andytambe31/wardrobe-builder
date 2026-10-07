output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Base URL of the HTTP API ($default stage)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}
