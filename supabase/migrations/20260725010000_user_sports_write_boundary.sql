-- JY-146 후속(#320): user_sports 쓰기를 save_user_sports RPC 로만 열어 둔다.
--
-- 20260724090000 이 저장을 단일 트랜잭션 RPC 로 옮겼지만, authenticated 는 여전히
-- user_sports 를 직접 INSERT/UPDATE/DELETE 할 수 있었다. 즉 RPC 는 강제 경계가 아니라
-- 권장 경로였고, 직접 DML 로 부분 적용(delete 만 성공)·주 종목 순서 의존·advisory lock
-- 밖의 경합을 그대로 재현할 수 있었다.
--
-- 회수하면 SECURITY INVOKER 함수는 자기 자신도 permission denied 로 막힌다(권한은 호출자
-- 기준으로 검사된다). 그래서 RPC 를 SECURITY DEFINER 로 바꾼다.
--
-- DEFINER 는 RLS 를 우회한다. 우회되는 규칙 중 함수 본문이 아직 대신 지키지 않는 것은
-- **연령 게이트** 하나뿐이므로(user_sports_self_insert/update 의 has_verified_signup_age),
-- 여기서 명시적으로 검사한다. 나머지는 우회되지 않는다 — enforce_active_grade 트리거,
-- grades 복합 FK, one_primary_per_user 부분 유니크 인덱스는 DEFINER 여부와 무관하게 발동한다.
-- 자기 행 한정은 함수가 auth.uid() 로 직접 강제한다(payload 의 user_id 는 읽지 않는다).

create or replace function public.save_user_sports(p_sports jsonb)
returns void
language plpgsql
-- SECURITY DEFINER: 아래 revoke 로 authenticated 의 직접 DML 을 걷어냈기 때문에,
-- 이 함수가 테이블에 쓸 수 있는 유일한 경로가 된다. 소유자는 postgres 다.
security definer
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
  -- sport enum·is_primary boolean 을 미리 검증한다. 안 하면 아래 캐스팅에서 22P02 로 죽어
  -- 클라이언트가 받는 오류 계약이 흔들린다(의도한 22023 이 아니라 내부 캐스팅 오류).
  -- enum 값은 enum_range 로 가져와 하드코딩하지 않는다.
  if exists (
    select 1 from jsonb_array_elements(p_sports) e
     where (e ->> 'sport') <> all (
       select unnest(enum_range(null::public.sport))::text
     )
  ) then
    raise exception '알 수 없는 종목이 있습니다' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_sports) e
     where e ? 'is_primary' and jsonb_typeof(e -> 'is_primary') <> 'boolean'
  ) then
    raise exception 'is_primary 는 boolean 이어야 합니다' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_sports) e)
     <> (select count(distinct e ->> 'sport') from jsonb_array_elements(p_sports) e) then
    raise exception '같은 종목이 두 번 들어왔습니다' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_sports) e
       where coalesce((e ->> 'is_primary')::boolean, false)) > 1 then
    raise exception '주 종목은 하나만 지정할 수 있습니다' using errcode = '22023';
  end if;

  -- 연령 게이트(개인정보보호법 §22의2). DEFINER 라 RLS 정책이 걸리지 않으므로 여기서 건다.
  -- 배열 검증 뒤에 둔다 — 앞에 두면 잘못된 sport 값이 캐스팅 오류로 먼저 터진다.
  --
  -- "새로 넣거나 값을 바꾸는 원소가 하나라도 있을 때"만 건다. RLS 도 insert/update 에만
  -- has_verified_signup_age 를 걸었고 delete 는 보지 않았다(user_sports_self_delete).
  -- 무조건 걸면 게이트 도입(2026-07-18) 전 가입해 birth_date 가 비어 있는 계정이
  -- 종목을 하나만 빼는 것까지 막힌다(운영 실측 3명). 전체 삭제는 되는데 부분 삭제만
  -- 막히면, 지운 뒤 다시 넣을 수 없는 유실 경로가 된다.
  if not (select public.has_verified_signup_age())
     and exists (
       select 1
         from jsonb_array_elements(p_sports) e
        where not exists (
          select 1
            from public.user_sports us
           where us.user_id = uid
             and us.sport = (e ->> 'sport')::public.sport
             and us.grade = e ->> 'grade'
             and us.is_primary = coalesce((e ->> 'is_primary')::boolean, false)
        )
     ) then
    raise exception '연령 검증이 필요합니다' using errcode = '42501';
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
  '프로필 종목·등급을 한 트랜잭션으로 교체한다(JY-146). user_sports 의 유일한 클라이언트 쓰기 경로다(#320).';

-- create or replace 는 기존 ACL 을 보존하지만, 클린 재생 시 이 파일만 읽어도 권한이
-- 자명하도록 다시 선언한다(docs/rules/DATABASE_RULES.md).
revoke all on function public.save_user_sports(jsonb) from public;
grant execute on function public.save_user_sports(jsonb) to authenticated, service_role;

-- 직접 DML 회수. 20260724060000_codify_api_role_grants.sql 의 club_inquiry 와 같은 패턴이다
-- (권한은 넓게 + 예외를 여기서 좁힌다). select 는 유지 — 앱이 자기 종목을 읽어야 한다.
-- RLS 정책은 그대로 둔다: service_role·관리자 읽기 경로와 방어 심층화에 계속 쓰인다.
revoke insert, update, delete on public.user_sports from anon, authenticated;
