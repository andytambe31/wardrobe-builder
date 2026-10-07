variable "project" {
  type    = string
  default = "wardrobe-builder"
}

variable "env" {
  description = "Environment name (dev | prod)."
  type        = string
}

variable "api_source_dir" {
  description = "Path to the Lambda API source directory (relative to the env root)."
  type        = string
}

variable "app_origins" {
  description = "Web origins for API CORS (scheme + host, no path), e.g. https://andytambe31.github.io."
  type        = list(string)
  default     = []
}

variable "auth_callback_urls" {
  description = "Exact OAuth redirect URLs registered on the Cognito app client (full app URL incl. path, e.g. https://andytambe31.github.io/wardrobe-builder/). Empty disables the Hosted UI flow."
  type        = list(string)
  default     = []
}

variable "auth_logout_urls" {
  description = "OAuth sign-out redirect URLs. Defaults to auth_callback_urls when empty."
  type        = list(string)
  default     = []
}

variable "cognito_domain_prefix" {
  description = "Cognito Hosted UI domain prefix (globally unique). Empty = none."
  type        = string
  default     = ""
}

variable "enable_frontend" {
  description = "Provision S3 + CloudFront to host the PWA on AWS (vs staying on GitHub Pages)."
  type        = bool
  default     = true
}

variable "frontend_domain_aliases" {
  type    = list(string)
  default = []
}

variable "frontend_acm_certificate_arn" {
  type    = string
  default = ""
}

variable "custom_domain" {
  description = "Custom domain for the frontend (e.g. wardrobe.aniruddhatambe.dev). Empty = none. Setting it requests an ACM cert; the domain is attached to CloudFront only when custom_domain_ready is also true."
  type        = string
  default     = ""
}

variable "custom_domain_ready" {
  description = "Flip true AFTER the ACM cert is validated (DNS record added + issued). Attaches the custom domain + cert to CloudFront and adds it to Cognito callbacks/CORS."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "DynamoDB deletion protection (true in prod)."
  type        = bool
  default     = true
}

variable "allowed_subs" {
  description = "Cognito subject IDs allowed past the app authz gate. The strong single-user allow-list."
  type        = list(string)
  default     = []
}

variable "allowed_emails" {
  description = "Emails allowed past the app authz gate (case-insensitive). Alternative/addition to allowed_subs."
  type        = list(string)
  default     = []
}

variable "require_allowlist" {
  description = "Fail closed: reject every principal when no allow-list is configured, rather than admitting any pool member."
  type        = bool
  default     = true
}

variable "media_max_bytes" {
  description = "Largest photo upload the API will sign for, in bytes (enforced by S3 via the POST policy)."
  type        = number
  default     = 10485760
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "budget_limit_usd" {
  type    = number
  default = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
