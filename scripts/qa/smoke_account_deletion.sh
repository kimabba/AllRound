#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"
QA_PASSWORD="QaLocal-Only-2026!"

cd "$ROOT"
bash scripts/qa/assert_local_supabase.sh >/dev/null

# Local keys and tokens stay in memory and never reach stdout/stderr.
status_env="$($SUPABASE_BIN status -o env 2>/dev/null)"
api_url="$(awk -F= '$1 == "API_URL" {gsub(/^"|"$/, "", $2); print $2}' <<<"$status_env")"
anon_key="$(awk -F= '$1 == "ANON_KEY" {sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print}' <<<"$status_env")"
service_key="$(awk -F= '$1 == "SERVICE_ROLE_KEY" {sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print}' <<<"$status_env")"
unset status_env

request_code() {
  curl --silent --show-error \
    --connect-timeout 3 \
    --max-time 20 \
    --output /dev/null \
    --write-out '%{http_code}' \
    "$@"
}

expect_code() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ ! "$actual" =~ ^($expected)$ ]]; then
    echo "$label 실패: HTTP $actual" >&2
    exit 1
  fi
}

run_suffix="$(date +%s)-$$"
email="qa-delete-$run_suffix@allround.invalid"
object_name="qa-delete-$run_suffix.png"
user_id=''
access_token=''

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/allround-delete-smoke.XXXXXX")"
image_file="$temp_dir/pixel.png"
cleanup() {
  local body
  body="$(printf '{"prefixes":["%s"]}' "$object_name")"
  request_code \
    --request DELETE \
    --header "apikey: $service_key" \
    --header "Authorization: Bearer $service_key" \
    --header "Content-Type: application/json" \
    --data "$body" \
    "$api_url/storage/v1/object/club-logos" >/dev/null || true
  if [[ -n "$user_id" ]]; then
    request_code \
      --request DELETE \
      --header "apikey: $service_key" \
      --header "Authorization: Bearer $service_key" \
      "$api_url/auth/v1/admin/users/$user_id" >/dev/null || true
  fi
  rm -f "$image_file"
  rmdir "$temp_dir" 2>/dev/null || true
}
trap cleanup EXIT

printf '%s' \
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+NlpYVQAAAABJRU5ErkJggg==' \
  | openssl base64 -d -A >"$image_file"

create_payload="$(printf \
  '{"email":"%s","password":"%s","email_confirm":true,"user_metadata":{"display_name":"QA 삭제 테스트","birth_date":"1990-01-01"}}' \
  "$email" "$QA_PASSWORD")"
create_result="$(curl --fail --silent --show-error \
  --request POST \
  --header "apikey: $service_key" \
  --header "Authorization: Bearer $service_key" \
  --header "Content-Type: application/json" \
  --data "$create_payload" \
  "$api_url/auth/v1/admin/users")"
user_id="$(jq -er '.id' <<<"$create_result")"
unset create_result create_payload

code="$(request_code \
  --request PATCH \
  --header "apikey: $service_key" \
  --header "Authorization: Bearer $service_key" \
  --header "Content-Type: application/json" \
  --header "Prefer: return=minimal" \
  --data '{"birth_date":"1990-01-01"}' \
  "$api_url/rest/v1/users?id=eq.$user_id")"
expect_code "$code" '200|204' '합성 탈퇴 계정 연령 준비'

login_payload="$(printf '{"email":"%s","password":"%s"}' "$email" "$QA_PASSWORD")"
login_result="$(curl --fail --silent --show-error \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Content-Type: application/json" \
  --data "$login_payload" \
  "$api_url/auth/v1/token?grant_type=password")"
access_token="$(jq -er '.access_token' <<<"$login_result")"
unset login_result

code="$(request_code \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $access_token" \
  --header "Content-Type: image/png" \
  --data-binary "@$image_file" \
  "$api_url/storage/v1/object/club-logos/$object_name")"
expect_code "$code" '200|201' '탈퇴 전 공개 이미지 업로드'

code="$(request_code \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $access_token" \
  "$api_url/functions/v1/delete-account")"
expect_code "$code" '200' '계정 삭제 Edge Function'

code="$(request_code \
  --header "apikey: $anon_key" \
  "$api_url/storage/v1/object/public/club-logos/$object_name")"
expect_code "$code" '400|404' '탈퇴 후 공개 이미지 삭제'

code="$(request_code \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Content-Type: application/json" \
  --data "$login_payload" \
  "$api_url/auth/v1/token?grant_type=password")"
expect_code "$code" '400|401' '탈퇴 후 재로그인 차단'

user_rows="$(curl --fail --silent --show-error \
  --header "apikey: $service_key" \
  --header "Authorization: Bearer $service_key" \
  "$api_url/rest/v1/users?id=eq.$user_id&select=id")"
if [[ "$(jq 'length' <<<"$user_rows")" != '0' ]]; then
  echo '탈퇴 후 public.users 개인정보 행이 남았습니다.' >&2
  exit 1
fi

cleanup
trap - EXIT
unset access_token anon_key service_key QA_PASSWORD login_payload
echo '회원탈퇴·공개 사진 삭제·재로그인 차단 스모크 확인 완료'
