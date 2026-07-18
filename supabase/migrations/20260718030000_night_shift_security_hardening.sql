-- Night Shift가 발견한 권한 회귀를 서버 경계에서 차단한다.
--
-- 080이 클럽/멤버 직접 UPDATE를 admin 전용으로 제한했지만, 더 늦게 실행되는
-- timestamp migration이 creator/self UPDATE를 다시 허용했다. 앱의 쓰기 흐름은
-- 제재·검수 로직이 있는 Edge Function(service_role)만 사용하므로 RLS를 원복한다.

drop policy if exists clubs_update on public.clubs;
create policy clubs_update on public.clubs
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists club_members_update on public.club_members;
create policy club_members_update on public.club_members
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 일반 사용자는 자신의 알림 행을 읽음 처리할 수 있지만 제목·본문·발송 상태 등
-- 서버가 만든 내용을 바꾸면 안 된다. service_role과 관리자는 운영 처리를 위해 제외한다.
create or replace function public.prevent_notification_content_update()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if auth.role() = 'authenticated'
     and not public.is_admin()
     and (
       new.id is distinct from old.id
       or new.user_id is distinct from old.user_id
       or new.type is distinct from old.type
       or new.title is distinct from old.title
       or new.body is distinct from old.body
       or new.reference_type is distinct from old.reference_type
       or new.reference_id is distinct from old.reference_id
       or new.club_id is distinct from old.club_id
       or new.status is distinct from old.status
       or new.error is distinct from old.error
       or new.sent_at is distinct from old.sent_at
       or new.created_at is distinct from old.created_at
     ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = '알림은 읽음 상태만 변경할 수 있습니다';
  end if;
  return new;
end;
$function$;

drop trigger if exists notifications_content_update_guard
  on public.notifications;
create trigger notifications_content_update_guard
  before update on public.notifications
  for each row
  execute function public.prevent_notification_content_update();

-- Auth 가입 직후 생성되는 빈 profile은 birth_date NULL을 허용한다. 한 번 온보딩으로
-- 생년월일을 저장한 계정은 값을 지워 연령 게이트를 무력화할 수 없게 한다.
create or replace function public.enforce_min_signup_age()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE'
     and old.birth_date is not null
     and new.birth_date is null then
    raise exception using
      errcode = 'check_violation',
      message = 'BIRTH_DATE_REQUIRED: 가입 완료 후 생년월일을 삭제할 수 없습니다.';
  end if;

  if new.birth_date is not null
     and new.birth_date > (current_date - interval '14 years') then
    raise exception using
      errcode = 'check_violation',
      message = 'MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.';
  end if;
  return new;
end;
$function$;
