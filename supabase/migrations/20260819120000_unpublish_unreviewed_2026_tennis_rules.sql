-- 도메인 담당자 검수 전인 ITF 2026 테니스 요약 18건을 사용자 화면에서 내린다.
-- 기존 테니스 랭킹 규정 33건은 유지하고, 레코드는 추후 준모 검수 때 재사용할 수 있게 보존한다.

begin;

update public.rule_articles
set
  published = false,
  embedding = null,
  embedding_updated_at = null
where sport = 'tennis'
  and published
  and title like '2026%'
  and body like '%www.itftennis.com/%';

commit;
