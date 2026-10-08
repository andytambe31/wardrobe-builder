variable "name" {
  description = "Lambda function name."
  type        = string
}

variable "source_dir" {
  description = "Directory containing the Lambda source to zip."
  type        = string
}

variable "handler" {
  description = "Lambda handler (file.export)."
  type        = string
  default     = "index.handler"
}

variable "runtime" {
  type    = string
  default = "nodejs20.x"
}

variable "memory_size" {
  type    = number
  default = 256
}

variable "timeout" {
  type    = number
  default = 10
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "table_name" {
  description = "DynamoDB table name (exposed to the function as TABLE_NAME)."
  type        = string
}

variable "table_arn" {
  description = "DynamoDB table ARN for the scoped IAM policy."
  type        = string
}

variable "table_gsi_arn" {
  description = "GSI1 ARN for the scoped IAM policy (optional)."
  type        = string
  default     = ""
}

variable "enable_media" {
  description = "Grant object access to media_bucket_arn under users/*. A bool so the decision is known at plan time (the ARN isn't until the bucket exists)."
  type        = bool
  default     = false
}

variable "media_bucket_arn" {
  description = "Media bucket ARN (used when enable_media is true)."
  type        = string
  default     = ""
}

variable "extra_statements" {
  description = "Additional IAM Allow statements for the function role."
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "environment" {
  description = "Extra environment variables for the function."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
