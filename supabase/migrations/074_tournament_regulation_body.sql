-- 074: 대회 요강 완전 본문 — regulation_body 추가
--
-- 배경:
--   073 의 regulation_fields 는 원본 표의 단순 2칸 "라벨:값" 화이트리스트
--   (장소/주최/주관/후원/협찬/사용구/시상)만 구조화한다. 그 결과 같은 표 안의
--   풍부한 내용 — 시상내역 상세(우승 110만원 …), 경기부서·참가자격(만20세↑,
--   등급 1.0~4.0), 경기일정+입금계좌(3칼럼), 접수마감 상세(◈ 줄) — 이
--   화이트리스트에 안 걸려 누락됐고, 앱이 구조화 필드가 있으면 description 을
--   숨기면서 화면에서 완전히 사라졌다.
--
-- 해결:
--   크롤러가 원본 콘텐츠 <table> 의 행 구조를 살려(평문화 X) 누락 없는
--   "읽기 쉬운 완전 본문"으로 재구성해 regulation_body 에 저장한다.
--   regulation_fields(요약) 행과 ※ 안내문(regulation_notes)은 제외해 중복을 막고,
--   나머지 풍부한 내용(일정/계좌/시상내역/참가자격/접수마감 등)만 담는다.
--   앱은 [핵심 요약 필드] + [전체 요강 본문] + [안내] 순으로 모두 표시한다.
--
-- 노출:
--   상세 화면은 select('*') 로 재조회하므로 컬럼 추가만으로 자동 노출.
--   목록 RPC 미변경(요강 미사용). 기존 RLS 정책이 신규 컬럼 커버.

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS regulation_body text;

COMMENT ON COLUMN public.tournaments.regulation_body IS
  '대회 요강 완전 본문. 원본 콘텐츠 표를 행 단위 줄바꿈으로 재구성한 읽기 쉬운 텍스트. regulation_fields(요약)·regulation_notes(※) 제외분 — 시상내역/참가자격/경기일정/입금계좌/접수마감 등.';
