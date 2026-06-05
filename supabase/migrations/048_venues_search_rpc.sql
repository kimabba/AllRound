-- 048: venues_search RPC + intent_examples constraint update

-- 1) venues_search RPC — 구장 검색 (chat + 향후 UI 공용)
CREATE OR REPLACE FUNCTION public.venues_search(
  p_sport     text     DEFAULT NULL,
  p_region    text     DEFAULT NULL,
  p_venue_type text    DEFAULT NULL,
  p_query     text     DEFAULT NULL,
  p_limit     integer  DEFAULT 20
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
LANGUAGE sql STABLE
AS $$
  SELECT v.id, v.sport, v.name, v.region, v.region_code,
         v.address, v.venue_type, v.court_count, v.phone, v.website
  FROM public.venues v
  WHERE (p_sport IS NULL OR v.sport::text = p_sport)
    AND (p_region IS NULL OR v.region = p_region OR v.region_code = p_region)
    AND (p_venue_type IS NULL OR v.venue_type = p_venue_type)
    AND (p_query IS NULL OR v.name ILIKE '%' || p_query || '%'
         OR COALESCE(v.address, '') ILIKE '%' || p_query || '%')
  ORDER BY v.region, v.name
  LIMIT GREATEST(p_limit, 1);
$$;

GRANT EXECUTE ON FUNCTION public.venues_search(text, text, text, text, integer) TO authenticated;

-- 2) intent_examples constraint update
ALTER TABLE public.intent_examples DROP CONSTRAINT IF EXISTS intent_examples_intent_check;
ALTER TABLE public.intent_examples ADD CONSTRAINT intent_examples_intent_check
  CHECK (intent = ANY(ARRAY['tournament_search','tournament_detail','club_search','rule_lookup','venue_search','match_schedule','my_profile','free_chat']));
