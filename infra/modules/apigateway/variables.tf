variable "name" {
  type = string
}

variable "lambda_invoke_arn" {
  type = string
}

variable "lambda_function_name" {
  type = string
}

variable "cognito_issuer" {
  type = string
}

variable "cognito_client_id" {
  type = string
}

variable "cors_allow_origins" {
  description = "Allowed CORS origins (the app's web origins)."
  type        = list(string)
  default     = ["*"]
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "throttle_burst" {
  type    = number
  default = 20
}

variable "throttle_rate" {
  type    = number
  default = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
