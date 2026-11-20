#!/usr/bin/env bash
set -uo pipefail

# Uses docvault as a client would, against the emulator, and checks every answer.
# The SAM network flags are passed through to every sam command.

base=http://127.0.0.1:3001
work=build/e2e
table=$(terraform -chdir=infra output -raw table_name)
bucket=$(terraform -chdir=infra output -raw bucket_name)
queue_url=$(terraform -chdir=infra output -raw queue_url)
run_id=$(date +%s)
passed=0
failed=0

mkdir -p "$work"

check() {
  if [ "$2" = "$3" ]; then
    passed=$((passed + 1))
    printf '  ok    %s\n' "$1"
  else
    failed=$((failed + 1))
    printf '  FAIL  %s: expected %s, got %s\n' "$1" "$2" "$3"
  fi
}

section() { printf '\n%s\n' "$1"; }

api() {
  local method=$1 path=$2 token=$3 body=${4:-}
  if [ -n "$body" ]; then
    curl -s -o "$work/response.json" -w '%{http_code}' -X "$method" "$base$path" -H "Authorization: Bearer $token" -d "$body"
  else
    curl -s -o "$work/response.json" -w '%{http_code}' -X "$method" "$base$path" -H "Authorization: Bearer $token"
  fi
}

response() { jq -r "$1" "$work/response.json"; }

create_file() {
  api POST /files "$1" "{\"filename\":\"$2\",\"size\":$3,\"mime\":\"application/pdf\"}" >/dev/null
  response '.file.id'
}

upload() {
  curl -s -o /dev/null -w '%{http_code}' --cacert "$(dirname "$AWS_CA_BUNDLE")/ca.pem" -X PUT \
    -H "Content-Type: $1" --data-binary "@$2" "$(response '.presigned_url')"
}

record() {
  aws dynamodb get-item --table-name "$table" --query "Item.$3" --output text \
    --key "{\"PK\":{\"S\":\"USER#$1\"},\"SK\":{\"S\":\"FILE#$2\"}}"
}

object() {
  aws s3api head-object --bucket "$bucket" --key "users/$1/$2.pdf" >/dev/null 2>&1 && echo present || echo absent
}

listed_status() {
  api GET /files "$1" >/dev/null
  jq -r --arg id "$2" '[.items[] | select(.id == $id) | .status][0] // "absent"' "$work/response.json"
}

age() {
  local seconds=$(($(date +%s) - 7200))
  aws dynamodb update-item --table-name "$table" \
    --key "{\"PK\":{\"S\":\"USER#$1\"},\"SK\":{\"S\":\"FILE#$2\"}}" \
    --update-expression "SET $3 = :past, gsiSK = :past" \
    --expression-attribute-values "{\":past\":{\"N\":\"$seconds\"}}"
}

queued_messages() {
  aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names ApproximateNumberOfMessages \
    --query Attributes.ApproximateNumberOfMessages --output text
}

# S3 delivers the event a moment after the upload, so wait for it before draining.
drain_queue() {
  for _ in $(seq 1 15); do
    [ "$(queued_messages)" != 0 ] && break
    sleep 1
  done
  for _ in 1 2 3 4 5; do
    ./local/worker.sh "$@" >"$work/worker.log" 2>&1
    grep -q "the queue is empty" "$work/worker.log" && return
  done
}

run_sweeper() {
  echo '{}' | sam local invoke SweeperFunction --template local/template.yaml --env-vars build/sam-env.json \
    --event - --region "$AWS_REGION" "$@" >"$work/sweeper.log" 2>&1
}

printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' >"$work/report.pdf"
pdf_size=$(wc -c <"$work/report.pdf" | tr -d ' ')

alice=alice-$run_id
bob=bob-$run_id
alice_token=$(./local/token.sh "$alice")
bob_token=$(./local/token.sh "$bob")

sam local start-api --template local/template.yaml --env-vars build/sam-env.json --region "$AWS_REGION" \
  --port 3001 --warm-containers LAZY "$@" >"$work/sam.log" 2>&1 &
sam_pid=$!
trap 'kill $sam_pid 2>/dev/null; wait $sam_pid 2>/dev/null' EXIT
for _ in $(seq 1 60); do
  curl -s -o /dev/null "$base/files" && break
  sleep 1
done

drain_queue "$@"

section "Authentication"
check "no token" 401 "$(api GET /files "")"
check "expired token" 401 "$(api GET /files "$(./local/token.sh "$alice" -60)")"
check "token signed with another secret" 401 "$(api GET /files "$(TF_VAR_jwt_secret=wrong ./local/token.sh "$alice")")"
check "valid token" 200 "$(api GET /files "$alice_token")"

section "Validation"
check "body that is not json" 400 "$(api POST /files "$alice_token" 'not json')"
check "missing filename" 400 "$(api POST /files "$alice_token" '{"size":10,"mime":"application/pdf"}')"
check "not a pdf" 400 "$(api POST /files "$alice_token" '{"filename":"a.txt","size":10,"mime":"text/plain"}')"
check "larger than 50 MB" 413 "$(api POST /files "$alice_token" '{"filename":"a.pdf","size":52428801,"mime":"application/pdf"}')"
check "unknown file" 404 "$(api GET /files/does-not-exist "$alice_token")"

section "Upload and download"
report_body=$(printf '{"filename":"report.pdf","size":%s,"mime":"application/pdf"}' "$pdf_size")
check "create" 201 "$(api POST /files "$alice_token" "$report_body")"
report=$(response '.file.id')
cp "$work/response.json" "$work/created.json"
check "created as pending" pending "$(response '.file.status')"
check "download before the upload" 409 "$(api GET "/files/$report" "$alice_token")"
cp "$work/created.json" "$work/response.json"
check "upload with a different content type" 403 "$(upload text/plain "$work/report.pdf")"
check "upload" 200 "$(upload application/pdf "$work/report.pdf")"
drain_queue "$@"
check "worker confirms the upload" uploaded "$(record "$alice" "$report" status.S)"
check "download" 200 "$(api GET "/files/$report" "$alice_token")"
curl -s --cacert "$(dirname "$AWS_CA_BUNDLE")/ca.pem" -o "$work/downloaded.pdf" "$(response '.presigned_url')"
check "downloaded bytes match" same "$(cmp -s "$work/report.pdf" "$work/downloaded.pdf" && echo same || echo different)"
check "listed as uploaded" uploaded "$(listed_status "$alice_token" "$report")"

section "Another user"
check "cannot read it" 404 "$(api GET "/files/$report" "$bob_token")"
check "cannot delete it" 404 "$(api DELETE "/files/$report" "$bob_token")"
check "cannot restore it" 404 "$(api POST "/files/$report/restore" "$bob_token")"
check "does not see it" absent "$(listed_status "$bob_token" "$report")"

section "Trash, restore and delete"
check "restore a file that is not in the trash" 409 "$(api POST "/files/$report/restore" "$alice_token")"
check "move to the trash" 204 "$(api DELETE "/files/$report" "$alice_token")"
check "download from the trash" 410 "$(api GET "/files/$report" "$alice_token")"
check "listed as trashed" trashed "$(listed_status "$alice_token" "$report")"
check "restore" 200 "$(api POST "/files/$report/restore" "$alice_token")"
check "restored as uploaded" uploaded "$(response '.file.status')"
check "download after the restore" 200 "$(api GET "/files/$report" "$alice_token")"
check "trash again" 204 "$(api DELETE "/files/$report" "$alice_token")"
check "delete for good" 204 "$(api DELETE "/files/$report" "$alice_token")"
check "record is deleted" deleted "$(record "$alice" "$report" status.S)"
check "object is gone" absent "$(object "$alice" "$report")"
check "record expires through the ttl" yes "$([ "$(record "$alice" "$report" expiresAt.N)" != None ] && echo yes || echo no)"
check "no longer listed" absent "$(listed_status "$alice_token" "$report")"
check "delete it again" 409 "$(api DELETE "/files/$report" "$alice_token")"

section "Rejected upload"
fake=$(create_file "$alice_token" fake.pdf 1000)
check "delete while the upload is pending" 409 "$(api DELETE "/files/$fake" "$alice_token")"
aws s3api put-object --bucket "$bucket" --key "users/$alice/$fake.pdf" --body "$work/report.pdf" \
  --content-type application/pdf >/dev/null
drain_queue "$@"
check "size mismatch is rejected" rejected "$(record "$alice" "$fake" status.S)"
check "rejected object is deleted" absent "$(object "$alice" "$fake")"
check "rejected file is not listed" absent "$(listed_status "$alice_token" "$fake")"

section "Pagination"
for name in one two three; do create_file "$bob_token" "$name.pdf" 10 >/dev/null; done
api GET "/files?limit=2" "$bob_token" >/dev/null
check "first page" 2 "$(response '.items | length')"
cursor=$(response '.next_cursor')
check "second page" 1 "$(curl -s -G "$base/files" -H "Authorization: Bearer $bob_token" \
  --data-urlencode limit=2 --data-urlencode "cursor=$cursor" | jq '.items | length')"

section "Sweeper"
abandoned=$(create_file "$alice_token" abandoned.pdf 10)
age "$alice" "$abandoned" createdAt

lost=$(create_file "$alice_token" lost-event.pdf "$pdf_size")
check "upload whose event gets lost" 200 "$(upload application/pdf "$work/report.pdf")"
sleep 2
aws sqs purge-queue --queue-url "$queue_url"
age "$alice" "$lost" createdAt

expired=$(create_file "$alice_token" expired-trash.pdf "$pdf_size")
upload application/pdf "$work/report.pdf" >/dev/null
drain_queue "$@"
api DELETE "/files/$expired" "$alice_token" >/dev/null
age "$alice" "$expired" trashExpiresAt

recent=$(create_file "$alice_token" recent-trash.pdf "$pdf_size")
upload application/pdf "$work/report.pdf" >/dev/null
drain_queue "$@"
api DELETE "/files/$recent" "$alice_token" >/dev/null

fresh=$(create_file "$alice_token" uploading-now.pdf 10)

run_sweeper "$@"
check "sweeper run" 0 "$(grep -c '"errorMessage"' "$work/sweeper.log")"
check "abandoned upload: record removed" 404 "$(api GET "/files/$abandoned" "$alice_token")"
check "lost event: promoted to uploaded" uploaded "$(record "$alice" "$lost" status.S)"
check "lost event: downloadable" 200 "$(api GET "/files/$lost" "$alice_token")"
check "expired trash: deleted for good" deleted "$(record "$alice" "$expired" status.S)"
check "expired trash: object gone" absent "$(object "$alice" "$expired")"
check "trash within retention: untouched" trashed "$(record "$alice" "$recent" status.S)"
check "trash within retention: object kept" present "$(object "$alice" "$recent")"
check "upload in progress: untouched" pending "$(record "$alice" "$fresh" status.S)"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
