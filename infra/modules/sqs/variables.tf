variable "queue_name" {
  description = "Name of the queue receiving the upload events."
  type        = string
}

variable "bucket_name" {
  description = "Bucket whose new objects are sent to the queue."
  type        = string
}

variable "bucket_arn" {
  description = "ARN of that bucket, the only sender the queue accepts."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "How long a received message stays hidden. At least six times the worker timeout."
  type        = number
  default     = 60
}

variable "max_receive_count" {
  description = "Receives before a message is moved to the dead letter queue."
  type        = number
  default     = 5
}
