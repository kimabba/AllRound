#!/usr/bin/env bash
# 로컬 스택에서만 클럽 사진 URL 제약을 완화한다(로컬 호스트 허용).
#
# 로컬 Supabase에 붙여 앱을 돌릴 때 사진 업로드 URL이 127.0.0.1:54321 로 나와
# CHECK 제약에 막히는 것을 푼다. supabase db reset 을 하면 원래(엄격한) 정의로
# 돌아가므로 그때마다 다시 실행한다.
#
# 프로덕션 보호: assert_local_supabase.sh 가 로컬 스택인지 먼저 확인한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"

cd "$ROOT"
bash scripts/qa/assert_local_supabase.sh >/dev/null

status_env="$($SUPABASE_BIN status -o env 2>/dev/null)"
db_url="$(awk -F= '$1 == "DB_URL" {sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print}' <<<"$status_env")"
unset status_env

psql "$db_url" -q -v ON_ERROR_STOP=1 -f supabase/qa/local_club_image_url_relaxation.sql
echo "로컬 스택에서 클럽 사진 URL 제약을 완화했습니다(로컬 호스트 허용)."
