-- JY-129: 기존 데이터의 묶음 region_code(seoul_metro/busan_ulsan_gn/daegu_gb/chungcheong)를
-- 표준 17개 광역시도로 재분류(backfill). regions 테이블은 20260710030000 에서 이미 17시도 완비.
--
-- 대상: venues(217행), tournaments(17행). user_tennis_orgs 의 seoul_metro(2건)는 실거주 시도
-- 정보가 없어 자동 분류 불가 → 그대로 두고 온보딩 재선택으로 유도(묶음 코드는 앱 선택지에 없음).
--
-- 매핑 근거(프로덕션 조회, 트랜잭션 롤백으로 검증 완료):
--   venues: region 텍스트가 전부 단일 시도명(서울시/경기도/…) → 기계적 매핑, uncovered=0
--   tournaments: region 단일 시도명은 직접, '경기·인천'(10건)만 location 으로 분기(인천 2 / 경기 8)
-- idempotent: WHERE 가 묶음 코드에만 걸리므로 재실행 시 no-op.

update public.venues set region_code = case region
  when '서울시' then 'seoul'
  when '경기도' then 'gyeonggi'
  when '인천시' then 'incheon'
  when '부산시' then 'busan'
  when '울산시' then 'ulsan'
  when '경상남도' then 'gyeongnam'
  when '대전시' then 'daejeon'
  when '충청북도' then 'chungbuk'
  when '충청남도' then 'chungnam'
  when '경상북도' then 'gyeongbuk'
  when '대구시' then 'daegu'
  else region_code
end
where region_code in ('seoul_metro', 'busan_ulsan_gn', 'daegu_gb', 'chungcheong');

update public.tournaments set region_code = case
  when region = '서울' then 'seoul'
  when region = '경남' then 'gyeongnam'
  when region = '충북' then 'chungbuk'
  when region = '경북' then 'gyeongbuk'
  when region = '경기·인천' and location like '%인천%' then 'incheon'
  when region = '경기·인천' then 'gyeonggi'
  else region_code
end
where region_code in ('seoul_metro', 'busan_ulsan_gn', 'daegu_gb', 'chungcheong');
