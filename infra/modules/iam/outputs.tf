output "api_role_arn" {
  value = aws_iam_role.api.arn
}

output "worker_role_arn" {
  value = aws_iam_role.worker.arn
}

output "sweeper_role_arn" {
  value = aws_iam_role.sweeper.arn
}
