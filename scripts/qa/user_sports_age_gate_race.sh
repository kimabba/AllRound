#!/usr/bin/env bash
# save_user_sports 연령 게이트의 동시성 회귀 검사 (#320)
#
# pgTAP 은 단일 세션이라 이 경합을 재현할 수 없어 별도 스크립트로 둔다(012 의 advisory
# lock 검증과 같은 이유). CI 의 database 잡에서 run_db_tests.sh 뒤에 실행한다.
#
# 지키는 불변식: **연령 게이트는 advisory lock 뒤에서 평가돼야 한다.**
#   게이트가 락 앞에 있으면, 연령 미검증 계정이 종목 A·B 를 가진 채 [A] 와 [B] 를 동시에
#   호출할 때 둘 다 "기존 행과 동일" 로 통과한다. 먼저 락을 잡은 쪽이 B 를 지우고 커밋하면,
#   뒤따르던 쪽은 이미 사라진 B 를 새 행으로 INSERT 한다 — RLS 시절이면 연령 검사에 막혔을
#   쓰기다. 실제로 리뷰 2회를 통과하며 재발한 결함이라 자동 검사로 고정한다.
#
# 사용: bash scripts/qa/user_sports_age_gate_race.sh   (로컬 Supabase 전용)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# 이 스크립트는 사용자 행을 지우고 다시 만든다. 원격 프로젝트를 가리키면 실제 데이터가
# 사라지므로, 다른 QA 스크립트와 같은 로컬 가드를 먼저 통과해야 한다. DB_URL 은 받지 않는다.
bash scripts/qa/assert_local_supabase.sh >/dev/null

DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
U=00000000-0000-4000-8000-000000000008 # QA 페르소나: 생년월일 없는 계정

if [ "$(psql "$DB_URL" -tAc "select count(*) from public.users where id = '$U'")" != "1" ]; then
  echo "QA 페르소나가 없습니다. 먼저 bash scripts/qa/run_db_tests.sh 를 실행하세요." >&2
  exit 1
fi

holder_pid=""
cleanup() {
  [ -n "$holder_pid" ] && kill "$holder_pid" 2>/dev/null
  # personas.sql 의 정본 상태(birth_date NULL·종목 없음)로 되돌린다.
  psql "$DB_URL" -q \
    -c "delete from public.user_sports where user_id = '$U'" \
    -c "update public.users set birth_date = null where id = '$U'" 2>/dev/null
}
trap cleanup EXIT

psql "$DB_URL" -q -v ON_ERROR_STOP=1 \
  -c "update public.users set birth_date = null where id = '$U'" \
  -c "delete from public.user_sports where user_id = '$U'" \
  -c "insert into public.user_sports (user_id, sport, grade, is_primary) values
        ('$U','futsal','intro',true), ('$U','tennis','y1to3',false)"

# 세션 A: 락을 먼저 잡고 tennis 를 지운 뒤 잠시 뒤 커밋한다.
psql "$DB_URL" -q -v ON_ERROR_STOP=1 >/dev/null <<SQL &
begin;
select pg_advisory_xact_lock(hashtextextended('$U', 0));
delete from public.user_sports where user_id = '$U' and sport = 'tennis';
select pg_sleep(5);
commit;
SQL
holder_pid=$!

# 세션 A 가 실제로 락을 잡을 때까지 기다린다(고정 sleep 은 CI 에서 흔들린다).
for _ in $(seq 1 50); do
  held=$(psql "$DB_URL" -tAc "select count(*) from pg_locks
      where locktype = 'advisory' and granted
        and ((classid::bigint << 32) | objid::bigint) = hashtextextended('$U', 0)")
  [ "$held" -ge 1 ] && break
  sleep 0.2
done
if [ "${held:-0}" -lt 1 ]; then
  echo "세션 A 가 advisory lock 을 잡지 못했습니다(환경 문제)." >&2
  exit 1
fi

# 세션 B: 지워지는 중인 tennis 를 "기존 행과 동일" 이라 주장하며 저장을 시도한다.
# SQLSTATE 를 직접 찍는다 — 한글 메시지만 grep 하면 22023·P0001 로 바뀌어도 통과한다.
# NOTICE 는 stderr 로 나오므로 2>&1 로 함께 받는다.
out=$(psql "$DB_URL" -X -q -tA -v ON_ERROR_STOP=1 2>&1 <<SQL
begin;
set local statement_timeout = '30s';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$U","role":"authenticated"}', true);
do \$\$
begin
  perform public.save_user_sports('[{"sport":"tennis","grade":"y1to3","is_primary":false}]'::jsonb);
  raise notice 'RESULT=NO_ERROR';
exception when others then
  raise notice 'RESULT=%|%', sqlstate, sqlerrm;
end
\$\$;
commit;
SQL
) || true

if ! wait "$holder_pid"; then
  echo "세션 A(락 보유 세션)가 실패했습니다." >&2
  echo "$out" >&2
  exit 1
fi
holder_pid=""

final=$(psql "$DB_URL" -tAc "select coalesce(string_agg(sport::text, ',' order by sport::text), '(없음)')
                               from public.user_sports where user_id = '$U'")

if grep -q 'RESULT=42501|연령 검증이 필요합니다' <<<"$out" && [ "$final" = "futsal" ]; then
  echo "✅ 연령 게이트 경합 차단 확인 (뒤따른 세션 42501 거부, 최종 종목=$final)"
  exit 0
fi

echo "❌ 연령 게이트가 동시 호출로 우회됐다 (최종 종목=$final, 기대=futsal)" >&2
grep -E 'RESULT=' <<<"$out" >&2 || echo "$out" | tail -5 >&2
exit 1
