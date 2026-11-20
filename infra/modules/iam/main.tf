locals {
  lambda_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "api" {
  name               = "${var.project_name}-api"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "api_logs" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api" {
  name = "files"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = var.table_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${var.bucket_arn}/*"
      },
    ]
  })
}

resource "aws_iam_role" "worker" {
  name               = "${var.project_name}-worker"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "worker_logs" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "worker" {
  name = "uploads"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.queue_arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = var.table_arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:DeleteObject"
        Resource = "${var.bucket_arn}/*"
      },
    ]
  })
}
