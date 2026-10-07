variable "region" {
  type    = string
  default = "us-east-1"
}

variable "app_origins" {
  description = "Web origins for API CORS (scheme + host, no path), e.g. https://andytambe31.github.io."
  type        = list(string)
  default     = ["https://andytambe31.github.io"]
}

variable "auth_callback_urls" {
  description = "Exact OAuth redirect URLs on the Cognito app client (full app URL incl. path)."
  type        = list(string)
  default     = ["https://andytambe31.github.io/wardrobe-builder/"]
}

variable "auth_logout_urls" {
  description = "OAuth sign-out redirect URLs (defaults to the callback URLs)."
  type        = list(string)
  default     = []
}

variable "enable_frontend" {
  description = "Host the PWA on S3+CloudFront (vs staying on GitHub Pages)."
  type        = bool
  default     = true
}

variable "frontend_domain_aliases" {
  type    = list(string)
  default = []
}

variable "frontend_acm_certificate_arn" {
  description = "ACM cert ARN in us-east-1 for the custom domain (optional)."
  type        = string
  default     = ""
}

variable "cognito_domain_prefix" {
  description = "Cognito Hosted UI domain prefix (globally unique). Optional."
  type        = string
  default     = ""
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

variable "custom_domain" {
  description = "Custom frontend domain, e.g. wardrobe.aniruddhatambe.dev. Empty = none."
  type        = string
  default     = ""
}

variable "custom_domain_ready" {
  description = "Set true after the ACM cert is validated, to attach the domain to CloudFront + Cognito."
  type        = bool
  default     = false
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "budget_limit_usd" {
  type    = number
  default = 15
}
