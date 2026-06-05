-- 046: venues table — 전국 풋살/테니스 구장 정보
-- 출처: 한국 풋살연맹 (futsal.or.kr) 등
-- GitHub #14 기획 연계

CREATE TABLE IF NOT EXISTS public.venues (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
  sport         sport NOT NULL,
  name          text NOT NULL,
  region        text NOT NULL,          -- 시/도 단위 (서울시, 광주시, 전라남도 등)
  region_code   text REFERENCES public.regions(code),
  address       text,                   -- 상세 주소
  venue_type    text NOT NULL DEFAULT 'unknown'
                CHECK (venue_type IN ('indoor', 'outdoor', 'mixed', 'unknown')),
  court_count   integer,                -- 코트/구장 수
  phone         text,
  website       text,
  source        text,                   -- 데이터 출처 (futsal.or.kr 등)
  verified_at   timestamptz,            -- 마지막 검증일
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS venues_sport_region ON public.venues (sport, region);
CREATE INDEX IF NOT EXISTS venues_region_code ON public.venues (region_code) WHERE region_code IS NOT NULL;

-- RLS
ALTER TABLE public.venues ENABLE ROW LEVEL SECURITY;

-- 모든 인증 사용자가 조회 가능 (공개 데이터)
CREATE POLICY venues_select ON public.venues
  FOR SELECT TO authenticated
  USING (true);

-- 삽입/수정/삭제는 admin만
CREATE POLICY venues_admin_insert ON public.venues
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY venues_admin_update ON public.venues
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY venues_admin_delete ON public.venues
  FOR DELETE TO authenticated
  USING (public.is_admin());
