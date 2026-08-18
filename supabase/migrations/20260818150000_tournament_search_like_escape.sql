-- 검색어의 LIKE 메타문자(%, _, \)를 리터럴로 취급한다.
--
-- 배경: 038 에서 넣었던 이스케이프가 이후 함수 재생성(075/076/enum→text) 과정에서
-- 빠진 채로 남아 있었다. 실측 — 검색창에 '%' 한 글자만 넣으면 전체 대회가 나온다.
-- SQL 인젝션은 아니지만(파라미터 바인딩), 사용자가 친 글자가 글자로 취급되지 않아
-- 검색 결과가 어긋난다. 홈 검색을 전체 대회 화면으로 일원화(#426)하면서 이 경로를
-- 쓰는 빈도가 올라갔으므로 함께 정리한다.
--
-- 별도 헬퍼 함수를 두지 않고 038 과 같이 쿼리 안에서 한 번만 계산한다.
-- public 에 새 함수를 만들면 anon 실행 권한을 함께 열어야 하고(SECURITY INVOKER 라
-- 호출자 권한으로 내부 함수를 부른다), 그만큼 공개 표면이 늘어난다.

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
  -- 검색어의 LIKE 메타문자를 리터럴로 바꿔 한 번만 계산한다(038 과 같은 규칙).
  CROSS JOIN LATERAL (
    SELECT replace(replace(replace(
             coalesce(p_query, ''), '\', '\\'), '%', '\%'), '_', '\_'
           ) AS term
  ) q
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
      OR t.title ILIKE '%' || q.term || '%' ESCAPE '\'
      OR COALESCE(t.organizer, '') ILIKE '%' || q.term || '%' ESCAPE '\'
      OR COALESCE(t.description, '') ILIKE '%' || q.term || '%' ESCAPE '\'
      OR COALESCE(t.region, '') ILIKE '%' || q.term || '%' ESCAPE '\'
      OR COALESCE(t.location, '') ILIKE '%' || q.term || '%' ESCAPE '\'
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
