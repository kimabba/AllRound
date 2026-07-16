-- 087_club_event_fee_capacity
-- JY-116 복원: 프로덕션에만 적용돼 있고 repo 파일이 없던 마이그레이션을 역복원.
-- 프로덕션 supabase_migrations 에 version='087', name='club_event_fee_capacity' 로 기록됨.
-- 번호형이라 Supabase CLI 타임스탬프 목록에서 무시된다 → db push 재적용 대상 아님(기록 보관용).
-- 정의는 프로덕션 실측(information_schema/pg_constraint)과 동일.

alter table public.club_events
  add column if not exists fee integer,
  add column if not exists capacity integer;

alter table public.club_events
  add constraint club_events_fee_check check (fee is null or fee >= 0);

alter table public.club_events
  add constraint club_events_capacity_check check (capacity is null or capacity >= 1);
