#!/usr/bin/env bash
# save_user_sports 연령 게이트의 동시성 회귀 검사 (#320)
#
# pgTAP 은 단일 세션이라 이 경합을 재현할 수 없어 별도 스크립트로 둔다(012 의 advisory
# lock 검증과 같은 이유). CI 에는 붙이지 않는다 — 함수를 손댈 때 수동으로 돌린다.
#
# 지키는 불변식: **연령 게이트는 advisory lock 뒤에서 평가돼야 한다.**
#   게이트가 락 앞에 있으면, 연령 미검증 계정이 종목 A·B 를 가진 채 [A] 와 [B] 를 동시에
#   호출할 때 둘 다 "기존 행과 동일" 로 통과한다. 먼저 락을 잡은 쪽이 B 를 지우고 커밋하면,
#   뒤따르던 쪽은 이미 사라진 B 를 새 행으로 INSERT 한다 — RLS 시절이면 연령 검사에 막혔을
#   쓰기다(실측으로 재현 확인).
#
# 사용: bash scripts/qa/user_sports_age_gate_race.sh
#       DB_URL=postgresql://... bash scripts/qa/user_sports_age_gate_race.sh
set -uo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
U=00000000-0000-4000-8000-000000000008 # QA 페르소나: 생년월일 없는 계정

if ! psql "$DB_URL" -tAc 'select 1' >/dev/null 2>&1; then
  echo "로컬 Supabase DB 에 접속할 수 없습니다: $DB_URL" >&2
  exit 1
fi

psql "$DB_URL" -q -v ON_ERROR_STOP=1 \
  -c "update public.users set birth_date = null where id = '$U'" \
  -c "delete from public.user_sports where user_id = '$U'" \
  -c "insert into public.user_sports (user_id, sport, grade, is_primary) values
        ('$U','futsal','intro',true), ('$U','tennis','y1to3',false)"

# 세션 A: 락을 먼저 잡고 tennis 를 지운 뒤 잠시 뒤 커밋한다.
psql "$DB_URL" -q >/dev/null 2>&1 <<SQL &
begin;
select pg_advisory_xact_lock(hashtextextended('$U', 0));
delete from public.user_sports where user_id = '$U' and sport = 'tennis';
select pg_sleep(4);
commit;
SQL

sleep 1
# 세션 B: 지워지는 중인 tennis 를 "기존 행과 동일" 이라 주장하며 저장을 시도한다.
out=$(psql "$DB_URL" -X -q 2>&1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$U","role":"authenticated"}', true);
select public.save_user_sports('[{"sport":"tennis","grade":"y1to3","is_primary":false}]'::jsonb);
commit;
SQL
)
wait

final=$(psql "$DB_URL" -tAc "select coalesce(string_agg(sport::text, ',' order by sport::text), '(없음)')
                               from public.user_sports where user_id = '$U'")
psql "$DB_URL" -q -c "delete from public.user_sports where user_id = '$U'"

if grep -q '연령 검증이 필요합니다' <<<"$out" && [ "$final" = "futsal" ]; then
  echo "✅ 연령 게이트 경합 차단 확인 (뒤따른 세션 거부, 최종 종목=$final)"
  exit 0
fi

echo "❌ 연령 게이트가 동시 호출로 우회됐다 (최종 종목=$final)" >&2
echo "$out" | tail -5 >&2
exit 1
