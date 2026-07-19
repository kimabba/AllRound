#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"
QA_PASSWORD="QaLocal-Only-2026!"
MEMBER_ID="00000000-0000-4000-8000-000000000005"

cd "$ROOT"
bash scripts/qa/assert_local_supabase.sh >/dev/null

# Local keys and access tokens stay in memory and are never printed.
status_env="$($SUPABASE_BIN status -o env 2>/dev/null)"
api_url="$(awk -F= '$1 == "API_URL" {gsub(/^"|"$/, "", $2); print $2}' <<<"$status_env")"
anon_key="$(awk -F= '$1 == "ANON_KEY" {sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print}' <<<"$status_env")"
unset status_env

login_token() {
  local email="$1"
  local payload
  payload="$(printf '{"email":"%s","password":"%s"}' "$email" "$QA_PASSWORD")"
  curl --fail --silent --show-error \
    --connect-timeout 3 \
    --max-time 10 \
    --request POST \
    --header "apikey: $anon_key" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    "$api_url/auth/v1/token?grant_type=password" | jq -er '.access_token'
}

request_code() {
  curl --silent --show-error \
    --connect-timeout 3 \
    --max-time 15 \
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

member_token="$(login_token qa-member@allround.invalid)"
applicant_token="$(login_token qa-applicant@allround.invalid)"
empty_token="$(login_token qa-empty@allround.invalid)"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/allround-storage-smoke.XXXXXX")"
image_file="$temp_dir/pixel.png"
cleanup() {
  local body
  body="$(printf '{"prefixes":["%s"]}' "$public_name")"
  request_code \
    --request DELETE \
    --header "apikey: $anon_key" \
    --header "Authorization: Bearer $member_token" \
    --header "Content-Type: application/json" \
    --data "$body" \
    "$api_url/storage/v1/object/club-logos" >/dev/null || true
  body="$(printf '{"prefixes":["%s"]}' "$evidence_name")"
  request_code \
    --request DELETE \
    --header "apikey: $anon_key" \
    --header "Authorization: Bearer $member_token" \
    --header "Content-Type: application/json" \
    --data "$body" \
    "$api_url/storage/v1/object/ugc-report-evidence" >/dev/null || true
  rm -f "$image_file"
  rmdir "$temp_dir" 2>/dev/null || true
}

public_name="qa-opaque-public-$(date +%s)-$$.png"
evidence_name="$MEMBER_ID/qa-opaque-private-$(date +%s)-$$.png"
trap cleanup EXIT

printf '%s' \
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+NlpYVQAAAABJRU5ErkJggg==' \
  | openssl base64 -d -A >"$image_file"

code="$(request_code \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $member_token" \
  --header "Content-Type: image/png" \
  --data-binary "@$image_file" \
  "$api_url/storage/v1/object/club-logos/$public_name")"
expect_code "$code" '200|201' '완료 회원 공개 이미지 업로드'

code="$(request_code \
  --header "apikey: $anon_key" \
  "$api_url/storage/v1/object/public/club-logos/$public_name")"
expect_code "$code" '200' '공개 이미지 URL 조회'

list_body='{"prefix":"","limit":100,"offset":0,"sortBy":{"column":"name","order":"asc"}}'
list_result="$(curl --fail --silent --show-error \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $applicant_token" \
  --header "Content-Type: application/json" \
  --data "$list_body" \
  "$api_url/storage/v1/object/list/club-logos")"
if jq -e --arg name "$public_name" '.[] | select(.name == $name)' \
  <<<"$list_result" >/dev/null; then
  echo '다른 계정이 공개 버킷 파일 목록을 열람했습니다.' >&2
  exit 1
fi

code="$(request_code \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $empty_token" \
  --header "Content-Type: image/png" \
  --data-binary "@$image_file" \
  "$api_url/storage/v1/object/club-logos/qa-empty-blocked-$$.png")"
expect_code "$code" '400|401|403' '온보딩 미완료 계정 업로드 차단'

code="$(request_code \
  --request POST \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $member_token" \
  --header "Content-Type: image/png" \
  --data-binary "@$image_file" \
  "$api_url/storage/v1/object/ugc-report-evidence/$evidence_name")"
expect_code "$code" '200|201' '비공개 신고 증거 업로드'

code="$(request_code \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $member_token" \
  "$api_url/storage/v1/object/authenticated/ugc-report-evidence/$evidence_name")"
expect_code "$code" '200' '신고자 본인 증거 조회'

code="$(request_code \
  --header "apikey: $anon_key" \
  --header "Authorization: Bearer $applicant_token" \
  "$api_url/storage/v1/object/authenticated/ugc-report-evidence/$evidence_name")"
expect_code "$code" '400|401|403|404' '다른 계정 신고 증거 차단'

cleanup
trap - EXIT
unset member_token applicant_token empty_token anon_key QA_PASSWORD
echo 'Storage 소유권·비공개 증거·연령 게이트 스모크 확인 완료'
