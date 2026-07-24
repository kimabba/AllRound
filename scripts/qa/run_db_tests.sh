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

# 권한 baseline 은 더 이상 여기서 보충하지 않는다.
# 20260724060000_codify_api_role_grants.sql 이 마이그레이션 체인 안에서 부여하므로,
# 이 러너가 통과한다는 것 자체가 "마이그레이션만으로 동작하는 DB 가 재현된다"는 증명이다.
echo "== DB 테스트 부트스트랩 (QA 페르소나) =="
psql "$DB_URL" -q -v ON_ERROR_STOP=1 -f supabase/qa/personas.sql
echo "QA 페르소나 준비 완료"

failed=0
total_ok=0

# 글롭이 하나도 안 맞으면 리터럴 문자열이 루프에 들어가 조용히 통과한다.
shopt -s nullglob
test_files=(supabase/tests/database/*.test.sql)
if [ "${#test_files[@]}" -eq 0 ]; then
  echo "테스트 파일을 찾지 못했습니다: supabase/tests/database/*.test.sql" >&2
  exit 1
fi

for f in "${test_files[@]}"; do
  name="$(basename "$f")"
  # set -e 아래에서 psql 실패로 스크립트가 죽지 않게 rc 를 따로 잡는다.
  set +e
  out="$(psql "$DB_URL" -q -f "$f" 2>&1)"
  rc=$?
  set -e

  n_ok="$(printf '%s' "$out" | grep -cE '^ ok ' || true)"
  n_bad="$(printf '%s' "$out" | grep -cE '^ not ok ' || true)"
  # 서버 오류는 "psql:file:line: ERROR:", 클라이언트 오류는 "psql: error:" 로 대소문자가
  # 다르다. 대소문자를 구분하면 접속 끊김 같은 후자를 놓쳐 ok=0 인 파일이 통과로 위장된다.
  n_err="$(printf '%s' "$out" | grep -ciE '^psql.*error' || true)"
  # pgTAP 은 plan 과 실제 실행 수가 다르면 "Looks like ..." 를 출력한다.
  n_plan="$(printf '%s' "$out" | grep -cE 'Looks like' || true)"

  # assertion 이 0 개면 파일이 실제로 돌지 않은 것이다(모든 테스트 파일은 최소 3건).
  if [ "$n_bad" -gt 0 ] || [ "$n_err" -gt 0 ] || [ "$n_plan" -gt 0 ] \
     || [ "$rc" -ne 0 ] || [ "$n_ok" -eq 0 ]; then
    failed=$((failed + 1))
    printf '✗ %-46s ok=%s not_ok=%s error=%s rc=%s\n' "$name" "$n_ok" "$n_bad" "$n_err" "$rc"
    printf '%s\n' "$out" | grep -iE '^ not ok |^psql.*error|Looks like' | head -12 | sed 's/^/    /'
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
