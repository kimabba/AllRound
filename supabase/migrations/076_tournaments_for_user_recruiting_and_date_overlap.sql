-- 076: tournaments_for_user — 모집상태(p_recruiting) 서버 필터 + 다중일 날짜 오버랩
--
-- Codex 리뷰 후속:
--   1) 모집상태(모집중/마감)를 클라이언트 측(limit:100 이후) 필터에서 RPC 로 이전
--      → 대량 데이터에서 누락 없음.
--   2) 날짜 필터를 start_date 단일 비교 → 오버랩 술어로 변경
--      → 범위 이전 시작 + end_date 로 겹치는 다중일 대회가 누락되지 않음.
--
-- 변경:
--   - p_recruiting text 파라미터 추가(맨 끝, 기본 NULL):
--       'open'   : application_deadline IS NULL OR application_deadline >= current_date
--       'closed' : application_deadline IS NOT NULL AND application_deadline < current_date
--       NULL/그외 : 필터 없음
--   - 날짜: (coalesce(end_date,start_date) >= p_date_from) AND (start_date <= p_date_to)
--   - 그 외 시그니처/로직은 075 와 동일.

DROP FUNCTION IF EXISTS public.tournaments_for_user(uuid, text, text, date, date, boolean, text, integer, integer, text, text, text[]);

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
  p_host_org text DEFAULT NULL,
  p_division_codes text[] DEFAULT NULL,
  p_recruiting text DEFAULT NULL
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
    -- 날짜 오버랩: 대회 기간[start, coalesce(end,start)] 이 [from, to] 와 겹치면 통과.
    AND (p_date_from IS NULL OR coalesce(t.end_date, t.start_date) >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (
      p_host_org IS NULL
      OR tt.host_orgs @> ARRAY[p_host_org::public.tennis_org]
    )
    AND (p_division_codes IS NULL OR p_division_codes && t.eligible_grades)
    -- 모집상태: 신청 마감일(application_deadline) 기준.
    AND (
      p_recruiting IS NULL
      OR (p_recruiting = 'open'
          AND (t.application_deadline IS NULL OR t.application_deadline >= current_date))
      OR (p_recruiting = 'closed'
          AND t.application_deadline IS NOT NULL
          AND t.application_deadline < current_date)
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
        (t.sport = 'tennis' AND EXISTS (
          SELECT 1 FROM public.user_tennis_orgs uto
          WHERE uto.user_id = p_user_id
            AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades
        ))
        OR
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
