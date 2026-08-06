-- 어느 클럽 사진에도 걸려 있지 않은 Storage 객체를 찾는다 (storage-gc Edge Function 용).
--
-- 문제: 게시글 삭제·소개 사진 교체·업로드 후 이탈 어디에서도 Storage 파일을 지우지
--   않는다. 공개 버킷이라 URL 을 아는 사람은 "지운" 사진을 계속 볼 수 있고 용량도
--   한 방향으로만 는다. 실측(2026-08-06 프로덕션): 객체 39개 중 32개가 미참조.
--
-- 삭제 주체를 앱에 두지 않는 이유: 운영자가 남의 글을 지우면 Storage delete 정책
--   (owner_id = auth.uid())에 막혀 파일이 남고, 앱이 도중에 꺼져도 남는다. 참조가
--   끊긴 파일을 서버가 한 곳에서 걷어내는 편이 경로마다 삭제 코드를 심는 것보다 짧다.
--
-- 안전장치: 방금 올라갔지만 아직 글에 저장되지 않은 파일을 지우지 않도록 기본 7일이
--   지난 객체만 대상으로 한다. 목록 조회와 실제 삭제 사이에 그 객체를 새로 참조하는
--   쓰기가 끼면 살아있는 사진을 지우게 되는데(codex MAJOR), 앱은 업로드 직후에만 URL 을
--   쓰고 작성 임시저장도 URL 을 보관하지 않아(had_selected_images 플래그뿐) 실제 경로는
--   없다. 그래도 되돌릴 수 없는 삭제라 유예를 하루가 아니라 일주일로 잡는다.
--   신고 스냅샷(content_snapshot)이 참조하는 사진은 원본 글이 지워진 뒤에도 심사
--   근거이므로 참조로 친다.

begin;

create or replace function public.orphan_club_image_objects(
  p_min_age interval default interval '7 days'
)
returns table (bucket_id text, object_name text)
language sql
security definer
stable
set search_path = ''
as $$
  with referenced as (
    select substring(u from '/storage/v1/object/public/(.*)$') as key
    from (
      select logo_url from public.clubs where logo_url is not null
      union all
      select unnest(intro_image_urls) from public.clubs
      union all
      select unnest(image_urls) from public.club_posts
    ) as s(u)
    union
    select m[1]
    from public.ugc_reports r
    cross join lateral regexp_matches(
      r.content_snapshot::text,
      '/storage/v1/object/public/([^"]+)',
      'g'
    ) as m
  )
  -- ponytail: 객체 수십~수천 개 규모라 매칭은 전량 대조로 충분하다.
  -- 만 단위가 되면 referenced 를 임시 테이블로 뽑아 인덱스를 걸 것.
  select o.bucket_id::text, o.name::text
  from storage.objects o
  where o.bucket_id in ('club-logos', 'club-intro-images', 'club-posts')
    and o.created_at < now() - p_min_age
    and not exists (
      select 1 from referenced r where r.key = o.bucket_id || '/' || o.name
    );
$$;

comment on function public.orphan_club_image_objects(interval) is
  '참조가 끊긴 클럽 사진 Storage 객체 목록. storage-gc Edge Function(service_role) 전용.';

revoke all on function public.orphan_club_image_objects(interval)
  from public, anon, authenticated;
grant execute on function public.orphan_club_image_objects(interval)
  to service_role;

commit;

-- 새 함수를 PostgREST 스키마 캐시에 즉시 알린다(AGENTS/START-HERE 규칙 9).
-- 없으면 배포 직후 RPC 호출이 캐시 갱신 전까지 실패할 수 있다.
notify pgrst, 'reload schema';
