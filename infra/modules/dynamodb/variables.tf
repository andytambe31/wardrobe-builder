variable "name" {
  description = "DynamoDB table name."
  type        = string
}

variable "deletion_protection" {
  description = "Guard against accidental table deletion (recommended true in prod)."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
