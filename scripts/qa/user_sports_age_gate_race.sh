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
# 이 검사는 "연령 미검증 계정" 이 필요하다. 008 에 생년월일이 채워져 있으면 되돌릴 수 없다
# (enforce_min_signup_age 가 한 번 저장된 생년월일의 삭제를 막는다) → 시드 재생성이 답이다.
if [ -n "$(psql "$DB_URL" -tAc "select birth_date from public.users where id = '$U'")" ]; then
  echo "페르소나 $U 에 생년월일이 채워져 있어 이 검사를 돌릴 수 없습니다." >&2
  echo "supabase db reset 으로 시드를 재생성한 뒤 다시 실행하세요." >&2
  exit 1
fi

# 실행 전 상태를 저장해 두고 그대로 되돌린다("정본일 것" 이라고 가정하지 않는다).
# users.updated_at 만은 되돌릴 수 없다 — users_touch_updated_at 트리거가 매 UPDATE 에
# 새 값을 넣기 때문이다(002_init_users_sports.sql).
prior_birth=$(psql "$DB_URL" -tAc "select coalesce(birth_date::text, '') from public.users where id = '$U'")
prior_sports=$(psql "$DB_URL" -tAc "select coalesce(json_agg(json_build_object(
    'sport', sport, 'grade', grade, 'is_primary', is_primary))::text, '[]')
  from public.user_sports where user_id = '$U'")

holder_pid=""
cleanup() {
  [ -n "$holder_pid" ] && kill "$holder_pid" 2>/dev/null
  psql "$DB_URL" -q \
    -c "delete from public.user_sports where user_id = '$U'" \
    -c "insert into public.user_sports (user_id, sport, grade, is_primary)
        select '$U', (e ->> 'sport')::public.sport, e ->> 'grade', (e ->> 'is_primary')::boolean
          from jsonb_array_elements('$prior_sports'::jsonb) e" \
    -c "update public.users set birth_date = nullif('$prior_birth', '')::date where id = '$U'" \
    2>/dev/null || echo "경고: 실행 전 상태로 되돌리지 못했습니다. run_db_tests.sh 로 시드를 복구하세요." >&2
}
trap cleanup EXIT

psql "$DB_URL" -q -v ON_ERROR_STOP=1 \
  -c "update public.users set birth_date = null where id = '$U'" \
  -c "delete from public.user_sports where user_id = '$U'" \
  -c "insert into public.user_sports (user_id, sport, grade, is_primary) values
        ('$U','futsal','intro',true), ('$U','tennis','y1to3',false)"

# 세션 A: 락을 잡고 tennis 를 지운 뒤, **세션 B 가 같은 락을 기다리는 것을 확인하고** 커밋한다.
# 고정 시간(pg_sleep)으로 커밋하면 러너가 느릴 때 B 가 시작하기도 전에 커밋이 끝나,
# 게이트가 락 앞에 있는 결함 함수도 "이미 지워진 tennis" 를 보고 42501 을 내며 통과한다
# (= 검사가 조용히 무력화된다). B 의 대기를 조건으로 삼으면 스케줄링과 무관해진다.
psql "$DB_URL" -q -v ON_ERROR_STOP=1 >/dev/null <<SQL &
begin;
select pg_advisory_xact_lock(hashtextextended('$U', 0));
delete from public.user_sports where user_id = '$U' and sport = 'tennis';
do \$\$
declare
  waited int := 0;
begin
  while not exists (
    select 1 from pg_locks
     where locktype = 'advisory' and not granted
       and ((classid::bigint << 32) | objid::bigint) = pg_catalog.hashtextextended('$U', 0)
  ) loop
    if waited > 600 then
      raise exception '세션 B 가 락을 기다리지 않았다 — 검사가 무의미하다';
    end if;
    waited := waited + 1;
    perform pg_sleep(0.05);
  end loop;
end
\$\$;
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
