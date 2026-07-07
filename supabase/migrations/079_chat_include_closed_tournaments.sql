-- 079: chat 대회 검색에서 마감(closed) 대회도 선택적으로 포함.
--
-- 배경: "이번 달 대회 일정 알려줘" 류 조회는 모집 마감 여부와 무관하게 일정 정보로
--       유효하다. 기존 RPC 는 status='published' 만 반환해, 이미 마감된 대회(status='closed')가
--       빠지면서 "조건에 맞는 대회가 없습니다" 가 자주 떴다.
-- 변경: p_include_closed(기본 false, 하위호환) 파라미터 추가. true 면 closed 도 포함.
--       정렬은 "다가오는 대회 먼저, 그다음 날짜순" 으로 바꿔 지난 대회가 위로 오지 않게 한다.
--       draft/rejected 는 여전히 제외.
CREATE OR REPLACE FUNCTION public.tournament_search_by_slots(
  p_user_id uuid,
  p_sport text DEFAULT NULL::text,
  p_region text DEFAULT NULL::text,
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
    AND (p_region IS NULL OR t.region = p_region OR t.region ILIKE '%' || p_region || '%')
    AND (p_date_from IS NULL OR coalesce(t.end_date, t.start_date) >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (
      p_recruiting IS NULL
      OR (p_recruiting = 'open' AND (t.application_deadline IS NULL OR t.application_deadline >= current_date))
      OR (p_recruiting = 'closed' AND t.application_deadline IS NOT NULL AND t.application_deadline < current_date)
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
  -- 다가오는 대회(coalesce(end,start) >= 오늘) 먼저, 그다음 시작일 오름차순.
  ORDER BY (coalesce(t.end_date, t.start_date) < current_date) ASC, t.start_date ASC, t.id
  LIMIT GREATEST(p_match_count, 1);
$function$;
