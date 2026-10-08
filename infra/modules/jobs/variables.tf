variable "name" {
  description = "Name prefix for the queues."
  type        = string
}

variable "worker_timeout_seconds" {
  description = "Worker Lambda timeout; the queue visibility timeout is derived from it."
  type        = number
  validation {
    condition     = var.worker_timeout_seconds >= 1 && var.worker_timeout_seconds <= 900
    error_message = "Lambda timeouts are 1-900 seconds."
  }
}

variable "max_receive_count" {
  description = "Delivery attempts before a message moves to the DLQ."
  type        = number
  default     = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}
