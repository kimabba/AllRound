#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"
QA_PASSWORD="QaLocal-Only-2026!"

cd "$ROOT"
bash scripts/qa/assert_local_supabase.sh >/dev/null

# 키와 토큰은 메모리에서만 사용하고 stdout/stderr 또는 artifact에 남기지 않는다.
status_env="$($SUPABASE_BIN status -o env 2>/dev/null)"
api_url="$(awk -F= '$1 == "API_URL" {gsub(/^\"|\"$/, "", $2); print $2}' <<<"$status_env")"
anon_key="$(awk -F= '$1 == "ANON_KEY" {sub(/^[^=]*=/, ""); gsub(/^\"|\"$/, ""); print}' <<<"$status_env")"
unset status_env

personas=(
  qa-admin@allround.invalid
  qa-owner@allround.invalid
  qa-manager@allround.invalid
  qa-delegate@allround.invalid
  qa-member@allround.invalid
  qa-applicant@allround.invalid
  qa-offender@allround.invalid
  qa-empty@allround.invalid
)

for email in "${personas[@]}"; do
  payload="$(printf '{\"email\":\"%s\",\"password\":\"%s\"}' "$email" "$QA_PASSWORD")"
  if ! curl --fail --silent --show-error \
    --connect-timeout 3 \
    --max-time 10 \
    --request POST \
    --header "apikey: $anon_key" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    "$api_url/auth/v1/token?grant_type=password" >/dev/null; then
    echo "로그인 실패: $email" >&2
    exit 1
  fi
done

unset anon_key payload QA_PASSWORD
echo "합성 계정 ${#personas[@]}명의 로컬 이메일 로그인 확인 완료"
