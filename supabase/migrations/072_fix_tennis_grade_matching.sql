-- 072: 테니스 등급 매칭 수정 — user_tennis_orgs.division_codes 기반으로 전환
--
-- 문제: user_sports.grade (경력 기반: y3to5)와 tournaments.eligible_grades
--       (협회 부서 코드: jn_m_general)는 다른 체계라서 절대 매칭 안 됨.
--
-- 수정: 테니스는 user_tennis_orgs.division_codes로 매칭.
--       광주(gj)/전남(jn) 동일 체계 교차 매칭 포함.
--       풋살은 기존 user_sports.grade 유지.
--
-- 영향: tournaments_for_user, tournament_search_by_slots 두 RPC.

-- ────────────────────────────────────────────────────────────────────
-- 헬퍼: 광주/전남 교차 매칭용 suffix 추출 + 교차 코드 배열 생성
-- gj_m_general → ['gj_m_general', 'jn_m_general']
-- kta_m_open   → ['kta_m_open'] (교차 대상 아님)
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.expand_gj_jn_codes(codes text[])
RETURNS text[]
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT array_agg(DISTINCT c) FROM (
    SELECT unnest(codes) AS c
    UNION
    SELECT
      CASE
        WHEN code LIKE 'gj_%' THEN 'jn_' || substring(code FROM 4)
        WHEN code LIKE 'jn_%' THEN 'gj_' || substring(code FROM 4)
        ELSE NULL
      END AS c
    FROM unnest(codes) AS code
  ) sub
  WHERE c IS NOT NULL;
$$;

-- ────────────────────────────────────────────────────────────────────
-- tournaments_for_user 재생성
-- ────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.tournaments_for_user(uuid, text, text, date, date, boolean, text, integer, integer, text, text);

CREATE FUNCTION public.tournaments_for_user(
  p_user_id uuid,
  p_sport text DEFAULT NULL,
  p_region text DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_only_my_grade boolean DEFAULT true,
  p_query text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_region_code text DEFAULT NULL,
  p_host_org text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  sport text,
  title text,
  organizer text,
  description text,
  start_date date,
  end_date date,
  application_deadline date,
  region text,
  region_code text,
  host_associations text[],
  location text,
  eligible_grades text[],
  division_label_local text,
  entry_fee integer,
  entry_fee_unit text,
  prize text,
  format text,
  source_url text,
  status text,
  created_at timestamptz,
  host_orgs public.tennis_org[],
  division_kta_standard text,
  division_gender text,
  division_age_group text,
  is_joint_event boolean,
  host_futsal_orgs public.futsal_org[],
  t_venue_type text,
  t_surface_type text,
  t_match_format text,
  t_player_count integer,
  t_team_count_max integer,
  t_roster_min integer,
  t_roster_max integer,
  futsal_event_category text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.sport::text,
    t.title,
    t.organizer,
    t.description,
    t.start_date,
    t.end_date,
    t.application_deadline,
    t.region,
    t.region_code,
    t.host_associations,
    t.location,
    t.eligible_grades,
    t.division_label_local,
    t.entry_fee,
    t.entry_fee_unit,
    t.prize,
    t.format,
    t.source_url,
    t.status::text,
    t.created_at,
    tt.host_orgs,
    tt.division_kta_standard,
    tt.division_gender,
    tt.division_age_group,
    tt.is_joint_event,
    ft.host_futsal_orgs,
    ft.venue_type,
    ft.surface_type,
    ft.match_format,
    ft.player_count,
    ft.team_count_max,
    ft.roster_min,
    ft.roster_max,
    ft.event_category
  FROM public.tournaments t
  LEFT JOIN public.tennis_tournament_details tt
    ON tt.tournament_id = t.id
  LEFT JOIN public.futsal_tournament_details ft
    ON ft.tournament_id = t.id
  WHERE t.status = 'published'
    AND (p_sport IS NULL OR t.sport::text = p_sport)
    AND (p_region IS NULL OR t.region = p_region)
    AND (p_region_code IS NULL OR t.region_code = p_region_code)
    AND (p_date_from IS NULL OR t.start_date >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (
      p_host_org IS NULL
      OR tt.host_orgs @> ARRAY[p_host_org::public.tennis_org]
    )
    AND (
      p_query IS NULL
      OR t.title ILIKE '%' || p_query || '%'
      OR COALESCE(t.organizer, '') ILIKE '%' || p_query || '%'
      OR COALESCE(t.description, '') ILIKE '%' || p_query || '%'
    )
    AND (
      NOT p_only_my_grade
      OR (
        -- 테니스: user_tennis_orgs.division_codes 기반 (광주/전남 교차 포함)
        (t.sport = 'tennis' AND EXISTS (
          SELECT 1 FROM public.user_tennis_orgs uto
          WHERE uto.user_id = p_user_id
            AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades
        ))
        OR
        -- 풋살: 기존 user_sports.grade 기반
        (t.sport = 'futsal' AND EXISTS (
          SELECT 1 FROM public.user_sports us
          WHERE us.user_id = p_user_id
            AND us.sport = t.sport
            AND us.grade = ANY(t.eligible_grades)
        ))
      )
    )
  ORDER BY t.start_date ASC, t.created_at DESC
  LIMIT GREATEST(p_limit, 0)
  OFFSET GREATEST(p_offset, 0);
$$;

-- ────────────────────────────────────────────────────────────────────
-- tournament_search_by_slots 재생성
-- ────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.tournament_search_by_slots(uuid, text, text, date, date, boolean, integer);

CREATE FUNCTION public.tournament_search_by_slots(
  p_user_id uuid,
  p_sport text DEFAULT NULL,
  p_region text DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_only_my_grade boolean DEFAULT true,
  p_match_count integer DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  sport text,
  title text,
  start_date date,
  end_date date,
  application_deadline date,
  region text,
  location text,
  eligible_grades text[],
  entry_fee integer,
  format text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    t.id, t.sport::text, t.title, t.start_date, t.end_date,
    t.application_deadline,
    t.region, t.location, t.eligible_grades, t.entry_fee, t.format
  FROM public.tournaments t
  WHERE t.status = 'published'
    AND (p_sport IS NULL OR t.sport::text = p_sport)
    AND (
      p_region IS NULL
      OR t.region = p_region
      OR t.region ILIKE '%' || p_region || '%'
    )
    AND (p_date_from IS NULL OR t.start_date >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (
      NOT p_only_my_grade
      OR (
        -- 테니스: user_tennis_orgs.division_codes 기반
        (t.sport = 'tennis' AND EXISTS (
          SELECT 1 FROM public.user_tennis_orgs uto
          WHERE uto.user_id = p_user_id
            AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades
        ))
        OR
        -- 풋살: 기존 user_sports.grade 기반
        (t.sport = 'futsal' AND EXISTS (
          SELECT 1 FROM public.user_sports us
          WHERE us.user_id = p_user_id
            AND us.sport = t.sport
            AND us.grade = ANY(t.eligible_grades)
        ))
      )
    )
  ORDER BY t.start_date ASC, t.id
  LIMIT GREATEST(p_match_count, 1);
$$;
