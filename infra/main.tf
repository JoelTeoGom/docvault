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

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
  table_arn    = module.dynamodb.table_arn
  bucket_arn   = module.s3.bucket_arn
  queue_arn    = module.sqs.queue_arn
}

module "api_lambda" {
  source             = "./modules/lambda"
  function_name      = "${var.project_name}-api"
  role_arn           = module.iam.api_role_arn
  package_path       = "${path.root}/../build/api.zip"
  log_retention_days = var.log_retention_days

  environment = {
    TABLE      = module.dynamodb.table_name
    S3_BUCKET  = module.s3.bucket_name
    JWT_SECRET = var.jwt_secret
  }
}

module "worker_lambda" {
  source             = "./modules/lambda"
  function_name      = "${var.project_name}-worker"
  role_arn           = module.iam.worker_role_arn
  package_path       = "${path.root}/../build/worker.zip"
  log_retention_days = var.log_retention_days

  environment = {
    TABLE     = module.dynamodb.table_name
    S3_BUCKET = module.s3.bucket_name
  }
}

resource "aws_lambda_event_source_mapping" "uploads" {
  event_source_arn        = module.sqs.queue_arn
  function_name           = module.worker_lambda.function_arn
  enabled                 = var.queue_trigger_enabled
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 2
  }
}

module "apigateway" {
  source               = "./modules/apigateway"
  project_name         = var.project_name
  allowed_origins      = var.allowed_origins
  lambda_invoke_arn    = module.api_lambda.invoke_arn
  lambda_function_name = module.api_lambda.function_name
}

module "sweeper_lambda" {
  source             = "./modules/lambda"
  function_name      = "${var.project_name}-sweeper"
  role_arn           = module.iam.sweeper_role_arn
  package_path       = "${path.root}/../build/sweeper.zip"
  log_retention_days = var.log_retention_days
  timeout            = 300

  environment = {
    TABLE     = module.dynamodb.table_name
    S3_BUCKET = module.s3.bucket_name
  }
}

module "eventbridge" {
  source              = "./modules/eventbridge"
  project_name        = var.project_name
  schedule_expression = var.sweeper_schedule
  lambda_arn          = module.sweeper_lambda.function_arn
}
