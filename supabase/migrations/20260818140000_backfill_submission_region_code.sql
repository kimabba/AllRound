-- 제보로 들어온 대회의 region_code 백필.
--
-- 배경: 지역 필터(전체 대회 화면·챗봇)는 region_code 정확매칭으로 거르는데,
-- 제보 경로(tournaments-submit)는 앱이 보내는 자유 입력 region 만 저장하고
-- region_code 를 채우지 않았다. 그래서 "부산"으로 등록된 대회 2건이 있는데도
-- 지역에서 부산을 고르면 0건이 나왔다(실측). 크롤러는 #32(2026-06)에서 같은
-- 처리를 했지만 제보 경로가 빠져 있었다 — 앞으로 들어오는 건은 같은 PR 의
-- tournaments-submit 수정이 막는다.
--
-- 이 마이그레이션은 이미 쌓인 행만 정리한다. 제보 데이터는 크롤과 달리 원본을
-- 다시 긁을 수 없어 여기서 채우지 않으면 영구히 필터에서 빠진다.

-- 1) 한글 지역명 → region_code. REGION_LABELS(_shared/enums.ts)와 같은 17개.
--    라벨이 정확히 일치하는 행만 채운다. '경기·인천' 같은 복합 표기는 어느
--    한쪽으로 단정할 수 없으므로 건드리지 않는다(사람이 판단할 몫).
UPDATE public.tournaments AS t
SET region_code = m.code
FROM (VALUES
  ('서울', 'seoul'), ('경기', 'gyeonggi'), ('인천', 'incheon'),
  ('강원', 'gangwon'), ('대전', 'daejeon'), ('세종', 'sejong'),
  ('충북', 'chungbuk'), ('충남', 'chungnam'), ('광주', 'gwangju'),
  ('전북', 'jeonbuk'), ('전남', 'jeonnam'), ('부산', 'busan'),
  ('울산', 'ulsan'), ('대구', 'daegu'), ('경북', 'gyeongbuk'),
  ('경남', 'gyeongnam'), ('제주', 'jeju')
) AS m(label, code)
WHERE t.region_code IS NULL
  AND btrim(t.region) = m.label;

-- 2) region 이 문자 그대로 '전국'인 행은 지역 없음(NULL)으로 정규화한다.
--    이 시스템에서 전국대회는 region 이 비어 있는 것으로 표현한다(KATO 전국대회가
--    그렇다). '전국'이 지역명 자리에 남아 있으면 지역 목록에 "전국"이 지역처럼
--    한 번 더 생겨 "전체" 항목과 부딪힌다.
UPDATE public.tournaments
SET region = NULL
WHERE btrim(region) = '전국';
