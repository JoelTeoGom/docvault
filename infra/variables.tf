variable "project_name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "docvault"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Use lowercase letters, digits and hyphens only."
  }
}

variable "aws_region" {
  description = "Region for every resource."
  type        = string
  default     = "eu-west-1"
}

variable "s3_use_path_style" {
  description = "Address buckets as host/bucket instead of bucket.host. Only the local emulator needs it."
  type        = bool
  default     = false
}

variable "allowed_origins" {
  description = "Browser origins allowed to call the API and to use the presigned URLs."
  type        = list(string)
}

variable "jwt_secret" {
  description = "HMAC key that signs and validates the access tokens."
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "Days the function logs are kept."
  type        = number
  default     = 14
}

variable "queue_trigger_enabled" {
  description = "Whether the upload queue invokes the worker. Off locally, where the emulator cannot run it."
  type        = bool
  default     = true
}

variable "sweeper_schedule" {
  description = "When the sweeper runs, as an EventBridge Scheduler expression."
  type        = string
  default     = "rate(1 day)"
}
