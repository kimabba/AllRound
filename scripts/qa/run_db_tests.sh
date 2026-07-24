#!/usr/bin/env bash
# pgTAP DB 테스트 러너 (CI·로컬 공용)
#
# 순서: 플랫폼 기본권한 보충 → QA 페르소나 시드 → supabase/tests/database/*.test.sql 실행
# 부트스트랩이 필요한 이유는 supabase/qa/platform_grants.sql 주석 참조.
#
# pg_prove 도커 이미지에 의존하지 않고 psql 로 직접 돌린다. 테스트 파일이 각자
# begin/rollback 으로 격리되어 있어 순서 의존이 없다.
#
# 사용: bash scripts/qa/run_db_tests.sh
#       DB_URL=postgresql://... bash scripts/qa/run_db_tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

if ! psql "$DB_URL" -tAc 'select 1' >/dev/null 2>&1; then
  echo "로컬 Supabase DB 에 접속할 수 없습니다: $DB_URL" >&2
  echo "먼저 'supabase start' 로 스택을 올리세요." >&2
  exit 1
fi

echo "== DB 테스트 부트스트랩 =="
psql "$DB_URL" -q -v ON_ERROR_STOP=1 -f supabase/qa/platform_grants.sql
psql "$DB_URL" -q -v ON_ERROR_STOP=1 -f supabase/qa/personas.sql
echo "권한 baseline · QA 페르소나 준비 완료"

failed=0
total_ok=0

for f in supabase/tests/database/*.test.sql; do
  name="$(basename "$f")"
  out="$(psql "$DB_URL" -q -f "$f" 2>&1 || true)"

  n_ok="$(printf '%s' "$out" | grep -cE '^ ok ' || true)"
  n_bad="$(printf '%s' "$out" | grep -cE '^ not ok ' || true)"
  n_err="$(printf '%s' "$out" | grep -cE '^psql.*ERROR' || true)"
  # pgTAP 은 plan 과 실제 실행 수가 다르면 "Looks like ..." 를 출력한다.
  n_plan="$(printf '%s' "$out" | grep -cE 'Looks like' || true)"

  if [ "$n_bad" -gt 0 ] || [ "$n_err" -gt 0 ] || [ "$n_plan" -gt 0 ]; then
    failed=$((failed + 1))
    printf '✗ %-46s ok=%s not_ok=%s error=%s\n' "$name" "$n_ok" "$n_bad" "$n_err"
    printf '%s\n' "$out" | grep -E '^ not ok |^psql.*ERROR|Looks like' | head -12 | sed 's/^/    /'
  else
    total_ok=$((total_ok + n_ok))
    printf '✓ %-46s ok=%s\n' "$name" "$n_ok"
  fi
done

echo
if [ "$failed" -gt 0 ]; then
  echo "DB 테스트 실패: ${failed}개 파일" >&2
  exit 1
fi
echo "✅ DB 테스트 통과 (assertion ${total_ok}개)"
