BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(21);

SELECT is(
  (SELECT count(*) FROM storage.buckets
   WHERE id IN ('club-logos', 'club-intro-images', 'club-posts')
     AND public = true),
  3::bigint,
  '클럽 공개 이미지 버킷 세 개만 공개 URL을 사용한다'
);

SELECT is(
  (SELECT public FROM storage.buckets WHERE id = 'ugc-report-evidence'),
  false,
  '신고 증거 버킷은 비공개다'
);

SELECT is(
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND policyname IN (
       'club_logos_public_read',
       'club_intro_images_public_read'
     )),
  0::bigint,
  '공개 URL과 별개로 객체 목록 전체를 노출하는 SELECT 정책은 제거됐다'
);

SELECT is(
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND cmd = 'INSERT'
     AND policyname IN (
       'club_logos_owner_insert',
       'club_intro_images_owner_insert',
       'club_posts_storage_insert',
       'ugc_report_evidence_insert'
     )
     AND with_check LIKE '%owner_id%'
     AND with_check LIKE '%has_verified_signup_age%'),
  4::bigint,
  '모든 이미지 업로드는 JWT 소유권과 서버 연령 확인을 함께 요구한다'
);

SELECT is(
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND cmd = 'SELECT'
     AND policyname IN (
       'club_logos_owner_select',
       'club_intro_images_owner_select',
       'club_posts_storage_select'
     )
     AND qual LIKE '%owner_id%'),
  3::bigint,
  '공개 버킷의 객체 목록은 업로더 본인에게만 보인다'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.public_storage_paths_owned_by(uuid)',
    'EXECUTE'
  ),
  '익명 사용자는 탈퇴용 Storage 목록 함수를 호출할 수 없다'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.public_storage_paths_owned_by(uuid)',
    'EXECUTE'
  ),
  '일반 사용자는 다른 계정의 탈퇴용 Storage 목록을 조회할 수 없다'
);

SELECT ok(
  has_function_privilege(
    'service_role',
    'public.public_storage_paths_owned_by(uuid)',
    'EXECUTE'
  ),
  'service role만 탈퇴용 Storage 목록을 조회할 수 있다'
);

SELECT is(
  (SELECT count(*)
   FROM pg_constraint AS constraint_row
   JOIN pg_class AS source_table
     ON source_table.oid = constraint_row.conrelid
   JOIN pg_namespace AS source_schema
     ON source_schema.oid = source_table.relnamespace
   WHERE constraint_row.contype = 'f'
     AND source_schema.nspname = 'public'
     AND constraint_row.confrelid = 'public.users'::regclass
     AND constraint_row.confdeltype IN ('a', 'r')),
  0::bigint,
  'public.users를 참조하는 FK가 회원 탈퇴를 NO ACTION/RESTRICT로 막지 않는다'
);

-- 파일명은 앱이 만드는 형식(48자리 hex)이어야 URL 제약을 통과한다.
-- 클럽 ...201 등 픽스처는 scripts/qa/run_db_tests.sh 가 먼저 로드하는
-- supabase/qa/personas.sql 에 있다(psql 로 이 파일만 직접 돌리면 없다).
INSERT INTO storage.objects (bucket_id, name, owner_id)
VALUES (
  'club-logos',
  repeat('a1', 24) || '.jpg',
  '00000000-0000-4000-8000-000000000008'
);

SELECT is(
  (SELECT count(*) FROM storage.objects
   WHERE name = repeat('a1', 24) || '.jpg'),
  1::bigint,
  '탈퇴 테스트용 공개 Storage 객체가 준비됐다'
);

-- 사진 URL 은 우리 Storage 공개 경로만 허용한다. 열려 있으면 앱을 거치지 않은 쓰기가
-- 외부 서버 이미지를 클럽 소개·게시글에 심어 열람자 IP 를 수집하거나, 검수 후 원격에서
-- 이미지 내용만 바꿔치기할 수 있다.
SELECT throws_ok(
  $$UPDATE public.clubs
      SET logo_url = 'https://evil.example.com/storage/v1/object/public/club-logos/x.jpg'
    WHERE id = '00000000-0000-4000-8000-000000000201'$$,
  '23514',
  NULL,
  '외부 도메인 로고 URL 은 CHECK 제약이 거부한다'
);

SELECT throws_ok(
  $$UPDATE public.clubs
      SET intro_image_urls = ARRAY['https://evil.example.com/x.jpg']
    WHERE id = '00000000-0000-4000-8000-000000000201'$$,
  '23514',
  NULL,
  '외부 도메인 소개 사진 URL 은 CHECK 제약이 거부한다'
);

SELECT is(
  (SELECT count(*) FROM pg_constraint
    WHERE conname IN (
      'clubs_logo_url_is_app_storage',
      'clubs_intro_image_urls_are_app_storage',
      'club_posts_image_urls_are_app_storage'
    )),
  3::bigint,
  '로고·소개 사진·게시글 사진 세 컬럼 모두 URL 형식 제약을 가진다'
);

-- ── 고아 사진 정리(storage-gc) 대상 판정 ──────────────────────────────
-- 되돌릴 수 없는 삭제라, 살아있는 사진이 목록에 들어가지 않는 것이 핵심이다.
INSERT INTO storage.objects (bucket_id, name, owner_id, created_at)
VALUES
  ('club-posts', repeat('d4', 24) || '.jpg',
   '00000000-0000-4000-8000-000000000008', now() - interval '30 days'),
  ('club-posts', repeat('e5', 24) || '.jpg',
   '00000000-0000-4000-8000-000000000008', now()),
  ('club-intro-images', repeat('b2', 24) || '.jpg',
   '00000000-0000-4000-8000-000000000008', now() - interval '30 days'),
  ('club-posts', repeat('c3', 24) || '.jpg',
   '00000000-0000-4000-8000-000000000008', now() - interval '30 days');

UPDATE public.clubs
SET intro_image_urls = ARRAY[
  'https://bsjdgwmveokanclqwtvx.supabase.co/storage/v1/object/public/club-intro-images/'
  || repeat('b2', 24) || '.jpg'
]
WHERE id = '00000000-0000-4000-8000-000000000201';

INSERT INTO public.ugc_reports (target_type, target_id, reason, content_snapshot)
VALUES (
  'club_post',
  '00000000-0000-4000-8000-000000000901',
  'other',
  jsonb_build_object(
    'image_urls',
    jsonb_build_array(
      'https://bsjdgwmveokanclqwtvx.supabase.co/storage/v1/object/public/club-posts/'
      || repeat('c3', 24) || '.jpg'
    )
  )
);

SELECT is(
  (SELECT count(*) FROM public.orphan_club_image_objects()
    WHERE object_name = repeat('d4', 24) || '.jpg'),
  1::bigint,
  '아무 글에도 안 걸린 오래된 사진은 정리 대상이다'
);

SELECT is(
  (SELECT coalesce(string_agg(object_name, ', ' ORDER BY object_name), '(없음)')
     FROM public.orphan_club_image_objects()
    WHERE object_name IN (
      repeat('e5', 24) || '.jpg',
      repeat('b2', 24) || '.jpg',
      repeat('c3', 24) || '.jpg'
    )),
  '(없음)',
  '방금 올린 사진·글에 걸린 사진·신고 스냅샷이 참조하는 사진은 정리 대상이 아니다'
);

SELECT is(
  (SELECT count(*) FROM public.orphan_club_image_objects(interval '60 days')
    WHERE object_name = repeat('d4', 24) || '.jpg'),
  0::bigint,
  '기준 나이를 늘리면 그보다 최근 사진은 목록에서 빠진다'
);

-- 사용 중인 사진 주소에 fragment 를 붙여 정리 작업이 원본을 고아로 오판하게 만드는
-- 우회(codex CRITICAL). 경로 형식 고정으로 저장 자체가 막혀야 한다.
SELECT throws_ok(
  format(
    $$UPDATE public.clubs SET intro_image_urls = ARRAY[%L] WHERE id = %L$$,
    'https://bsjdgwmveokanclqwtvx.supabase.co/storage/v1/object/public/club-intro-images/'
      || repeat('b2', 24) || '.jpg#x',
    '00000000-0000-4000-8000-000000000201'
  ),
  '23514',
  NULL,
  '사용 중인 사진 주소에 fragment 를 붙인 값은 거부한다'
);

DELETE FROM public.ugc_reports
WHERE target_id = '00000000-0000-4000-8000-000000000901';
UPDATE public.clubs SET intro_image_urls = '{}'
WHERE id = '00000000-0000-4000-8000-000000000201';

-- clubs_logo_url_is_app_storage 제약이 생긴 뒤로 픽스처도 실제 앱이 저장하는
-- 형식이어야 한다. 로컬 seed 는 로컬 호스트도 열어주지만, 프로덕션과 같은 판정을
-- 검증하려고 프로덕션 호스트로 쓴다(문자열 대조라 실제 접속은 없다).
UPDATE public.clubs
SET logo_url =
  'https://bsjdgwmveokanclqwtvx.supabase.co/storage/v1/object/public/club-logos/'
  || repeat('a1', 24) || '.jpg'
WHERE id = '00000000-0000-4000-8000-000000000201';

SELECT lives_ok(
  $$SELECT public.delete_account_data(
    '00000000-0000-4000-8000-000000000008'
  )$$,
  '공유 FK와 공개 사진이 있어도 계정 데이터 삭제가 완료된다'
);

SELECT is(
  (SELECT count(*) FROM public.users
   WHERE id = '00000000-0000-4000-8000-000000000008'),
  0::bigint,
  '탈퇴한 사용자의 public.users 행이 삭제됐다'
);

SELECT is(
  (SELECT logo_url FROM public.clubs
   WHERE id = '00000000-0000-4000-8000-000000000201'),
  NULL::text,
  '탈퇴한 사용자가 소유한 공개 사진 URL 참조가 제거됐다'
);

SELECT is(
  (SELECT count(*)
   FROM public.public_storage_paths_owned_by(
     '00000000-0000-4000-8000-000000000008'
   )
   WHERE bucket_id = 'club-logos'
     AND object_name = repeat('a1', 24) || '.jpg'),
  1::bigint,
  'Edge Function이 실제 Storage 파일을 제거할 경로를 삭제 후에도 조회한다'
);

SELECT * FROM finish();
ROLLBACK;
