BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(14);

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

INSERT INTO storage.objects (bucket_id, name, owner_id)
VALUES (
  'club-logos',
  'qa-storage-delete-test.jpg',
  '00000000-0000-4000-8000-000000000008'
);

SELECT is(
  (SELECT count(*) FROM storage.objects
   WHERE name = 'qa-storage-delete-test.jpg'),
  1::bigint,
  '탈퇴 테스트용 공개 Storage 객체가 준비됐다'
);

UPDATE public.clubs
SET logo_url =
  'http://local/storage/v1/object/public/club-logos/qa-storage-delete-test.jpg'
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
     AND object_name = 'qa-storage-delete-test.jpg'),
  1::bigint,
  'Edge Function이 실제 Storage 파일을 제거할 경로를 삭제 후에도 조회한다'
);

SELECT * FROM finish();
ROLLBACK;
