-- 071: Futsal grade expansion + official 2026 futsal event archive.
--
-- Sources:
--   - Korea Futsal Federation 생활체육: http://www.futsal.or.kr/LeagueList.action
--   - Korea Futsal Federation FK리그: http://www.futsal.or.kr/mng_GameList.action
--
-- Intent:
--   - Expand futsal skill levels to 입문/초급/중급/고급/선출.
--   - Preserve official 2026 schedules, including past events, for future news/archive tabs.
--   - Keep already-finished events as `closed` so they do not mix into active application lists.

BEGIN;

-- Futsal grades now use five levels:
-- intro(입문), beginner(초급), intermediate(중급), advanced(고급), elite(선출).
ALTER TABLE public.user_sports
  DROP CONSTRAINT IF EXISTS user_sports_grade_check;

ALTER TABLE public.user_sports
  ADD CONSTRAINT user_sports_grade_check CHECK (
    (sport = 'tennis' AND grade IN ('under1y', 'y1to3', 'y3to5', 'over5y'))
    OR
    (sport = 'futsal' AND grade IN ('intro', 'beginner', 'intermediate', 'advanced', 'elite'))
  );

ALTER TABLE public.futsal_tournament_details
  ADD COLUMN IF NOT EXISTS event_category text
    CHECK (event_category IN ('regional_federation', 'sports_for_all', 'private'));

COMMENT ON COLUMN public.futsal_tournament_details.event_category IS
  '풋살 대회 표시 분류: regional_federation(지역 풋살연맹), sports_for_all(생활체육대회), private(민간 풋살 대회)';

CREATE TEMP TABLE _official_futsal_events_2026 (
  title text NOT NULL,
  organizer text NOT NULL,
  description text NOT NULL,
  start_date date NOT NULL,
  end_date date,
  application_deadline date,
  region text,
  location text,
  region_code text,
  eligible_grades text[] NOT NULL,
  division_label_local text,
  format text,
  source_url text NOT NULL,
  source text NOT NULL,
  status public.tournament_status NOT NULL,
  host_futsal_orgs public.futsal_org[] NOT NULL,
  event_category text,
  venue_type text,
  surface_type text,
  match_format text,
  player_count integer,
  division_gender text,
  division_age_group text
) ON COMMIT DROP;

INSERT INTO _official_futsal_events_2026 (
  title, organizer, description, start_date, end_date, application_deadline,
  region, location, region_code, eligible_grades, division_label_local, format,
  source_url, source, status, host_futsal_orgs, event_category, venue_type,
  surface_type, match_format, player_count, division_gender, division_age_group
)
VALUES
  (
    '제13회 단양 소백산 철쭉배 전국풋살대회',
    '한국풋살연맹',
    '한국풋살연맹 생활체육 공식 목록 기준 2026년 클럽 대항 전국풋살대회입니다. 충청북도 단양군 단양공설운동장 및 매포생활체육공원에서 진행되었습니다.',
    DATE '2026-04-04',
    DATE '2026-04-05',
    DATE '2026-03-24',
    '충북',
    '충청북도 단양군 단양공설운동장 및 매포생활체육공원',
    'chungcheong',
    ARRAY['intro', 'beginner', 'intermediate', 'advanced', 'elite'],
    '클럽 대항',
    '전국풋살대회',
    'http://www.futsal.or.kr/LeagueList.action#69',
    'manual-kfl-sports-for-all',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'sports_for_all',
    'outdoor',
    'artificial_turf',
    'group_knockout',
    5,
    NULL,
    'open'
  ),
  (
    '2026 전국생활체육대축전 풋살대회',
    '한국풋살연맹',
    '한국풋살연맹 생활체육 공식 목록 기준 2026년 시도 대항 생활체육 풋살대회입니다. 경상남도 밀양시 밀양종합운동장 보조경기장에서 진행되었습니다.',
    DATE '2026-04-25',
    DATE '2026-04-26',
    DATE '2026-04-10',
    '경남',
    '밀양종합운동장 보조경기장',
    'busan_ulsan_gn',
    ARRAY['intro', 'beginner', 'intermediate', 'advanced', 'elite'],
    '시도 대항',
    '생활체육대축전',
    'http://www.futsal.or.kr/LeagueList.action#70',
    'manual-kfl-sports-for-all',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'sports_for_all',
    'outdoor',
    'artificial_turf',
    'group_knockout',
    5,
    NULL,
    'open'
  ),
  (
    '제27회 문화체육관광부장관기 전국풋살대회',
    '한국풋살연맹',
    '한국풋살연맹 생활체육 공식 목록 기준 2026년 시도 대항 전국풋살대회입니다. 충청북도 제천시 제천축구센터에서 진행되었습니다.',
    DATE '2026-05-09',
    DATE '2026-05-10',
    DATE '2026-04-30',
    '충북',
    '충청북도 제천시 제천축구센터',
    'chungcheong',
    ARRAY['intro', 'beginner', 'intermediate', 'advanced', 'elite'],
    '시도 대항',
    '전국풋살대회',
    'http://www.futsal.or.kr/LeagueList.action#71',
    'manual-kfl-sports-for-all',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'sports_for_all',
    'outdoor',
    'artificial_turf',
    'group_knockout',
    5,
    NULL,
    'open'
  ),
  (
    '제4회 대한축구협회장기 전국풋살대회',
    '대한축구협회·한국풋살연맹',
    '한국풋살연맹 생활체육 공식 목록 기준 2026년 클럽 대항 전국풋살대회입니다. 충청북도 단양군 단양공설운동장 외 경기장에서 진행되었습니다.',
    DATE '2026-06-06',
    DATE '2026-06-07',
    DATE '2026-05-27',
    '충북',
    '충청북도 단양군 단양공설운동장 외',
    'chungcheong',
    ARRAY['intro', 'beginner', 'intermediate', 'advanced', 'elite'],
    '클럽 대항',
    '전국풋살대회',
    'http://www.futsal.or.kr/LeagueList.action#72',
    'manual-kfl-sports-for-all',
    'closed',
    ARRAY['kfa', 'kfl']::public.futsal_org[],
    'sports_for_all',
    'outdoor',
    'artificial_turf',
    'group_knockout',
    5,
    NULL,
    'open'
  ),
  (
    '2026 만천하배 유·청소년 FK리그',
    '한국풋살연맹',
    '한국풋살연맹 생활체육 공식 목록 및 FK CUP·유청소년 목록 기준 2026년 유·청소년 FK리그입니다. 충청북도 단양군 국민체육센터 및 문화체육 관련 경기장에서 진행되었습니다.',
    DATE '2026-01-05',
    DATE '2026-01-09',
    DATE '2026-01-09',
    '충북',
    '충청북도 단양군 국민체육센터 및 문화체육 관련 경기장',
    'chungcheong',
    ARRAY['intro', 'beginner', 'intermediate', 'advanced'],
    '시도 대항 · 유청소년',
    '유·청소년 FK리그',
    'http://www.futsal.or.kr/LeagueList.action#68',
    'manual-kfl-sports-for-all',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'sports_for_all',
    'indoor',
    'wood_floor',
    'league',
    5,
    NULL,
    'youth'
  ),
  (
    'flex 2025-26 FK 리그(FK1)',
    '한국풋살연맹',
    '한국풋살연맹 FK리그 공식 일정 기준 2025-26 시즌 FK1 리그입니다. 각 팀 홈경기장 및 단양군에서 진행되었습니다. 일반 사용자 신청형 대회가 아닌 리그/소식성 일정입니다.',
    DATE '2025-11-15',
    DATE '2026-04-04',
    DATE '2025-11-07',
    '전국',
    '각 팀 홈경기장 및 단양군',
    NULL,
    ARRAY['elite'],
    'FK1',
    'FK리그',
    'http://www.futsal.or.kr/mng_GameList.action#108',
    'manual-kfl-league',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'regional_federation',
    'mixed',
    NULL,
    'league',
    5,
    'male',
    'open'
  ),
  (
    'flex 2025-26 FK 리그(FK2)',
    '한국풋살연맹',
    '한국풋살연맹 FK리그 공식 일정 기준 2025-26 시즌 FK2 리그입니다. 각 팀 홈경기장 및 단양군에서 진행되었습니다. 일반 사용자 신청형 대회가 아닌 리그/소식성 일정입니다.',
    DATE '2025-11-15',
    DATE '2026-04-04',
    DATE '2025-11-07',
    '전국',
    '각 팀 홈경기장 및 단양군',
    NULL,
    ARRAY['elite'],
    'FK2',
    'FK리그',
    'http://www.futsal.or.kr/mng_GameList.action#109',
    'manual-kfl-league',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'regional_federation',
    'mixed',
    NULL,
    'league',
    5,
    'male',
    'open'
  ),
  (
    'flex 2025-26 WFK 리그(여자부)',
    '한국풋살연맹',
    '한국풋살연맹 FK리그 공식 일정 기준 2025-26 시즌 WFK 여자부 리그입니다. 각 팀 홈경기장 및 단양군에서 진행되었습니다. 일반 사용자 신청형 대회가 아닌 리그/소식성 일정입니다.',
    DATE '2025-12-06',
    DATE '2026-03-28',
    DATE '2025-12-04',
    '전국',
    '각 팀 홈경기장 및 단양군',
    NULL,
    ARRAY['elite'],
    'WFK 여자부',
    'WFK리그',
    'http://www.futsal.or.kr/mng_GameList.action#110',
    'manual-kfl-league',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'regional_federation',
    'mixed',
    NULL,
    'league',
    5,
    'female',
    'open'
  ),
  (
    'flex 2025-26 FK리그 플레이오프',
    '한국풋살연맹',
    '한국풋살연맹 FK리그 공식 일정 기준 2025-26 시즌 플레이오프입니다. 상위팀 홈구장에서 진행되었습니다. 일반 사용자 신청형 대회가 아닌 리그/소식성 일정입니다.',
    DATE '2026-02-28',
    DATE '2026-04-04',
    DATE '2026-04-04',
    '전국',
    '상위팀 홈구장',
    NULL,
    ARRAY['elite'],
    '플레이오프',
    'FK리그 플레이오프',
    'http://www.futsal.or.kr/mng_GameList.action#112',
    'manual-kfl-league',
    'closed',
    ARRAY['kfl']::public.futsal_org[],
    'regional_federation',
    'mixed',
    NULL,
    'knockout_only',
    5,
    NULL,
    'open'
  );

INSERT INTO public.tournaments (
  sport,
  title,
  organizer,
  description,
  start_date,
  end_date,
  application_deadline,
  region,
  location,
  region_code,
  division_label_local,
  entry_fee_unit,
  eligible_grades,
  entry_fee,
  prize,
  format,
  source_url,
  source,
  status,
  embedding,
  embedding_updated_at
)
SELECT
  'futsal'::public.sport,
  title,
  organizer,
  description,
  start_date,
  end_date,
  application_deadline,
  region,
  location,
  region_code,
  division_label_local,
  'per_team',
  eligible_grades,
  NULL,
  NULL,
  format,
  source_url,
  source,
  status,
  NULL,
  NULL
FROM _official_futsal_events_2026
ON CONFLICT (source, source_url) WHERE source_url IS NOT NULL
DO UPDATE SET
  title = EXCLUDED.title,
  organizer = EXCLUDED.organizer,
  description = EXCLUDED.description,
  start_date = EXCLUDED.start_date,
  end_date = EXCLUDED.end_date,
  application_deadline = EXCLUDED.application_deadline,
  region = EXCLUDED.region,
  location = EXCLUDED.location,
  region_code = EXCLUDED.region_code,
  division_label_local = EXCLUDED.division_label_local,
  eligible_grades = EXCLUDED.eligible_grades,
  format = EXCLUDED.format,
  status = EXCLUDED.status,
  embedding = NULL,
  embedding_updated_at = NULL,
  updated_at = now();

INSERT INTO public.futsal_tournament_details (
  tournament_id,
  host_futsal_orgs,
  venue_type,
  surface_type,
  match_format,
  player_count,
  team_count_max,
  roster_min,
  roster_max,
  event_category
)
SELECT
  t.id,
  s.host_futsal_orgs,
  s.venue_type,
  s.surface_type,
  s.match_format,
  s.player_count,
  NULL,
  NULL,
  NULL,
  s.event_category
FROM _official_futsal_events_2026 s
JOIN public.tournaments t
  ON t.source = s.source
 AND t.source_url = s.source_url
ON CONFLICT (tournament_id)
DO UPDATE SET
  host_futsal_orgs = EXCLUDED.host_futsal_orgs,
  venue_type = EXCLUDED.venue_type,
  surface_type = EXCLUDED.surface_type,
  match_format = EXCLUDED.match_format,
  player_count = EXCLUDED.player_count,
  event_category = EXCLUDED.event_category;

-- Existing all-level futsal events should include the newly introduced intro/elite ends.
UPDATE public.tournaments
SET
  eligible_grades = ARRAY['intro', 'beginner', 'intermediate', 'advanced', 'elite'],
  embedding = NULL,
  embedding_updated_at = NULL,
  updated_at = now()
WHERE sport = 'futsal'
  AND eligible_grades = ARRAY['beginner', 'intermediate', 'advanced'];

-- Restore the app-facing RPC signature used by tournaments-search and include the futsal category.
DROP FUNCTION IF EXISTS public.tournaments_for_user(
  uuid,
  public.sport,
  text,
  date,
  date,
  boolean,
  text,
  integer,
  integer,
  text,
  text
);

DROP FUNCTION IF EXISTS public.tournaments_for_user(uuid, text, text, integer, integer);

CREATE OR REPLACE FUNCTION public.tournaments_for_user(
  p_user_id uuid,
  p_sport public.sport DEFAULT NULL,
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
    AND (p_sport IS NULL OR t.sport = p_sport)
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
      OR EXISTS (
        SELECT 1
        FROM public.user_sports us
        WHERE us.user_id = p_user_id
          AND us.sport = t.sport
          AND us.grade = ANY(t.eligible_grades)
      )
    )
  ORDER BY t.start_date ASC, t.created_at DESC
  LIMIT GREATEST(p_limit, 0)
  OFFSET GREATEST(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION public.tournaments_for_user(
  uuid,
  public.sport,
  text,
  date,
  date,
  boolean,
  text,
  integer,
  integer,
  text,
  text
) TO authenticated;

COMMIT;
