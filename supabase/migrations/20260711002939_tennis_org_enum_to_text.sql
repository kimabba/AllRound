-- 086: P3 전국확장 — tennis_org enum 탈출(enum → text FK).
--   enum 참조 3곳: user_tennis_orgs.org, tennis_tournament_details.host_orgs[],
--   함수 tournaments_for_user(반환+캐스트). 값 보존(라벨=tennis_orgs.code), 앱 투명.
--   비파괴 컬럼전환 → 함수재생성 → 타입드롭 순.

-- 1) user_tennis_orgs.org : enum → text + FK
alter table public.user_tennis_orgs
  alter column org type text using org::text;
alter table public.user_tennis_orgs
  add constraint user_tennis_orgs_org_fkey
  foreign key (org) references public.tennis_orgs(code);

-- 2) tennis_tournament_details.host_orgs : tennis_org[] → text[]
alter table public.tennis_tournament_details
  alter column host_orgs drop default;
alter table public.tennis_tournament_details
  alter column host_orgs type text[] using host_orgs::text[];
alter table public.tennis_tournament_details
  alter column host_orgs set default '{}'::text[];

-- 3) tournaments_for_user 재생성 (반환 host_orgs text[], p_host_org 캐스트 제거)
--    반환 타입 변경이라 CREATE OR REPLACE 불가 → DROP 후 CREATE.
--    071이 public.sport 파라미터 버전을 만든 뒤 072가 text 파라미터 버전을 별도로
--    만들면서 sport 오버로드가 남았다. 둘 다 tennis_org[]를 반환하므로 enum 삭제 전
--    명시적으로 제거해야 fresh reset에서 타입 의존성이 남지 않는다.
drop function if exists public.tournaments_for_user(
  uuid, public.sport, text, date, date, boolean, text,
  integer, integer, text, text
);

drop function if exists public.tournaments_for_user(uuid,text,text,date,date,boolean,text,integer,integer,text,text,text[],text);

create function public.tournaments_for_user(
  p_user_id uuid, p_sport text default null, p_region text default null,
  p_date_from date default null, p_date_to date default null,
  p_only_my_grade boolean default true, p_query text default null,
  p_limit integer default 50, p_offset integer default 0,
  p_region_code text default null, p_host_org text default null,
  p_division_codes text[] default null, p_recruiting text default null
)
returns table(
  id uuid, sport text, title text, organizer text, description text,
  start_date date, end_date date, application_deadline date, region text,
  region_code text, host_associations text[], location text, eligible_grades text[],
  division_label_local text, entry_fee integer, entry_fee_unit text, prize text,
  format text, source_url text, status text, created_at timestamptz,
  host_orgs text[], division_kta_standard text, division_gender text,
  division_age_group text, is_joint_event boolean, host_futsal_orgs futsal_org[],
  t_venue_type text, t_surface_type text, t_match_format text, t_player_count integer,
  t_team_count_max integer, t_roster_min integer, t_roster_max integer,
  futsal_event_category text
)
language sql stable
set search_path to 'public'
as $function$
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

-- 4) 미참조가 된 enum 타입 제거
drop type public.tennis_org;

notify pgrst, 'reload schema';
