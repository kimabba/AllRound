-- 업로드 개수 제한 (보안 점검 3번 항목 4).
--
-- profile-avatars 스토리지 정책은 지금까지 폴더만 auth.uid()로 제한하고
-- 파일명은 제한하지 않아, 로그인한 사용자가 자기 폴더 안에 임의 파일명으로
-- 무제한 업로드할 수 있었다(3MB 제한 버킷 x 무제한 개수).
--
-- 앱은 이미 avatar.jpg / avatar.png 고정 경로만 쓴다(app/lib/services/user_api.dart
-- uploadProfileAvatar). 파일명을 그 두 가지로 고정하면 사용자당 최대 2객체·6MB로
-- 실질적인 개수 상한이 생긴다.
--
-- 설계 검토: backend-architect(Fable). rate_limits 재사용 트리거안을 검토했으나,
-- 그 방식은 users.avatar_url UPDATE 커밋 시점만 막아 실제 업로드(storage.objects
-- insert) 자체는 못 막고, 관리자 프로필 수정도 quota를 소모하는 등 결함이 있어
-- 대신 이 정책 수정으로 대체했다.

BEGIN;

DROP POLICY IF EXISTS profile_avatars_owner_insert ON storage.objects;
CREATE POLICY profile_avatars_owner_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
    AND name IN (
      (SELECT auth.uid()::text) || '/avatar.jpg',
      (SELECT auth.uid()::text) || '/avatar.png'
    )
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS profile_avatars_owner_update ON storage.objects;
CREATE POLICY profile_avatars_owner_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
  )
  WITH CHECK (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
    AND name IN (
      (SELECT auth.uid()::text) || '/avatar.jpg',
      (SELECT auth.uid()::text) || '/avatar.png'
    )
    AND (SELECT public.has_verified_signup_age())
  );

COMMIT;
