-- 018_tournament_search_by_slots.sql
-- Day 5-6: tournament_search intent routing 용 slot-based SQL.
-- 임베딩 / RAG 우회 → input 토큰 + Gemini API 호출 완전 제거.
--
-- 배경:
--   - intent classifier 가 tournament_search 로 분류하고 confidence ≥ 0.95 일 때만
--     chat/index.ts 가 이 함수를 호출 (LLM 우회 → 템플릿 응답).
--   - 신뢰도 미달 또는 다른 의도는 기존 RAG+LLM 흐름 그대로 (fallback).
--
-- region 매핑:
--   - intent.ts slots.region 은 코드 ('gwangju', 'jeonnam' 등) 지만
--     tournaments.region 컬럼은 한글 문자열 ('광주', '전남' 등).
--   - chat/index.ts 에서 REGION_LABELS 로 코드 → 한글 매핑 후 RPC 호출.
--   - 변환 누락/오타에 대한 보수적 안전망으로 RPC 내부는 equality + ilike 동시 매칭.
--
-- 권한:
--   - SECURITY INVOKER + RLS: tournaments 의 published 행만 노출.
--   - user_sports 매칭은 호출자 자신의 행을 보는 것이 정상 케이스이지만
--     edge function 은 user JWT 로 supabase.rpc() 호출하므로 RLS 통해 자기 행만 접근.

create or replace function public.tournament_search_by_slots(
  p_user_id uuid,
  p_sport text default null,           -- intent.ts 의 sport 슬롯 ('tennis' | 'futsal' | null)
  p_region text default null,          -- 한글 region 라벨 ('광주' 등) 또는 null
  p_date_from date default null,
  p_date_to date default null,
  p_only_my_grade boolean default true,
  p_match_count int default 10
)
returns table (
  id uuid,
  sport sport,
  title text,
  start_date date,
  end_date date,
  region text,
  location text,
  eligible_grades text[],
  entry_fee integer,
  format text
)
language sql
stable
security invoker
as $$
  select
    t.id, t.sport, t.title, t.start_date, t.end_date,
    t.region, t.location, t.eligible_grades, t.entry_fee, t.format
  from public.tournaments t
  where t.status = 'published'
    and (p_sport is null or t.sport::text = p_sport)
    and (
      p_region is null
      or t.region = p_region
      or t.region ilike '%' || p_region || '%'
    )
    and (p_date_from is null or t.start_date >= p_date_from)
    and (p_date_to is null or t.start_date <= p_date_to)
    and (
      not p_only_my_grade
      or exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      )
    )
  order by t.start_date asc, t.id
  limit greatest(p_match_count, 1);
$$;

grant execute on function public.tournament_search_by_slots(uuid, text, text, date, date, boolean, int) to authenticated;
