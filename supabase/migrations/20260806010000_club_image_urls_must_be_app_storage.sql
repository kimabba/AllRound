-- 클럽 사진 주소는 우리 Storage 공개 URL만 허용한다.
--
-- 문제: club_posts.image_urls / clubs.intro_image_urls / clubs.logo_url 은 형식 제약이
--   없는 text 라 RLS 를 통과한 사용자가 앱을 거치지 않고 임의 외부 URL 을 넣을 수 있다.
--   그 글을 여는 사람들의 IP·UA 가 외부 서버로 새고, 검수 후 원격에서 이미지 내용만
--   바꿔치기하는 우회도 가능하다. 소개 사진은 비멤버에게도 노출돼 영향이 더 크다.
--
-- 강제 지점: 값 검증은 RLS(누가 쓰는가)로는 불가능하므로 CHECK 제약으로 내린다.
--   CHECK 안에서는 서브쿼리를 쓸 수 없어 IMMUTABLE 헬퍼 함수 한 개로 배열을 검사한다.
--
-- 호스트는 프로덕션 하나만 허용한다. 다른 Supabase 프로젝트를 열어두면 공격자가 자기
--   프로젝트로 우회할 수 있다. 프로젝트 ref 는 앱에 이미 들어 있는 공개 식별자이며
--   시크릿이 아니다. 로컬 스택(127.0.0.1:54321)용 완화는 seed.sql 에만 둔다 —
--   프로덕션 제약이 개발자 기기의 loopback 주소를 허용할 이유가 없다.
--
-- 경로도 앱이 실제로 만드는 형태로 고정한다: (업로더 uuid/)?48자리 hex.jpg|png.
--   느슨하게 두면 `.../사용중인객체.jpg#x` 처럼 fragment·query·퍼센트 인코딩을 붙인
--   URL 이 저장되고, 정리 작업(orphan_club_image_objects)은 그 문자열을 객체 키와
--   그대로 대조하므로 **사용 중인 사진을 고아로 오판해 지운다**. 프로덕션 기존 7건은
--   모두 이 형식임을 확인했다.

begin;

create or replace function public.club_image_urls_are_app_storage(
  p_urls text[],
  p_bucket text
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(
    bool_and(
      u is not null
      and u ~ (
        '^https://bsjdgwmveokanclqwtvx\.supabase\.co'
        || '/storage/v1/object/public/'
        || p_bucket
        || '/([0-9a-f-]{36}/)?[0-9a-f]{48}\.(jpg|png)$'
      )
    ),
    true
  )
  from unnest(p_urls) as u;
$$;

comment on function public.club_image_urls_are_app_storage(text[], text) is
  '클럽 사진 URL 이 우리 Storage 공개 경로인지 검사한다. CHECK 제약 전용(IMMUTABLE).';

-- CHECK 제약 평가는 트리거와 달리 **호출자의 EXECUTE 를 요구한다**(로컬 실측:
-- authenticated 에서 회수하면 정상 INSERT 가 permission denied 로 막힌다).
-- 그래서 쓰기 주체인 authenticated·service_role 에만 남기고 anon 은 닫는다.
-- 프로덕션은 새 함수에 anon 개별 grant 를 주므로 public 회수만으로는 부족하다(021 주석).
revoke all on function public.club_image_urls_are_app_storage(text[], text)
  from public, anon;
grant execute on function public.club_image_urls_are_app_storage(text[], text)
  to authenticated, service_role;

alter table public.clubs
  drop constraint if exists clubs_logo_url_is_app_storage;
alter table public.clubs
  add constraint clubs_logo_url_is_app_storage
  check (
    logo_url is null
    or public.club_image_urls_are_app_storage(array[logo_url], 'club-logos')
  );

alter table public.clubs
  drop constraint if exists clubs_intro_image_urls_are_app_storage;
alter table public.clubs
  add constraint clubs_intro_image_urls_are_app_storage
  check (
    public.club_image_urls_are_app_storage(intro_image_urls, 'club-intro-images')
  );

alter table public.club_posts
  drop constraint if exists club_posts_image_urls_are_app_storage;
alter table public.club_posts
  add constraint club_posts_image_urls_are_app_storage
  check (
    public.club_image_urls_are_app_storage(image_urls, 'club-posts')
  );

commit;

-- 새 함수를 PostgREST 스키마 캐시에 즉시 알린다(AGENTS/START-HERE 규칙 9).
-- 없으면 배포 직후 RPC 호출이 캐시 갱신 전까지 실패할 수 있다.
notify pgrst, 'reload schema';
