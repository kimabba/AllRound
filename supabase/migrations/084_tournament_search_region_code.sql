-- 084: tournament_search_by_slots 오버로드 정리(JY-105) + 지역 필터 region_code 기반 통일(JY-104)
--
-- 문제:
--   1) [JY-105] 079가 CREATE OR REPLACE 로 p_include_closed 를 추가했으나 인자 수가
--      8→9 로 달라 replace 가 아닌 새 오버로드가 생성됨. 078(8-param)/079(9-param)이
--      pg_proc 에 공존 → 8개 named args 호출 시 42725(function is not unique).
--   2) [JY-104] 지역 필터가 한글 라벨(p_region="수도권")로 t.region("경기·인천")을 비교해
--      데이터가 있어도 항상 0건. 정규 코드 컬럼 t.region_code("seoul_metro")가 이미
--      채워져 있으므로 코드 기반으로 통일한다.
--
-- 변경:
--   - 8-param/9-param 두 시그니처를 모두 DROP 후, p_region 을 p_region_code 로 바꾼
--     단일 함수로 재생성(파라미터명 변경이라 CREATE OR REPLACE 불가 → DROP 필요).
--   - 지역 필터: t.region_code = p_region_code. 전국(region_code NULL, region='전국')
--     대회는 모든 지역 검색에 포함(전국 대회는 지역 무관 유효).
--   - 나머지 로직(마감 포함/모집상태/등급/정렬)은 079와 동일.

DROP FUNCTION IF EXISTS public.tournament_search_by_slots(uuid, text, text, date, date, boolean, integer, text);
DROP FUNCTION IF EXISTS public.tournament_search_by_slots(uuid, text, text, date, date, boolean, integer, text, boolean);

CREATE FUNCTION public.tournament_search_by_slots(
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

GRANT EXECUTE ON FUNCTION public.tournament_search_by_slots(
  uuid, text, text, date, date, boolean, integer, text, boolean
) TO authenticated;

-- PostgREST 스키마 캐시 리로드(오버로드 정리 반영).
NOTIFY pgrst, 'reload schema';
