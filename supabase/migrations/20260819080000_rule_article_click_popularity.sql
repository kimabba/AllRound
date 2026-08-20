-- 룰북 클릭 집계 — 최근 24시간 인기 카테고리/규칙 카드용.
--
-- 같은 사용자가 같은 규칙을 반복해서 눌러 순위를 올리지 못하도록 24시간에
-- 한 번만 기록한다. 앱에는 사용자별 원본 기록을 노출하지 않고 집계 RPC만 연다.

begin;

create table public.rule_article_clicks (
  id bigint generated always as identity primary key,
  article_id uuid not null references public.rule_articles(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  clicked_at timestamptz not null default now()
);

create index rule_article_clicks_article_recent_idx
  on public.rule_article_clicks (article_id, clicked_at desc);

create index rule_article_clicks_user_article_recent_idx
  on public.rule_article_clicks (user_id, article_id, clicked_at desc);

alter table public.rule_article_clicks enable row level security;

create policy rule_article_clicks_admin_read
  on public.rule_article_clicks
  for select
  to authenticated
  using (public.is_admin());

revoke all on table public.rule_article_clicks from public, anon, authenticated;
grant select on table public.rule_article_clicks to authenticated;
grant all on table public.rule_article_clicks to service_role;

comment on table public.rule_article_clicks is
  '룰북 규칙 열람 클릭. 같은 사용자·규칙은 record_rule_article_click RPC가 최근 24시간 중복을 제거한다.';

create or replace function public.record_rule_article_click(p_article_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.rule_articles r
    where r.id = p_article_id
      and r.published
  ) then
    return false;
  end if;

  -- 같은 사용자·규칙의 동시 탭도 한 건만 남긴다.
  perform pg_advisory_xact_lock(
    hashtextextended(v_user_id::text || ':' || p_article_id::text, 0)
  );

  if exists (
    select 1
    from public.rule_article_clicks c
    where c.user_id = v_user_id
      and c.article_id = p_article_id
      and c.clicked_at >= now() - interval '24 hours'
  ) then
    return false;
  end if;

  insert into public.rule_article_clicks (article_id, user_id)
  values (p_article_id, v_user_id);

  return true;
end;
$$;

comment on function public.record_rule_article_click(uuid) is
  '로그인 사용자가 규칙을 열 때 호출. 같은 사용자·규칙은 최근 24시간에 한 번만 기록한다.';

revoke execute on function public.record_rule_article_click(uuid)
  from public, anon;
grant execute on function public.record_rule_article_click(uuid)
  to authenticated, service_role;

create or replace function public.popular_rule_highlight_24h(p_sport public.sport)
returns table (
  article_id uuid,
  sport public.sport,
  category text,
  title text,
  article_click_count bigint,
  category_click_count bigint,
  window_started_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with article_counts as (
    select
      r.id as article_id,
      r.sport,
      r.category,
      r.title,
      count(c.id)::bigint as article_click_count
    from public.rule_article_clicks c
    join public.rule_articles r on r.id = c.article_id
    where c.clicked_at >= now() - interval '24 hours'
      and r.published
      and r.sport = p_sport
    group by r.id, r.sport, r.category, r.title
  ), ranked as (
    select
      a.*,
      sum(a.article_click_count) over (
        partition by a.category
      )::bigint as category_click_count,
      row_number() over (
        partition by a.category
        order by a.article_click_count desc, a.article_id
      ) as article_rank
    from article_counts a
  )
  select
    r.article_id,
    r.sport,
    r.category,
    r.title,
    r.article_click_count,
    r.category_click_count,
    now() - interval '24 hours' as window_started_at
  from ranked r
  where r.article_rank = 1
  order by
    r.category_click_count desc,
    r.article_click_count desc,
    r.category,
    r.article_id
  limit 1
$$;

comment on function public.popular_rule_highlight_24h(public.sport) is
  '최근 24시간 유효 클릭 합계가 가장 높은 카테고리와 그 안의 최다 클릭 규칙을 반환한다.';

revoke execute on function public.popular_rule_highlight_24h(public.sport)
  from public, anon;
grant execute on function public.popular_rule_highlight_24h(public.sport)
  to authenticated, service_role;

commit;
