-- 070: 기존 크롤 대회 description 정제 (raw zone 도입 후 후속)
--
-- 배경: a5fc923 이후 크롤러가 원문 본문을 description 에 통째로 넣어 일부 대회는
--   description 이 7000자 이상으로 비대해졌다. 원문 전체는 이제 crawl_documents
--   (raw zone)에 보존되므로, description 은 임베딩·표시용으로 축소한다.
--   (긴 잡음 텍스트는 tournaments_semantic_search 임베딩 품질을 떨어뜨림)
--
-- 처리: 실제 크롤 출처(crawl_sources.slug 에 등록된 source)만 대상.
--   어드민 수기(manual_description=true)·사용자 제보(user_submission)는 raw zone 이
--   없으므로 원문이 잘리면 안 되어 제외한다.
--   description 변경 → invalidate_tournament_embedding 트리거가 임베딩을 무효화 →
--   embed-pending 워커가 재계산.

update public.tournaments
set description = left(description, 1100) || ' …'
where not manual_description
  and length(description) > 1200
  and source in (select slug from public.crawl_sources);
