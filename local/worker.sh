#!/usr/bin/env bash
set -euo pipefail

queue_url=$(terraform -chdir=infra output -raw queue_url)
queue_arn=$(aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn --query Attributes.QueueArn --output text)

messages=$(aws sqs receive-message --queue-url "$queue_url" --max-number-of-messages 10 --wait-time-seconds 5 --output json)
if [ -z "$messages" ]; then
  echo "the queue is empty"
  exit 0
fi

jq --arg arn "$queue_arn" --arg region "$AWS_REGION" '{Records: [.Messages[] | {
    messageId: .MessageId, receiptHandle: .ReceiptHandle, body: .Body, md5OfBody: .MD5OfBody,
    attributes: {}, messageAttributes: {}, eventSource: "aws:sqs", eventSourceARN: $arn, awsRegion: $region}]}' \
  <<<"$messages" > build/worker-event.json

response=$(sam local invoke WorkerFunction --template local/template.yaml --env-vars build/sam-env.json \
  --event build/worker-event.json --region "$AWS_REGION" "$@" | tail -n 1)
echo "worker response: $response"

failed_ids=$(jq -r '(.batchItemFailures // [])[].itemIdentifier' <<<"$response")

# Lambda deletes the messages it did not report as failed; failed ones come back after the visibility timeout.
jq -r '.Records[] | [.messageId, .receiptHandle] | @tsv' build/worker-event.json |
  while IFS=$'\t' read -r message_id receipt_handle; do
    if ! grep -qx "$message_id" <<<"$failed_ids"; then
      aws sqs delete-message --queue-url "$queue_url" --receipt-handle "$receipt_handle"
    fi
  done
