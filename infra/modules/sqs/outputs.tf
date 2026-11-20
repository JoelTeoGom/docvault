output "queue_arn" {
  value = aws_sqs_queue.uploads.arn
}

output "queue_url" {
  value = aws_sqs_queue.uploads.id
}

output "dead_letter_queue_url" {
  value = aws_sqs_queue.dead_letter.id
}
