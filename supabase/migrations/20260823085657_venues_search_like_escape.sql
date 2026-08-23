-- venues_search 의 p_query 가 LIKE 메타문자(%, _)를 와일드카드로 그대로 써서
-- 대회검색(038_search_like_escape, 20260818150000_tournament_search_like_escape)과
-- 달리 구장검색만 이스케이프가 안 돼 있었다.
-- 실측: 검색창에 '%' 한 글자만 넣으면 전체 구장이 나온다.
--
-- 038과 같은 규칙: \ -> \\, % -> \%, _ -> \_ 후 ilike ... escape '\'.

CREATE OR REPLACE FUNCTION public.venues_search(
  p_sport      text     DEFAULT NULL,
  p_region     text     DEFAULT NULL,
  p_venue_type text     DEFAULT NULL,
  p_query      text     DEFAULT NULL,
  p_limit      integer  DEFAULT 20
)
RETURNS TABLE (
  id          uuid,
  sport       sport,
  name        text,
  region      text,
  region_code text,
  address     text,
  venue_type  text,
  court_count integer,
  phone       text,
  website     text
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  WITH q AS (
    SELECT replace(replace(replace(
             coalesce(p_query, ''), '\', '\\'), '%', '\%'), '_', '\_'
           ) AS term
  )
  SELECT v.id, v.sport, v.name, v.region, v.region_code,
         v.address, v.venue_type, v.court_count, v.phone, v.website
  FROM public.venues v, q
  WHERE (p_sport IS NULL OR v.sport::text = p_sport)
    AND (p_region IS NULL OR v.region = p_region OR v.region_code = p_region)
    AND (p_venue_type IS NULL OR v.venue_type = p_venue_type)
    AND (p_query IS NULL OR v.name ILIKE '%' || q.term || '%' ESCAPE '\'
         OR COALESCE(v.address, '') ILIKE '%' || q.term || '%' ESCAPE '\')
  ORDER BY v.region, v.name
  LIMIT GREATEST(p_limit, 1);
$function$;

GRANT EXECUTE ON FUNCTION public.venues_search(text, text, text, text, integer) TO authenticated;
