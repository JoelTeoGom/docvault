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
