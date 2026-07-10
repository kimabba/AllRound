-- 생년월일 수집 (연령·합산나이 대회 자격 매칭용). 주민번호는 수집하지 않음.
-- 기존 birth_year(int, 미사용)와 별개로 전체 날짜를 저장한다.
alter table public.users
  add column if not exists birth_date date;

comment on column public.users.birth_date is
  '생년월일. 대회 연령/합산나이 자격 매칭 내부용(공개 안 함).';
