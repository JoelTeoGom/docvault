variable "bucket_name" {
  description = "Name of the bucket holding the uploaded files."
  type        = string
}

variable "allowed_origins" {
  description = "Browser origins allowed to upload and download with presigned URLs."
  type        = list(string)
}
