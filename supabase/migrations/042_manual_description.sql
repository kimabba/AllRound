-- 042: 수동 편집 description 보호 플래그
-- 크롤러가 수동 편집한 description을 덮어쓰지 않도록 한다.
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS manual_description boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tournaments.manual_description IS
  'true이면 크롤러가 description을 덮어쓰지 않음. 어드민 수기 편집 시 자동 설정.';
