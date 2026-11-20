variable "function_name" {
  description = "Name of the function."
  type        = string
}

variable "role_arn" {
  description = "Role the function runs with."
  type        = string
}

variable "package_path" {
  description = "Zip holding the bootstrap binary."
  type        = string
}

variable "environment" {
  description = "Environment variables of the function."
  type        = map(string)
  default     = {}
}

variable "memory_size" {
  description = "Memory in MB, which also scales the CPU."
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Seconds before an invocation is stopped."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Days the function logs are kept."
  type        = number
}
