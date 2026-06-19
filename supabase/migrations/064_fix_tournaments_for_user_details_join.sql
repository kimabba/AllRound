-- 064: tournaments_for_user 를 059 확장 분리 후 스키마에 맞게 수정 (P0 프로덕션 장애)
--
-- 배경:
--   059_tournament_extension_tables 에서 host_orgs / division_kta_standard /
--   player_count 등을 tennis/futsal_tournament_details 로 옮기고 tournaments 에서
--   DROP 했으나, 044 의 tournaments_for_user 는 여전히 t.host_orgs 등 삭제된
--   컬럼을 SELECT/필터해서 호출 시 "column t.host_orgs does not exist" 로 실패.
--   tournaments-search Edge Function 이 이 RPC 를 호출하므로 대회 검색이 깨진 상태였음.
--
-- 수정:
--   반환 타입·필터·등급 매칭 로직은 044 그대로 유지하고, details 테이블을
--   LEFT JOIN 해서 옮겨간 컬럼의 출처만 td/fd 로 교체.
--   (futsal_tournament_details 에 없는 team_count_current 는 null 로 반환)

DROP FUNCTION IF EXISTS public.tournaments_for_user(
  uuid, sport, text, date, date, boolean, text, integer, integer, text, text
);

CREATE OR REPLACE FUNCTION public.tournaments_for_user(
  p_user_id       uuid,
  p_sport         sport    DEFAULT NULL,
  p_region        text     DEFAULT NULL,
  p_date_from     date     DEFAULT NULL,
  p_date_to       date     DEFAULT NULL,
  p_only_my_grade boolean  DEFAULT true,
  p_query         text     DEFAULT NULL,
  p_limit         integer  DEFAULT 50,
  p_offset        integer  DEFAULT 0,
  p_region_code   text     DEFAULT NULL,
  p_host_org      text     DEFAULT NULL
)
RETURNS TABLE (
  id                   uuid,
  sport                sport,
  title                text,
  organizer            text,
  description          text,
  start_date           date,
  end_date             date,
  application_deadline date,
  region               text,
  location             text,
  eligible_grades      text[],
  entry_fee            integer,
  entry_fee_unit       text,
  prize                text,
  format               text,
  source_url           text,
  source               text,
  status               tournament_status,
  submitted_by         uuid,
  approved_by          uuid,
  approved_at          timestamptz,
  rejection_reason     text,
  created_at           timestamptz,
  updated_at           timestamptz,
  region_code          text,
  host_associations    text[],
  host_orgs            tennis_org[],
  division_label_local text,
  division_kta_standard text,
  is_joint_event       boolean,
  player_count         integer,
  division_gender      text,
  division_age_group   text,
  team_count_max       integer,
  team_count_current   integer,
  roster_min           integer,
  roster_max           integer,
  venue_type           text,
  surface_type         text,
  match_format         text,
  host_futsal_orgs     futsal_org[],
  manual_description   boolean
)
LANGUAGE sql STABLE
AS $function$
  with q as (
    select replace(replace(replace(
             coalesce(p_query, ''), '\', '\\'), '%', '\%'), '_', '\_'
           ) as term
  )
  select
    t.id, t.sport, t.title, t.organizer, t.description,
    t.start_date, t.end_date, t.application_deadline,
    t.region, t.location, t.eligible_grades,
    t.entry_fee, t.entry_fee_unit, t.prize, t.format, t.source_url, t.source,
    t.status, t.submitted_by, t.approved_by, t.approved_at, t.rejection_reason,
    t.created_at, t.updated_at,
    t.region_code, t.host_associations, td.host_orgs,
    t.division_label_local, td.division_kta_standard, coalesce(td.is_joint_event, false),
    fd.player_count, td.division_gender, td.division_age_group,
    fd.team_count_max, null::integer as team_count_current, fd.roster_min, fd.roster_max,
    fd.venue_type, fd.surface_type, fd.match_format,
    fd.host_futsal_orgs, t.manual_description
  from public.tournaments t
    left join public.tennis_tournament_details td on td.tournament_id = t.id
    left join public.futsal_tournament_details fd on fd.tournament_id = t.id,
    q
  where t.status = 'published'
    and (p_sport is null or t.sport = p_sport)
    and (p_region is null or t.region = p_region)
    and (p_region_code is null or t.region_code = p_region_code)
    and (p_host_org is null or td.host_orgs @> ARRAY[p_host_org::tennis_org])
    and (p_date_from is null or t.start_date >= p_date_from)
    and (p_date_to is null or t.start_date <= p_date_to)
    and (
      p_query is null
      or t.title ilike '%' || q.term || '%' escape '\'
      or coalesce(t.organizer, '') ilike '%' || q.term || '%' escape '\'
      or coalesce(t.description, '') ilike '%' || q.term || '%' escape '\'
    )
    and (
      not p_only_my_grade
      or (t.sport = 'tennis' and exists (
        select 1 from public.user_tennis_orgs uto
        where uto.user_id = p_user_id
          and uto.division_codes && t.eligible_grades
      ))
      or (t.sport = 'tennis'
        and exists (
          select 1 from public.user_sports us
          where us.user_id = p_user_id and us.sport = 'tennis'
        )
        and not exists (
          select 1 from public.user_tennis_orgs uto
          where uto.user_id = p_user_id
        )
      )
      or (t.sport != 'tennis' and exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      ))
    )
  order by t.start_date asc, t.created_at desc
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
$function$;
