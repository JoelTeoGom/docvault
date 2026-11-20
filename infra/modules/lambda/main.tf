resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  role             = var.role_arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "bootstrap"
  filename         = var.package_path
  source_code_hash = filebase64sha256(var.package_path)
  memory_size      = var.memory_size
  timeout          = var.timeout

  environment {
    variables = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.function]
}
