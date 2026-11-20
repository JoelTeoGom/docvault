#!/usr/bin/env bash
set -euo pipefail

table=$(terraform -chdir=infra output -raw table_name)
bucket=$(terraform -chdir=infra output -raw bucket_name)
access_key=$(aws configure get aws_access_key_id)
secret_key=$(aws configure get aws_secret_access_key)

jq -n --arg table "$table" --arg bucket "$bucket" --arg access_key "$access_key" \
  --arg secret_key "$secret_key" --arg jwt_secret "$TF_VAR_jwt_secret" '
  {TABLE: $table, S3_BUCKET: $bucket, AWS_ACCESS_KEY_ID: $access_key, AWS_SECRET_ACCESS_KEY: $secret_key,
    AWS_ENDPOINT_URL: "https://localhost:9297", AWS_CA_BUNDLE: "/var/task/ca.pem"} as $common
  | {ApiFunction: ($common + {JWT_SECRET: $jwt_secret}), WorkerFunction: $common}' > build/sam-env.json

for function in api worker; do
  install -m 644 "$(dirname "$AWS_CA_BUNDLE")/ca.pem" "build/$function/ca.pem"
done
