-- 050: clubs.active 레거시 컬럼 제거
-- 031에서 status(pending/approved/rejected)로 전환 완료.
-- 032에서 active 기반 RLS 정책 제거 완료.
-- active 컬럼은 더 이상 어디서도 참조되지 않음.

-- 1) active 기반 인덱스 재생성 (where 절 제거)
DROP INDEX IF EXISTS clubs_sport_region_idx;
CREATE INDEX clubs_sport_region_idx ON public.clubs (sport, region);

-- 2) active 컬럼 제거
ALTER TABLE public.clubs DROP COLUMN IF EXISTS active;
