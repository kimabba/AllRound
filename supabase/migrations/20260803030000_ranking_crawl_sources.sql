-- 협회 랭킹 크롤 소스 + 부서 단위 교체 RPC
--
-- 소스는 협회당 1건. 파서가 랭킹 부서 7개를 순회한다(부서별 URL 을 소스로 쪼개면
-- 14건이 되고 부서 추가마다 소스 관리가 따라온다).
--
-- cron 시각: 실제 실행은 전체 크롤 소스 공통의 단일 스케줄러(pg_cron 'crawl-dispatch',
-- '0 21 * * *' = UTC 21:00 = KST 06:00, 20260710010000_crawl_daily_schedule.sql)가
-- 하루 1회 담당한다. 아래 schedule_cron 컬럼 값('10 22 * * *' / '20 22 * * *')은
-- 현재 dispatcher(crawl-dispatch/index.ts)가 평가하지 않는 참고용 값이다 —
-- dispatcher 가 소스별 정밀 스케줄을 지원하게 되면 그때 쓰일 예정.

begin;

-- ═══════════════════════════════════════════════
-- 부서 단위 교체 — delete + insert 를 한 트랜잭션으로
--   PostgREST 로 나눠 쏘면 별도 커밋이라, delete 성공 후 insert 실패 시
--   그 부서가 다음 크롤(최대 24h)까지 빈 채로 남는다. 한 함수로 묶으면
--   그 조합 자체가 불가능해진다.
-- ═══════════════════════════════════════════════
create or replace function public.replace_org_ranking_division(
  p_org        text,
  p_division   text,
  p_source_url text,
  p_rows       jsonb
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted int;
begin
  -- 빈 배열로 기존 데이터를 지우는 사고를 막는다(파서에도 0행 가드가 있으나 2중으로).
  if p_rows is null or jsonb_array_length(p_rows) = 0 then
    raise exception 'replace_org_ranking_division: 빈 목록으로 % / % 를 교체할 수 없다',
      p_org, p_division;
  end if;

  delete from public.org_rankings
  where org_code = p_org and division_code = p_division;

  insert into public.org_rankings
    (org_code, division_code, rank, player_name, org_player_id,
     club_raw, rank_points, total_points, source_url)
  select
    p_org,
    p_division,
    (r ->> 'rank')::int,
    r ->> 'player_name',
    r ->> 'org_player_id',
    r ->> 'club_raw',
    (r ->> 'rank_points')::int,
    (r ->> 'total_points')::int,
    p_source_url
  from jsonb_array_elements(p_rows) as r;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

comment on function public.replace_org_ranking_division is
  '한 협회·부서의 랭킹 미러를 한 트랜잭션으로 교체한다. service_role 전용(크롤러).';

revoke all on function public.replace_org_ranking_division(text, text, text, jsonb) from public;
grant execute on function public.replace_org_ranking_division(text, text, text, jsonb)
  to service_role;

-- ═══════════════════════════════════════════════
-- 크롤 소스 2건
-- ═══════════════════════════════════════════════
insert into public.crawl_sources
  (slug, name, url, sport, region, region_code, org_code, source_type,
   parser_module, schedule_cron, enabled, notes)
values
  ('tennis-gwangju-ranking', '광주테니스협회 부서별랭킹',
   'https://gjtennis.kr', 'tennis', '광주', 'gwangju', 'gj', 'board',
   'gnuboard-ranking', '10 22 * * *', true,
   '부서 7개 순회. 0점 선수 미저장. 협회 동의 하에 크롤.'),
  ('tennis-jeonnam-ranking', '전남테니스협회 부서별랭킹',
   'https://jntennis.kr', 'tennis', '전남', 'jeonnam', 'jn', 'board',
   'gnuboard-ranking', '20 22 * * *', true,
   '광주와 동일 CMS. 2026년부터 광주와 랭킹 분리 운영.')
on conflict (slug) do nothing;

commit;
