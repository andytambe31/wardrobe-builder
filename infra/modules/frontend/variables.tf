variable "bucket_name" {
  description = "Globally-unique S3 bucket name for the static site."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_100 = NA/EU only, cheapest)."
  type        = string
  default     = "PriceClass_100"
}

variable "domain_aliases" {
  description = "Custom domain aliases (requires acm_certificate_arn). Empty = default *.cloudfront.net."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM cert ARN in us-east-1 for a custom domain. Empty = CloudFront default cert."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
