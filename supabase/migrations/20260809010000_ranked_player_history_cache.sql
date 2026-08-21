-- 랭킹 선수 이력 온디맨드 캐시
--
-- 전 선수 수천 명을 매일 순회하지 않는다. 사용자가 랭킹표에서 선수를 열 때만
-- Edge Function 이 협회 공개 이력을 가져오고, 이 테이블의 갱신 시각을 기준으로
-- 24시간 동안 재사용한다. org_player_results 의 기존 본인 전용 RLS 는 넓히지 않는다.

begin;

create table public.org_player_history_fetches (
  org_code text not null check (org_code in ('gj', 'jn')),
  org_player_id text not null,
  fetched_at timestamptz not null default now(),
  result_count integer not null default 0 check (result_count >= 0),
  is_complete boolean not null default true,
  primary key (org_code, org_player_id)
);

comment on table public.org_player_history_fetches is
  '랭킹 선수 개인 이력의 온디맨드 수집 시각. 실명·성적은 담지 않는다.';

alter table public.org_player_history_fetches enable row level security;

-- authenticated 에 SELECT 권한은 주되 정책을 만들지 않아 직접 조회 결과는 0행이다.
-- Edge Function 의 service_role 만 RLS 를 우회해 캐시 상태를 읽고 쓴다.
grant select on public.org_player_history_fetches to authenticated, service_role;
grant insert, update, delete on public.org_player_history_fetches to service_role;
revoke all on public.org_player_history_fetches from anon;

create or replace function public.replace_org_player_history(
  p_org text,
  p_org_player_id text,
  p_rows jsonb,
  p_is_complete boolean
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  if p_org not in ('gj', 'jn') then
    raise exception 'replace_org_player_history: 지원하지 않는 협회 %', p_org;
  end if;
  if p_org_player_id is null or btrim(p_org_player_id) = '' then
    raise exception 'replace_org_player_history: 선수 ID가 필요합니다';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'replace_org_player_history: p_rows는 배열이어야 합니다';
  end if;
  if p_is_complete is null then
    raise exception 'replace_org_player_history: 수집 완료 여부가 필요합니다';
  end if;
  if not exists (
    select 1
      from public.org_rankings r
     where r.org_code = p_org
       and r.org_player_id = p_org_player_id
  ) then
    raise exception 'replace_org_player_history: 현재 랭킹에 없는 선수입니다';
  end if;

  delete from public.org_player_results
   where org_code = p_org
     and org_player_id = p_org_player_id;

  if jsonb_array_length(p_rows) > 0 then
    insert into public.org_player_results
      (org_code, org_player_id, tournament_name, played_on,
       event_raw, result_raw, result_round, points, fetched_at)
    select
      p_org,
      p_org_player_id,
      r ->> 'tournament_name',
      (r ->> 'played_on')::date,
      nullif(r ->> 'event_raw', ''),
      r ->> 'result_raw',
      nullif(r ->> 'result_round', '')::integer,
      coalesce(nullif(r ->> 'points', '')::integer, 0),
      now()
    from jsonb_array_elements(p_rows) as r;
    get diagnostics v_count = row_count;
  end if;

  insert into public.org_player_history_fetches
    (org_code, org_player_id, fetched_at, result_count, is_complete)
  values (p_org, p_org_player_id, now(), v_count, p_is_complete)
  on conflict (org_code, org_player_id)
  do update set
    fetched_at = excluded.fetched_at,
    result_count = excluded.result_count,
    is_complete = excluded.is_complete;

  return v_count;
end;
$$;

comment on function public.replace_org_player_history(text, text, jsonb, boolean) is
  '현재 랭킹 선수 한 명의 협회 공개 이력을 원자적으로 교체하고 캐시 시각을 기록한다.';

revoke all on function public.replace_org_player_history(text, text, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function public.replace_org_player_history(text, text, jsonb, boolean)
  to service_role;

commit;
