output "table_name" {
  value = module.dynamodb.table_name
}

output "bucket_name" {
  value = module.s3.bucket_name
}

output "queue_url" {
  value = module.sqs.queue_url
}

output "api_endpoint" {
  value = module.apigateway.api_endpoint
}
