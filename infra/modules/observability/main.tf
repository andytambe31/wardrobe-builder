terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.40" }
  }
}

# Alerts go to an SNS topic; subscribe an email if provided.
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda errors.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-lambda-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = var.lambda_function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# Worker errors and dead-lettered jobs. Count'd on a plain bool so the decision
# is known at plan time.
resource "aws_cloudwatch_metric_alarm" "worker_errors" {
  count               = var.enable_worker_alarms ? 1 : 0
  alarm_name          = "${var.name}-worker-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = var.worker_function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# Any message in the DLQ is a job that failed every retry — always worth a look.
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  count               = var.enable_worker_alarms ? 1 : 0
  alarm_name          = "${var.name}-jobs-dlq"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { QueueName = var.dlq_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# API Gateway 5xx.
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name}-api-5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { ApiId = var.api_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# DynamoDB throttling (read or write).
resource "aws_cloudwatch_metric_alarm" "ddb_throttle" {
  alarm_name          = "${var.name}-ddb-throttle"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ThrottledRequests"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { TableName = var.table_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# A monthly cost guardrail so a mistake can't quietly run up a bill. Account-wide
# (no cost filter), so it catches ANY unexpected spend, not just this app's.
#
# Notifications are layered to catch a cost climb EARLY rather than only at the
# limit:
#   • ACTUAL 50%     — an unexpected rise well before the cap (the app should sit
#                      near a couple of dollars, so ~half the budget is a signal).
#   • ACTUAL 80/100% — approaching / at the limit.
#   • FORECASTED 100% — AWS projects the month will END over budget: the earliest
#                       warning that spend is TRENDING up (e.g. a runaway resource
#                       from a misconfiguration), days before you'd actually hit it.
locals {
  budget_notifications = var.alert_email == "" ? [] : [
    { threshold = 50, type = "ACTUAL" },
    { threshold = 80, type = "ACTUAL" },
    { threshold = 100, type = "ACTUAL" },
    { threshold = 100, type = "FORECASTED" },
  ]
}

resource "aws_budgets_budget" "monthly" {
  count        = var.budget_limit_usd > 0 ? 1 : 0
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = local.budget_notifications
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = [var.alert_email]
    }
  }
}
