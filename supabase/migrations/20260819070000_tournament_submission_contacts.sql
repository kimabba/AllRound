-- 사용자 대회 제보의 담당자 연락처는 공개 tournaments 행과 분리한다.
-- 승인된 대회가 공개되어도 담당자 개인정보는 제보자 본인과 관리자만 읽을 수 있다.

create table public.tournament_submission_contacts (
  tournament_id uuid primary key
    references public.tournaments(id) on delete cascade,
  submitted_by uuid not null
    references public.users(id) on delete cascade,
  contact_name text not null
    check (char_length(btrim(contact_name)) between 1 and 100),
  contact_value text not null
    check (char_length(btrim(contact_value)) between 1 and 200),
  created_at timestamptz not null default now()
);

create index tournament_submission_contacts_submitted_by_idx
  on public.tournament_submission_contacts (submitted_by);

alter table public.tournament_submission_contacts enable row level security;

create policy tournament_submission_contacts_read_own
  on public.tournament_submission_contacts
  for select
  using ((select auth.uid()) = submitted_by);

create policy tournament_submission_contacts_read_admin
  on public.tournament_submission_contacts
  for select
  using (public.is_admin());

revoke all on public.tournament_submission_contacts from anon, authenticated;
grant select on public.tournament_submission_contacts
  to authenticated, service_role;
grant insert, update, delete on public.tournament_submission_contacts
  to service_role;

comment on table public.tournament_submission_contacts is
  '사용자 대회 제보 담당자 정보. 공개 대회 데이터와 분리된 개인정보.';
comment on column public.tournament_submission_contacts.contact_value is
  '관리자가 제보 확인에 사용할 전화번호 또는 이메일.';
