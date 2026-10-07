variable "name" {
  description = "Cognito user pool name."
  type        = string
}

variable "mfa_configuration" {
  description = "OFF | ON | OPTIONAL."
  type        = string
  default     = "OPTIONAL"
}

variable "callback_urls" {
  description = "OAuth callback URLs (app origins). Empty disables the OAuth/hosted-UI flow."
  type        = list(string)
  default     = []
}

variable "logout_urls" {
  description = "OAuth logout URLs."
  type        = list(string)
  default     = []
}

variable "hosted_ui_domain_prefix" {
  description = "Prefix for the Cognito Hosted UI domain (globally unique). Empty = no hosted UI."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
