-- 070: 기존 크롤 대회 description 정제 (raw zone 도입 후 후속)
--
-- 배경: a5fc923 이후 크롤러가 원문 본문을 description 에 통째로 넣어 일부 대회는
--   description 이 7000자 이상으로 비대해졌다. 원문 전체는 이제 crawl_documents
--   (raw zone)에 보존되므로, description 은 임베딩·표시용으로 축소한다.
--   (긴 잡음 텍스트는 tournaments_semantic_search 임베딩 품질을 떨어뜨림)
--
-- 처리: 원문이 crawl_documents(raw zone)에 실제로 보존된 행만 truncate 한다.
--   raw 사본이 없으면(pre-raw-zone 행, saveRawDocument 실패 등) description 이
--   유일한 원문이므로 자르면 영구 손실 → 반드시 raw document 존재를 전제로 한다.
--   어드민 수기(manual_description=true)·사용자 제보는 애초에 raw 가 없어 자동 제외됨.
--   description 변경 → invalidate_tournament_embedding 트리거가 임베딩 무효화 →
--   embed-pending 워커가 재계산.

update public.tournaments t
set description = left(t.description, 1100) || ' …'
where not t.manual_description
  and length(t.description) > 1200
  and exists (
    select 1 from public.crawl_documents cd where cd.tournament_id = t.id
  );
