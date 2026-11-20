data "aws_caller_identity" "current" {}

module "dynamodb" {
  source     = "./modules/dynamodb"
  table_name = "${var.project_name}-files"
}

module "s3" {
  source          = "./modules/s3"
  bucket_name     = "${var.project_name}-files-${data.aws_caller_identity.current.account_id}"
  allowed_origins = var.allowed_origins
}

module "sqs" {
  source      = "./modules/sqs"
  queue_name  = "${var.project_name}-uploads"
  bucket_name = module.s3.bucket_name
  bucket_arn  = module.s3.bucket_arn
}
