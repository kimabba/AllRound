#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"

cd "$ROOT"

if ! command -v "$SUPABASE_BIN" >/dev/null 2>&1; then
  echo "supabase CLI를 찾을 수 없습니다." >&2
  exit 1
fi

# status 출력에는 로컬 anon/service-role 키가 포함되므로 절대 출력하거나 저장하지 않는다.
status_env="$($SUPABASE_BIN status -o env 2>/dev/null)" || {
  echo "로컬 Supabase가 실행 중이 아닙니다. 먼저 supabase start를 실행하세요." >&2
  exit 1
}

api_url="$(awk -F= '$1 == "API_URL" {gsub(/^\"|\"$/, "", $2); print $2}' <<<"$status_env")"
db_url="$(awk -F= '$1 == "DB_URL" {sub(/^[^=]*=/, ""); gsub(/^\"|\"$/, ""); print}' <<<"$status_env")"

unset status_env

case "$api_url" in
  http://127.0.0.1:* | http://localhost:*) ;;
  *)
    echo "QA 중단: API_URL이 로컬 주소가 아닙니다." >&2
    exit 1
    ;;
esac

case "$db_url" in
  postgresql://*@127.0.0.1:*/* | postgresql://*@localhost:*/* | postgres://*@127.0.0.1:*/* | postgres://*@localhost:*/*) ;;
  *)
    echo "QA 중단: DB_URL이 로컬 주소가 아닙니다." >&2
    exit 1
    ;;
esac

echo "로컬 Supabase 확인 완료: 외부 프로젝트 접근 없음"
