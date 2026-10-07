variable "bucket_name" {
  description = "Globally-unique S3 bucket name for user media."
  type        = string
}

variable "cors_allow_origins" {
  description = "Web origins allowed to upload/download directly (the app's origins)."
  type        = list(string)
  default     = []
}

# A plain bool rather than length(cors_allow_origins) > 0: the origin list can
# include the CloudFront domain, which is unknown until apply, and count must be
# known at plan time.
variable "enable_cors" {
  description = "Create the bucket CORS rule (cors_allow_origins must then be non-empty)."
  type        = bool
  default     = false
}

variable "noncurrent_version_days" {
  description = "Days to keep overwritten/deleted object versions before they expire."
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
