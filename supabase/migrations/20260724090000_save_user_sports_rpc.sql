-- JY-146 P3-a 후속: 종목·등급 저장을 단일 트랜잭션 RPC 로.
--
-- 그동안 앱은 PostgREST 로 delete → insert 두 요청을 보냈다. 두 요청은 별도 트랜잭션이라
-- delete 만 커밋된 채 insert 가 거부되면(폐기 등급·FK 위반·네트워크) 종목이 사라졌다.
--
-- 클라이언트에서 delete 대상을 좁히고 upsert 로 바꿔도 두 가지가 남는다.
--   1) 여전히 두 트랜잭션이라 부분 적용이 가능하다.
--   2) 배치 upsert 는 주 종목 교체가 **행 순서에 의존한다**. user_sports_one_primary_per_user
--      는 (user_id) WHERE is_primary 부분 유니크 인덱스라, 새 주 종목을 먼저 올리는 순서면
--      옛 주 종목이 아직 true 인 시점에 23505 로 실패한다(실측 확인).
--
-- 그래서 서버에서 한 트랜잭션으로 처리한다: 주 종목을 모두 내리고 → upsert → 빠진 종목 삭제.

create or replace function public.save_user_sports(p_sports jsonb)
returns void
language plpgsql
-- SECURITY INVOKER(기본): RLS 가 그대로 적용돼 자기 행만 건드린다.
set search_path = ''
as $func$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception '인증이 필요합니다' using errcode = '28000';
  end if;
  if p_sports is null or jsonb_typeof(p_sports) <> 'array' then
    raise exception 'p_sports 는 JSON 배열이어야 합니다' using errcode = '22023';
  end if;

  -- 쓰기 전에 배열 자체의 불변식을 검사한다. 안 하면 같은 sport 중복은 ON CONFLICT 가
  -- 한 행을 두 번 갱신해 21000 으로, primary 가 둘이면 부분 유니크 인덱스가 23505 로
  -- 죽는다 — 둘 다 원인을 알 수 없는 내부 오류라 클라이언트가 고칠 수 없다.
  if exists (
    select 1 from jsonb_array_elements(p_sports) e
     where jsonb_typeof(e) <> 'object' or e ->> 'sport' is null or e ->> 'grade' is null
  ) then
    raise exception '각 원소는 sport·grade 를 가진 객체여야 합니다' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_sports) e)
     <> (select count(distinct e ->> 'sport') from jsonb_array_elements(p_sports) e) then
    raise exception '같은 종목이 두 번 들어왔습니다' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_sports) e
       where coalesce((e ->> 'is_primary')::boolean, false)) > 1 then
    raise exception '주 종목은 하나만 지정할 수 있습니다' using errcode = '22023';
  end if;

  -- 같은 사용자의 저장을 직렬화한다. 트랜잭션 스코프라 커밋·롤백 시 자동 해제된다.
  -- 없으면: 두 기기(또는 재시도)가 동시에 주 종목을 바꿀 때, 뒤 요청의 문장 스냅샷이
  -- 앞 요청이 새로 올린 primary 행을 보지 못해 upsert 가 부분 유니크 인덱스에서
  -- 23505 로 실패한다. 배열 순서가 다른 동시 호출끼리는 행 잠금 교착도 가능하다.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(uid::text, 0)
  );

  -- 주 종목 교체를 순서에 무관하게 만든다(부분 유니크 인덱스 회피).
  -- is_primary 만 바뀌므로 `before update of sport, grade` 트리거는 발동하지 않는다.
  update public.user_sports
     set is_primary = false
   where user_id = uid and is_primary;

  -- upsert 를 먼저 한다. 폐기 등급 보유자의 기존 행이 아직 남아 있어야
  -- enforce_active_grade 가 "이미 갖고 있던 등급"으로 인정한다.
  insert into public.user_sports (user_id, sport, grade, is_primary)
  select uid,
         (e ->> 'sport')::public.sport,
         e ->> 'grade',
         coalesce((e ->> 'is_primary')::boolean, false)
    from jsonb_array_elements(p_sports) e
  on conflict (user_id, sport) do update
     set grade = excluded.grade,
         is_primary = excluded.is_primary;

  -- 목록에서 빠진 종목만 삭제한다. NOT IN 은 값에 NULL 이 섞이면 아무것도 지우지 않으므로
  -- NOT EXISTS 를 쓴다. 빈 배열이면 전부 삭제되는 게 맞다(종목 없음).
  delete from public.user_sports us
   where us.user_id = uid
     and not exists (
       select 1
         from jsonb_array_elements(p_sports) e
        where (e ->> 'sport')::public.sport = us.sport
     );
end;
$func$;

comment on function public.save_user_sports(jsonb) is
  '프로필 종목·등급을 한 트랜잭션으로 교체한다(JY-146). 부분 적용과 주 종목 순서 의존을 없앤다.';

-- 신규 함수 권한은 같은 마이그레이션에서 명시한다(docs/rules/DATABASE_RULES.md).
revoke all on function public.save_user_sports(jsonb) from public;
grant execute on function public.save_user_sports(jsonb) to authenticated, service_role;
