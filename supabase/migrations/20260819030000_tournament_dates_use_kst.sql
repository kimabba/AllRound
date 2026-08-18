-- 대회 날짜 판정을 KST 로 고정 — current_date(=UTC) 제거.
--
-- 문제:
--   이 DB 의 TimeZone 은 UTC 다(실측: current_setting('TimeZone') = 'UTC').
--   그래서 `current_date` 는 한국 시각 00:00~09:00 동안 아직 "어제"를 가리킨다.
--   서비스는 한국 대상이고 서버 자동 마감(_shared/tournament_status.ts)·채팅
--   날짜 슬롯(chat/index.ts todayKst)·앱 카드의 '종료' 배지는 모두 KST 로
--   판정하므로, 그 9시간 동안만 DB 판정이 하루 어긋난다.
--
--   눈에 보이는 증상 (한국 새벽에 앱을 켰을 때):
--     1) 채팅 대회 카드 — 어제 끝난 대회가 '다가오는 대회' 그룹에 섞여 정렬된다.
--     2) 대회 목록 '접수 중' 필터 — 어제 마감된 대회가 하루 더 접수 중으로 보인다.
--
-- 변경:
--   `current_date` → `(now() AT TIME ZONE 'Asia/Seoul')::date` (총 5곳).
--   now() 는 트랜잭션 시각(timestamptz)이라 세션 타임존과 무관하고,
--   AT TIME ZONE 이 그 절대시각을 한국 벽시계로 옮긴 뒤 날짜만 취한다.
--   함수 본문 외 나머지(시그니처·반환형·필터·정렬 순서)는 그대로다.
--
--   DB 전체 타임존(ALTER DATABASE ... SET timezone)은 건드리지 않는다 —
--   timestamptz 를 읽는 모든 쿼리·PostgREST 응답·로그 표기가 함께 바뀌어
--   영향 범위가 이 버그보다 훨씬 넓다.
--
-- 범위 밖(같은 UTC 원인이지만 이번에 고치지 않는 것):
--   - enforce_min_signup_age / has_verified_signup_age / before_user_created_allround
--     만 나이 게이트. 법적 요건이라 별도 검토 후 처리한다.
--   - replace_org_ranking_division 의 captured_on. 랭킹 스냅샷 날짜.
--
-- 시그니처가 그대로라 CREATE OR REPLACE 로 교체한다(079 처럼 인자 수가 달라져
-- 오버로드가 새로 생기는 사고를 피하려면 인자 목록을 손대지 않아야 한다).
-- REPLACE 는 기존 EXECUTE 권한을 유지하므로 GRANT 를 다시 주지 않는다.

CREATE OR REPLACE FUNCTION public.tournament_search_by_slots(
  p_user_id uuid,
  p_sport text DEFAULT NULL::text,
  p_region_code text DEFAULT NULL::text,
  p_date_from date DEFAULT NULL::date,
  p_date_to date DEFAULT NULL::date,
  p_only_my_grade boolean DEFAULT true,
  p_match_count integer DEFAULT 10,
  p_recruiting text DEFAULT NULL::text,
  p_include_closed boolean DEFAULT false
)
RETURNS TABLE(
  id uuid, sport text, title text, start_date date, end_date date,
  application_deadline date, region text, location text, eligible_grades text[],
  entry_fee integer, format text, regulation_fields jsonb
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT
    t.id, t.sport::text, t.title, t.start_date, t.end_date,
    t.application_deadline,
    t.region, t.location, t.eligible_grades, t.entry_fee, t.format,
    t.regulation_fields
  FROM public.tournaments t
  WHERE (t.status = 'published' OR (p_include_closed AND t.status = 'closed'))
    AND (p_sport IS NULL OR t.sport::text = p_sport)
    -- 지역: region_code 정확 일치 + 전국 대회는 항상 포함.
    AND (
      p_region_code IS NULL
      OR t.region_code = p_region_code
      OR t.region = '전국'
    )
    AND (p_date_from IS NULL OR coalesce(t.end_date, t.start_date) >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (
      p_recruiting IS NULL
      OR (p_recruiting = 'open' AND (t.application_deadline IS NULL OR t.application_deadline >= (now() AT TIME ZONE 'Asia/Seoul')::date))
      OR (p_recruiting = 'closed' AND t.application_deadline IS NOT NULL AND t.application_deadline < (now() AT TIME ZONE 'Asia/Seoul')::date)
    )
    AND (
      NOT p_only_my_grade
      OR (
        (t.sport = 'tennis' AND EXISTS (
          SELECT 1 FROM public.user_tennis_orgs uto
          WHERE uto.user_id = p_user_id AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades
        ))
        OR
        (t.sport = 'futsal' AND EXISTS (
          SELECT 1 FROM public.user_sports us
          WHERE us.user_id = p_user_id AND us.sport = t.sport AND us.grade = ANY(t.eligible_grades)
        ))
      )
    )
  -- 다가오는 대회(coalesce(end,start) >= 오늘 KST) 먼저, 그다음 시작일 오름차순.
  ORDER BY (coalesce(t.end_date, t.start_date) < (now() AT TIME ZONE 'Asia/Seoul')::date) ASC, t.start_date ASC, t.id
  LIMIT GREATEST(p_match_count, 1);
$function$;

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
  region_code text, host_associations text[], location text, eligible_grades text[],
  division_label_local text, entry_fee integer, entry_fee_unit text, prize text,
  format text, source_url text, status text, created_at timestamp with time zone,
  host_orgs text[], division_kta_standard text, division_gender text,
  division_age_group text, is_joint_event boolean, host_futsal_orgs futsal_org[],
  t_venue_type text, t_surface_type text, t_match_format text, t_player_count integer,
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
      OR (p_recruiting = 'open' AND (t.application_deadline IS NULL OR t.application_deadline >= (now() AT TIME ZONE 'Asia/Seoul')::date))
      OR (p_recruiting = 'closed' AND t.application_deadline IS NOT NULL AND t.application_deadline < (now() AT TIME ZONE 'Asia/Seoul')::date)
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
