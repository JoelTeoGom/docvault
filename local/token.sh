#!/usr/bin/env bash
set -euo pipefail

user_id=${1:-local-user}

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

header=$(printf '{"alg":"HS256","typ":"JWT"}' | base64url)
payload=$(printf '{"user_id":"%s","role":"user","exp":%d}' "$user_id" "$(($(date +%s) + 3600))" | base64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -hmac "$TF_VAR_jwt_secret" -binary | base64url)

printf '%s.%s.%s\n' "$header" "$payload" "$signature"
