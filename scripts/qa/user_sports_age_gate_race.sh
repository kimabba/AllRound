#!/usr/bin/env bash
# save_user_sports 연령 게이트의 동시성 회귀 검사 (#320)
#
# pgTAP 은 단일 세션이라 이 경합을 재현할 수 없어 별도 스크립트로 둔다(012 의 advisory
# lock 검증과 같은 이유). CI 의 database 잡에서 실행한다.
#
# 지키는 불변식: **연령 게이트는 advisory lock 뒤에서 평가돼야 한다.**
#   게이트가 락 앞에 있으면, 연령 미검증 계정이 종목 A·B 를 가진 채 [A] 와 [B] 를 동시에
#   호출할 때 둘 다 "기존 행과 동일" 로 통과한다. 먼저 락을 잡은 쪽이 B 를 지우고 커밋하면,
#   뒤따르던 쪽은 이미 사라진 B 를 새 행으로 INSERT 한다 — RLS 시절이면 연령 검사에 막혔을
#   쓰기다. 리뷰 2회를 통과하며 재발한 결함이라 자동 검사로 고정한다.
#
# fixture 는 이 검사 전용 계정을 직접 만들고 끝나면 지운다. QA 페르소나를 빌려 쓰면
# "실행 전 상태로 되돌리기"(created_at·updated_at·폐기 등급 행)가 원리적으로 불가능하다.
#
# 사용: bash scripts/qa/user_sports_age_gate_race.sh   (로컬 Supabase 전용)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# 이 스크립트는 계정을 만들고 지운다. 원격 프로젝트를 가리키면 실제 데이터가 사라지므로,
# 다른 QA 스크립트와 같은 로컬 가드를 먼저 통과해야 한다. DB_URL 은 인자로 받지 않는다.
bash scripts/qa/assert_local_supabase.sh >/dev/null

DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
U=00000000-0000-4000-8000-0000000000f0 # 이 검사 전용 합성 계정
APP=user_sports_race_b                 # 세션 B 식별용 application_name

cleanup() {
  # auth.users → public.users → user_sports 로 CASCADE 되므로 한 줄이면 흔적이 없다.
  psql "$DB_URL" -q -c "delete from auth.users where id = '$U'" 2>/dev/null || true
}
trap cleanup EXIT
cleanup # 앞선 중단이 남긴 잔여물 제거

# 연령 미검증 계정: raw_user_meta_data 에 birth_date 가 없으면 handle_new_user 트리거가
# public.users.birth_date 를 NULL 로 만든다(personas.sql 의 008 과 같은 상태).
psql "$DB_URL" -q -v ON_ERROR_STOP=1 \
  -c "insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data, is_super_admin,
        confirmation_token, recovery_token,
        email_change, email_change_token_new, email_change_token_current)
      values (
        '00000000-0000-0000-0000-000000000000', '$U', 'authenticated', 'authenticated',
        'qa-race@allround.invalid', '', now(), now(), now(),
        '{\"provider\":\"email\",\"providers\":[\"email\"]}'::jsonb,
        '{\"display_name\":\"QA 경합검사\"}'::jsonb,
        false, '', '', '', '', '')" \
  -c "insert into public.user_sports (user_id, sport, grade, is_primary) values
        ('$U','futsal','intro',true), ('$U','tennis','y1to3',false)"

if [ -n "$(psql "$DB_URL" -tAc "select birth_date from public.users where id = '$U'")" ]; then
  echo "합성 계정에 생년월일이 생겼습니다 — 이 검사는 연령 미검증 계정을 전제로 합니다." >&2
  exit 1
fi

# 세션 A: 락을 잡고 tennis 를 지운 뒤, **세션 B 가 같은 락을 기다리는 것을 확인하고** 커밋한다.
# 고정 시간(pg_sleep)으로 커밋하면 러너가 느릴 때 B 가 시작하기도 전에 커밋이 끝나,
# 게이트가 락 앞에 있는 결함 함수도 "이미 지워진 tennis" 를 보고 42501 을 내며 통과한다
# (= 검사가 조용히 무력화된다). 대기 세션은 application_name 으로 특정한다 — 같은 키를
# 기다리는 제3 세션을 B 로 오인하면 같은 방식으로 무력화되기 때문이다.
psql "$DB_URL" -q -v ON_ERROR_STOP=1 >/dev/null <<SQL &
begin;
select pg_advisory_xact_lock(hashtextextended('$U', 0));
delete from public.user_sports where user_id = '$U' and sport = 'tennis';
do \$\$
declare
  waited int := 0;
begin
  while not exists (
    select 1
      from pg_locks l
      join pg_stat_activity a on a.pid = l.pid
     where l.locktype = 'advisory'
       and not l.granted
       and l.database = (select oid from pg_database where datname = current_database())
       and ((l.classid::bigint << 32) | l.objid::bigint)
           = pg_catalog.hashtextextended('$U', 0)
       and a.application_name = '$APP'
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

# 세션 B: 지워지는 중인 tennis 를 "기존 행과 동일" 이라 주장하며 저장을 시도한다.
# SQLSTATE 를 직접 찍는다 — 한글 메시지만 grep 하면 22023·P0001 로 바뀌어도 통과한다.
# NOTICE 는 stderr 로 나오므로 2>&1 로 함께 받는다.
out=$(PGAPPNAME="$APP" psql "$DB_URL" -X -q -tA -v ON_ERROR_STOP=1 2>&1 <<SQL
begin;
set local statement_timeout = '60s';
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
  echo "세션 A(락 보유 세션)가 실패했습니다 — 검사를 신뢰할 수 없습니다." >&2
  echo "$out" >&2
  exit 1
fi

final=$(psql "$DB_URL" -tAc "select coalesce(string_agg(sport::text, ',' order by sport::text), '(없음)')
                               from public.user_sports where user_id = '$U'")

if grep -q 'RESULT=42501|연령 검증이 필요합니다' <<<"$out" && [ "$final" = "futsal" ]; then
  echo "✅ 연령 게이트 경합 차단 확인 (뒤따른 세션 42501 거부, 최종 종목=$final)"
  exit 0
fi

echo "❌ 연령 게이트가 동시 호출로 우회됐다 (최종 종목=$final, 기대=futsal)" >&2
grep -E 'RESULT=' <<<"$out" >&2 || echo "$out" | tail -5 >&2
exit 1
