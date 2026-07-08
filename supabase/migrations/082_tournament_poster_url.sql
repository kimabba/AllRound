-- 082: 대회 포스터 이미지 링크
--
-- 사용자가 대회 제보 시 포스터 이미지 URL을 함께 남길 수 있게 한다.
-- 실제 이미지 업로드/Storage는 별도 작업으로 두고, 현재는 외부 https/http 이미지 링크만 저장한다.

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS poster_url text;

COMMENT ON COLUMN public.tournaments.poster_url IS
  '대회 포스터 이미지 URL. 사용자 제보/관리자 승인 흐름에서 선택 입력한다.';
