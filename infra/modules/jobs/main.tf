terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.40" }
  }
}

# Background job queue. API Gateway caps a request at 30s, and AI work (photo
# analysis, outfit generation) can run longer, so the API enqueues a job and
# returns at once; the worker Lambda drains the queue with a long timeout and
# the client polls for the result. Messages that fail max_receive_count times
# land in the dead-letter queue (alarmed in modules/observability) instead of
# retrying forever.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 days, the max, to leave time to inspect
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue" "jobs" {
  name = "${var.name}-jobs"
  # AWS guidance for Lambda event sources: at least 6x the function timeout, so
  # an in-flight message isn't redelivered while the worker is still on it.
  visibility_timeout_seconds = var.worker_timeout_seconds * 6
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # long polling
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
  tags = var.tags
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.jobs.arn]
  })
}
