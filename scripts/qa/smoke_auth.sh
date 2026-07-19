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

assert_signup_rejected() {
  local label="$1"
  local request_payload="$2"
  local expected_marker="$3"
  local response status body

  response="$(curl --silent --show-error \
    --connect-timeout 3 \
    --max-time 10 \
    --request POST \
    --header "apikey: $anon_key" \
    --header "Content-Type: application/json" \
    --data "$request_payload" \
    --write-out $'\n%{http_code}' \
    "$api_url/auth/v1/signup")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ ! "$status" =~ ^4[0-9][0-9]$ ]]; then
    echo "$label: 가입 전 서버 거부를 기대했지만 HTTP $status" >&2
    return 1
  fi
  if [[ "$body" != *"$expected_marker"* ]]; then
    echo "$label: 예상한 안전 오류 코드가 응답에 없습니다." >&2
    return 1
  fi
}

assert_signup_rejected \
  "생년월일 누락" \
  '{"email":"qa-missing-birth@allround.invalid","password":"QaLocal-Only-2026!"}' \
  "BIRTH_DATE_REQUIRED"
assert_signup_rejected \
  "만 14세 미만" \
  '{"email":"qa-underage@allround.invalid","password":"QaLocal-Only-2026!","data":{"birth_date":"2020-01-01"}}' \
  "MINOR_NOT_ALLOWED"
assert_signup_rejected \
  "생년월일 형식 오류" \
  '{"email":"qa-invalid-birth@allround.invalid","password":"QaLocal-Only-2026!","data":{"birth_date":"not-a-date"}}' \
  "INVALID_BIRTH_DATE"

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
echo "가입 전 연령 거부 3건과 합성 계정 ${#personas[@]}명의 로컬 이메일 로그인 확인 완료"
