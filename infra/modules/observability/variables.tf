variable "name" {
  type = string
}

variable "lambda_function_name" {
  type = string
}

variable "api_id" {
  type = string
}

variable "table_name" {
  type = string
}

variable "alert_email" {
  description = "Email for alarm + budget notifications. Empty = no email subscription."
  type        = string
  default     = ""
}

variable "budget_limit_usd" {
  description = "Monthly cost budget in USD (0 disables the budget)."
  type        = number
  default     = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
