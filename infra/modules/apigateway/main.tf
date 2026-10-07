terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.40" }
  }
}

# HTTP API (cheaper/simpler than REST API) fronting the Lambda. A public health
# route, and everything else behind a Cognito JWT authorizer.
resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"

  # CORS is handled entirely by the Lambda (it reflects the allow-listed origin on
  # every response, including a 204 for OPTIONS). We deliberately do NOT set an
  # API-level cors_configuration: with a catch-all `ANY /{proxy+}` behind a JWT
  # authorizer, the gateway's automatic CORS doesn't reliably answer the OPTIONS
  # preflight, so the preflight fell through to the authorizer and got 401 — which
  # broke every browser that didn't already have a cached preflight. The explicit
  # public OPTIONS route below routes preflight to the Lambda instead.

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Cognito JWT authorizer — validates the Bearer token's signature, issuer and
# audience (the app client id) on every guarded route.
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.name}-cognito"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = var.cognito_issuer
  }
}

# Public health check (no auth) — proves the wiring end to end.
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# CORS preflight — PUBLIC (no authorizer). A browser sends an unauthenticated
# OPTIONS before any cross-origin request with an Authorization header; it must
# not require auth. This explicit method route wins over `ANY` for OPTIONS, so
# the preflight reaches the Lambda (which returns 204 + CORS) instead of the
# authorizer (which returned 401 and broke the whole app in the browser).
resource "aws_apigatewayv2_route" "preflight" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "OPTIONS /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Everything else requires a valid Cognito JWT.
resource "aws_apigatewayv2_route" "proxy" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigw/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId     = "$context.requestId"
      ip            = "$context.identity.sourceIp"
      method        = "$context.httpMethod"
      route         = "$context.routeKey"
      status        = "$context.status"
      latencyMs     = "$context.responseLatency"
      integationErr = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = var.throttle_burst
    throttling_rate_limit  = var.throttle_rate
  }

  tags = var.tags
}

# Let this API invoke the Lambda.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
