-- 012_search_like_escape.sql
-- SEC-M-01 (검색 정확도/하드닝): tournaments_for_user 의 p_query 가
-- ilike 패턴에 그대로 보간되어 사용자 입력의 %, _, \ 가 와일드카드로 동작.
-- SQL injection 은 아니지만 (parameterized), 검색 정확도·예측 가능성을 위해
-- LIKE 메타문자를 리터럴로 escape 한다.
--
-- escape 규칙: \ → \\, % → \%, _ → \_  후 `ilike ... escape '\'`.

create or replace function public.tournaments_for_user(
  p_user_id uuid,
  p_sport sport default null,
  p_region text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_only_my_grade boolean default true,
  p_query text default null,
  p_limit int default 50,
  p_offset int default 0
)
returns setof public.tournaments
language sql
stable
security invoker
as $$
  with q as (
    select replace(replace(replace(
             coalesce(p_query, ''), '\', '\\'), '%', '\%'), '_', '\_'
           ) as term
  )
  select t.*
  from public.tournaments t, q
  where t.status = 'published'
    and (p_sport is null or t.sport = p_sport)
    and (p_region is null or t.region = p_region)
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
      or exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      )
    )
  order by t.start_date asc, t.created_at desc
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
$$;

grant execute on function public.tournaments_for_user(uuid, sport, text, date, date, boolean, text, int, int) to authenticated;
