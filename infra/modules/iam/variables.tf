variable "project_name" {
  description = "Prefix for the role names."
  type        = string
}

variable "table_arn" {
  description = "ARN of the files table."
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the files bucket."
  type        = string
}

variable "queue_arn" {
  description = "ARN of the upload queue the worker consumes."
  type        = string
}
