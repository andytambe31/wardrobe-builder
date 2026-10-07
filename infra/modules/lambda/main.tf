terraform {
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.40" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

# Zip the API source at plan time. Pointing at a directory of plain .mjs keeps
# this build-step-free (matches the app's philosophy); swap for a CI artifact
# (filename var) once you add a bundler.
data "archive_file" "code" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${var.name}.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# Logs + X-Ray + scoped DynamoDB access to just this table and its GSI.
data "aws_iam_policy_document" "perms" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
  statement {
    sid       = "Xray"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
  statement {
    sid    = "Dynamo"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
      "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem", "dynamodb:ConditionCheckItem"
    ]
    resources = compact([var.table_arn, var.table_gsi_arn])
  }
}

resource "aws_iam_role_policy" "perms" {
  name   = "${var.name}-perms"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.perms.json
}

resource "aws_lambda_function" "this" {
  function_name    = var.name
  role             = aws_iam_role.lambda.arn
  runtime          = var.runtime
  handler          = var.handler
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  memory_size      = var.memory_size
  timeout          = var.timeout

  environment {
    variables = merge({
      TABLE_NAME = var.table_name
    }, var.environment)
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
  tags       = var.tags
}
