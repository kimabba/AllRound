-- 대회 검색어(p_query)에 지역·장소를 포함한다.
--
-- 배경: 앱의 검색창 안내 문구는 "대회명 또는 지역을 검색해보세요" 인데
-- 서버는 title/organizer/description 만 찾고 있었다. 홈에서는 앱이 받아둔
-- 목록을 직접 훑어 지역이 걸렸지만, 전체 대회 화면(서버 검색)에서는
-- "광주" 같은 지역명이 안 걸려 같은 검색어가 화면마다 다른 결과를 냈다.
-- 홈 검색을 전체 대회 화면으로 일원화하면서 서버 쪽 기준을 문구에 맞춘다.
--
-- 시그니처·반환형·나머지 술어는 그대로이며 p_query 조건에만 두 줄을 더한다.
-- CREATE OR REPLACE 이므로 기존 권한(GRANT)은 유지된다.

CREATE OR REPLACE FUNCTION public.tournaments_for_user(
  p_user_id uuid,
  p_sport text DEFAULT NULL::text,
  p_region text DEFAULT NULL::text,
  p_date_from date DEFAULT NULL::date,
  p_date_to date DEFAULT NULL::date,
  p_only_my_grade boolean DEFAULT true,
  p_query text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_region_code text DEFAULT NULL::text,
  p_host_org text DEFAULT NULL::text,
  p_division_codes text[] DEFAULT NULL::text[],
  p_recruiting text DEFAULT NULL::text
)
RETURNS TABLE(
  id uuid, sport text, title text, organizer text, description text,
  start_date date, end_date date, application_deadline date, region text,
  region_code text, host_associations text[], location text,
  eligible_grades text[], division_label_local text, entry_fee integer,
  entry_fee_unit text, prize text, format text, source_url text, status text,
  created_at timestamp with time zone, host_orgs text[],
  division_kta_standard text, division_gender text, division_age_group text,
  is_joint_event boolean, host_futsal_orgs futsal_org[], t_venue_type text,
  t_surface_type text, t_match_format text, t_player_count integer,
  t_team_count_max integer, t_roster_min integer, t_roster_max integer,
  futsal_event_category text
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT
    t.id, t.sport::text, t.title, t.organizer, t.description, t.start_date,
    t.end_date, t.application_deadline, t.region, t.region_code, t.host_associations,
    t.location, t.eligible_grades, t.division_label_local, t.entry_fee, t.entry_fee_unit,
    t.prize, t.format, t.source_url, t.status::text, t.created_at,
    tt.host_orgs, tt.division_kta_standard, tt.division_gender, tt.division_age_group,
    tt.is_joint_event, ft.host_futsal_orgs, ft.venue_type, ft.surface_type,
    ft.match_format, ft.player_count, ft.team_count_max, ft.roster_min, ft.roster_max,
    ft.event_category
  FROM public.tournaments t
  LEFT JOIN public.tennis_tournament_details tt ON tt.tournament_id = t.id
  LEFT JOIN public.futsal_tournament_details ft ON ft.tournament_id = t.id
  WHERE t.status = 'published'
    AND (p_sport IS NULL OR t.sport::text = p_sport)
    AND (p_region IS NULL OR t.region = p_region)
    AND (p_region_code IS NULL OR t.region_code = p_region_code)
    AND (p_date_from IS NULL OR coalesce(t.end_date, t.start_date) >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (p_host_org IS NULL OR tt.host_orgs @> ARRAY[p_host_org])
    AND (p_division_codes IS NULL OR p_division_codes && t.eligible_grades)
    AND (
      p_recruiting IS NULL
      OR (p_recruiting = 'open' AND (t.application_deadline IS NULL OR t.application_deadline >= current_date))
      OR (p_recruiting = 'closed' AND t.application_deadline IS NOT NULL AND t.application_deadline < current_date)
    )
    AND (
      p_query IS NULL
      OR t.title ILIKE '%' || p_query || '%'
      OR COALESCE(t.organizer, '') ILIKE '%' || p_query || '%'
      OR COALESCE(t.description, '') ILIKE '%' || p_query || '%'
      -- 추가: 지역·장소도 검색 대상에 포함
      OR COALESCE(t.region, '') ILIKE '%' || p_query || '%'
      OR COALESCE(t.location, '') ILIKE '%' || p_query || '%'
    )
    AND (
      NOT p_only_my_grade
      OR (
        (t.sport = 'tennis' AND EXISTS (
          SELECT 1 FROM public.user_tennis_orgs uto
          WHERE uto.user_id = p_user_id
            AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades
        ))
        OR
        (t.sport = 'futsal' AND EXISTS (
          SELECT 1 FROM public.user_sports us
          WHERE us.user_id = p_user_id AND us.sport = t.sport AND us.grade = ANY(t.eligible_grades)
        ))
      )
    )
  ORDER BY t.start_date ASC, t.created_at DESC
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
$function$;
