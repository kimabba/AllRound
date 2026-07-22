-- clubs.logo_url 복구 (프로덕션 드리프트 정정)
--
-- 036_club_logos.sql 은 프로덕션에 부분 적용됐다 — storage 버킷 `club-logos` 는
-- 존재하지만 이 컬럼이 없다 (2026-07-22 확인, 이력 정합화 중 발견).
-- 로컬/신규 DB 는 036 이 정상 실행되므로 이 마이그레이션은 no-op 이다.
--
-- 이미 적용된 두 함수가 이 컬럼을 참조해 프로덕션에서 42703 으로 깨져 있었다:
--   * delete_account_data()  (20260719013000_harden_storage_privacy)
--     → `UPDATE public.clubs SET logo_url = NULL ...` 에서 실패.
--       supabase/functions/delete-account 의 계정 삭제가 통째로 실패한다.
--   * create_ugc_report()    (20260715120000_ugc_moderation)
--     → 클럽 신고 스냅샷의 `'logo_url', c.logo_url` 에서 실패.
--
-- 버킷과 storage 정책은 20260719013000_harden_storage_privacy.sql 이 소유한다.
-- 여기서 다시 만들면 하드닝 이전의 공개 읽기 정책이 부활하므로 건드리지 않는다.

alter table public.clubs
  add column if not exists logo_url text;

comment on column public.clubs.logo_url is
  '클럽 로고 공개 URL (storage 버킷 club-logos). 계정 삭제 시 delete_account_data() 가 NULL 로 정리한다.';

notify pgrst, 'reload schema';
