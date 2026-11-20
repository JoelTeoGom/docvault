variable "project_name" {
  description = "Prefix for the schedule and its role."
  type        = string
}

variable "schedule_expression" {
  description = "When the target runs, as a rate() or cron() expression."
  type        = string
}

variable "lambda_arn" {
  description = "ARN of the Lambda the schedule invokes."
  type        = string
}
