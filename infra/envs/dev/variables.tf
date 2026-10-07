variable "region" {
  type    = string
  default = "us-east-1"
}

variable "app_origins" {
  description = "Web origins for API CORS (scheme + host, no path), e.g. https://andytambe31.github.io."
  type        = list(string)
  default     = ["https://andytambe31.github.io", "http://localhost:8099"]
}

variable "auth_callback_urls" {
  description = "Exact OAuth redirect URLs on the Cognito app client (full app URL incl. path)."
  type        = list(string)
  default     = ["https://andytambe31.github.io/wardrobe-builder/", "http://localhost:8099/"]
}

variable "auth_logout_urls" {
  description = "OAuth sign-out redirect URLs (defaults to the callback URLs)."
  type        = list(string)
  default     = []
}

variable "enable_frontend" {
  description = "Host the PWA on S3+CloudFront in dev too."
  type        = bool
  default     = false
}

variable "allowed_subs" {
  description = "Cognito subject IDs allowed into the app (the single-user gate)."
  type        = list(string)
  default     = []
}

variable "allowed_emails" {
  description = "Emails allowed into the app (case-insensitive)."
  type        = list(string)
  default     = []
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "budget_limit_usd" {
  type    = number
  default = 5
}
