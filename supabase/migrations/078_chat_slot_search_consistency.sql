-- 078: 채팅 슬롯검색(tournament_search_by_slots)을 목록 RPC(076)와 일치 + 카드 요강
--
-- 검토 후속:
--   1) 날짜 필터를 start_date 단일 비교 → 오버랩 술어로 (목록 076 과 동일).
--   2) p_recruiting('open'/'closed') 모집상태 필터 추가 — 채팅이 마감 대회를
--      제안하지 않도록(채팅은 'open' 기본 전달).
--   3) regulation_fields(jsonb) 반환 추가 — 채팅 카드에 요강 요약 노출용.
--   기존 시그니처/로직은 동일.

DROP FUNCTION IF EXISTS public.tournament_search_by_slots(uuid, text, text, date, date, boolean, integer);

CREATE FUNCTION public.tournament_search_by_slots(
  p_user_id uuid,
  p_sport text DEFAULT NULL,
  p_region text DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_only_my_grade boolean DEFAULT true,
  p_match_count integer DEFAULT 10,
  p_recruiting text DEFAULT NULL
)
RETURNS TABLE(
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
  format text,
  regulation_fields jsonb
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
  WHERE t.status = 'published'
    AND (p_sport IS NULL OR t.sport::text = p_sport)
    AND (
      p_region IS NULL
      OR t.region = p_region
      OR t.region ILIKE '%' || p_region || '%'
    )
    -- 날짜 오버랩 (목록 076 과 동일): 다중일 대회 누락 방지.
    AND (p_date_from IS NULL OR coalesce(t.end_date, t.start_date) >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    -- 모집상태: 신청 마감일 기준.
    AND (
      p_recruiting IS NULL
      OR (p_recruiting = 'open'
          AND (t.application_deadline IS NULL OR t.application_deadline >= current_date))
      OR (p_recruiting = 'closed'
          AND t.application_deadline IS NOT NULL
          AND t.application_deadline < current_date)
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
  ORDER BY t.start_date ASC, t.id
  LIMIT GREATEST(p_match_count, 1);
$function$;
