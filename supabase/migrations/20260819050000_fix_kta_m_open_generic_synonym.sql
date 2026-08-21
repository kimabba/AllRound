-- kta_m_open(남자오픈) 부서 동의어에서 지나치게 일반적인 '오픈' 을 제거한다.
--
-- 배경: KTA 크롤러(tennis-kta) 실측 검증 중 발견 — 대회 상세 텍스트에 거의 항상 나오는
-- "참가신청 오픈일시" 같은 상용구의 '오픈'이 substring 매칭으로 kta_m_open 에 오탐되어,
-- 크롤된 6개 대회 전부가 실제로는 없는 '남자오픈' 부서로 잘못 태깅됐다.
-- '남자오픈'(온전한 단어)만 남기고 bare '오픈'은 뺀다 — 이 동의어는 kta_m_open 하나뿐이었다.

update public.tennis_divisions
set synonyms = array['남자오픈']
where code = 'kta_m_open';
