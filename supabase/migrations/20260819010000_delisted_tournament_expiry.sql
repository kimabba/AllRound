-- 목록이탈 대회 자동 만료. 설계: docs/superpowers/specs 없음(backend-architect 인라인 검토,
-- 대화 기록 참고) — 크롤러는 목록에 없는 게시물을 재방문하지 않아 죽은 published 대회가
-- 영원히 남는다(우천 연기·행사 취소로 원본이 내려간 경우 등).
--
-- tournaments.last_seen_at: 크롤러가 이 대회를 마지막으로 "목록에서" 본 시각. 파서가
--   listing 파싱 직후(ended 필터·CAP 적용 전) 전체 url 에 찍는다(markListingSeen) —
--   상세 파싱 성공 여부와 무관하게 목록 등장이 기준이어야 오탐이 없다.
-- tournaments.delisted_at: 목록이탈로 auto-close 된 시각. 날짜-close(start_date 지남)와
--   구분해야 tournament_status.ts 의 되살리기(날짜 교정 시 closed→published)가 이걸
--   침범하지 않는다.
-- crawl_sources.last_listing_parsed_at: 그 소스가 실제로 "전체 목록을 훑은" 마지막 시각
--   (no_change/error/빈 목록 제외). 목록이탈 판정에 "그 이후 재확인이 실제로 있었음"을
--   보장하는 하한선 — 사이트가 조용하거나 셀렉터가 깨져도 대량 오폐쇄가 안 나는 핵심 가드.

begin;

alter table public.tournaments
  add column last_seen_at timestamptz,
  add column delisted_at timestamptz;

alter table public.crawl_sources
  add column last_listing_parsed_at timestamptz;

commit;
