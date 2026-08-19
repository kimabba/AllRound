-- KTA(대한테니스협회) 크롤 소스 등록.
--
-- 배경: 기존 koreatennis.or.kr(gnuboard) 소스 'tennis-korea'는 2026-05-21 사이트
-- 리뉴얼로 DNS 가 끊겨 enabled=false 로 방치돼 있었다(2026-08-19 확인). 협회가
-- join.kortennis.or.kr 로 완전히 새 시스템(커스텀 SPA)으로 이전했고, 옛 gnuboard
-- parser 는 재사용 불가 — 새 parser 'kta-sportsforall' 를 별도로 작성했다
-- (_shared/crawler/parsers/kta_sportsforall.ts).
--
-- 새 사이트는 로그인 없이 접근 가능한 JSON API 를 쓴다(실측 확인):
--   목록: /sportsForAll/sportsForAll_selList.json (사이트지역=sidoCd 필터는 대회
--     개최지가 아니라 리그 소속지사 분류로 보여 전부 ALL 로 받고, region_code 는
--     기존 관례대로 upsertTournament 가 location/title 텍스트에서 유도한다)
--   상세: /sportsForAll/sportsForAllRellyInfo.do?cmptEvntCd={code}&dtlSt=Tab1
--
-- org_code='kta'(부서사전 로드 키, tennis_orgs 에 이미 존재 — 20260710020000),
-- region_code=null(전국). enabled=false 초기값 — KATO/gwangju-gu 사례와 동일하게
-- 배포·라이브 검증(force 크롤로 draft 수집 확인) 후 관리자가 수동 활성화한다.

insert into public.crawl_sources
  (name, slug, url, sport, region, region_code, org_code, source_type,
   parser_module, schedule_cron, enabled, notes)
values
  (
    'KTA 생활체육대회 일정',
    'tennis-kta',
    'https://join.kortennis.or.kr/sportsForAll/sportsForAll_selList.json?cmptDtlGb=02&sidoCd=ALL&sigunguCd=ALL&cmptStat=&cmptNm=&type=4&strDt=2024-01-01&endDt=2029-12-31&selectSize=50&cntGbn=0&pageIndex=1',
    'tennis',
    null,
    null,
    'kta',
    'json_api',
    'kta-sportsforall',
    '50 21 * * *',
    false,
    '2026-05-21 사이트 리뉴얼로 옛 tennis-korea(gnuboard) 소스 폐기 후 재등록. '
    || '신규 사이트, 라이브 검증(force 크롤 → draft 수집 확인) 후 enabled=true.'
  )
on conflict (slug) do update set
  name = excluded.name,
  url = excluded.url,
  region_code = excluded.region_code,
  org_code = excluded.org_code,
  source_type = excluded.source_type,
  parser_module = excluded.parser_module,
  schedule_cron = excluded.schedule_cron,
  notes = excluded.notes;
