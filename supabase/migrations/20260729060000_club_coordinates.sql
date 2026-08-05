-- 사용자 요청 시에만 계산하는 주변 클럽 검색용 공개 클럽 좌표.

BEGIN;

ALTER TABLE public.clubs
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision;

ALTER TABLE public.clubs
  ADD CONSTRAINT clubs_latitude_range
    CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  ADD CONSTRAINT clubs_longitude_range
    CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  ADD CONSTRAINT clubs_coordinates_pair
    CHECK ((latitude IS NULL) = (longitude IS NULL));

CREATE INDEX clubs_coordinates_idx
  ON public.clubs (latitude, longitude)
  WHERE status = 'approved' AND latitude IS NOT NULL AND longitude IS NOT NULL;

COMMIT;
