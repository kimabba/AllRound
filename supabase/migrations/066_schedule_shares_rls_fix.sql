-- 066: schedule_shares RLS 수정 (P1, 코덱스 반복 지적)
--
-- 문제: 062 의 단일 FOR ALL 정책이 WITH CHECK (shared_by = auth.uid()) 라
--   공유받은 사람(shared_with)이 status 를 accepted/declined 로 UPDATE 할 때
--   WITH CHECK 를 통과하지 못해 수락/거절이 불가능했음 (기능 자체가 동작 안 함).
--
-- 수정:
--   - SELECT: 보낸 사람 + 받은 사람 둘 다
--   - INSERT: 보낸 사람만
--   - UPDATE: 양쪽 허용하되, 받은 사람은 status 만 변경 가능(트리거로 강제)
--   - DELETE: 보낸 사람만

begin;

drop policy if exists schedule_shares_self on public.schedule_shares;

create policy schedule_shares_select on public.schedule_shares
  for select
  using (shared_by = auth.uid() or shared_with = auth.uid());

create policy schedule_shares_insert on public.schedule_shares
  for insert
  with check (shared_by = auth.uid());

create policy schedule_shares_update on public.schedule_shares
  for update
  using (shared_by = auth.uid() or shared_with = auth.uid())
  with check (shared_by = auth.uid() or shared_with = auth.uid());

create policy schedule_shares_delete on public.schedule_shares
  for delete
  using (shared_by = auth.uid());

-- 받은 사람은 status 만 변경 가능하도록 강제 (보낸 사람/이벤트 식별자 변조 차단).
create or replace function public.schedule_shares_guard_recipient_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() = new.shared_with and auth.uid() is distinct from new.shared_by then
    if new.shared_by   is distinct from old.shared_by
    or new.shared_with is distinct from old.shared_with
    or new.event_type  is distinct from old.event_type
    or new.event_id    is distinct from old.event_id then
      raise exception 'schedule_shares: recipient can only update status';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists schedule_shares_recipient_guard on public.schedule_shares;
create trigger schedule_shares_recipient_guard
  before update on public.schedule_shares
  for each row execute function public.schedule_shares_guard_recipient_update();

commit;
