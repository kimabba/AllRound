-- 013_rls_hardening.sql
-- SEC-M-02 / SEC-M-06 — RLS defence-in-depth.
--
-- SEC-M-02: users.role 자가 상승 차단을 트리거뿐 아니라 RLS WITH CHECK 로도 강제.
--           + users 테이블에 사용자 직접 INSERT 명시적 deny (현재는 정책 부재로 암묵 deny).
-- SEC-M-06: notifications_log 는 service_role(notify-cron)만 INSERT.
--           일반 사용자 INSERT 를 명시적 deny 정책으로 의도 고정 (회피 row 선삽입 방지).

-- ── SEC-M-02: users self-update 시 role 변경 금지 ───────────────
drop policy if exists users_self_update on public.users;

create policy users_self_update on public.users
  for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and role = (select u.role from public.users u where u.id = auth.uid())
  );

-- 사용자 직접 INSERT 명시적 deny. row 생성은 handle_new_user 트리거(SECURITY DEFINER)만.
-- (admin 은 users_admin_all 정책으로 여전히 가능)
drop policy if exists users_no_self_insert on public.users;
create policy users_no_self_insert on public.users
  for insert
  with check (false);

comment on policy users_no_self_insert on public.users is
  'user row 는 auth trigger(handle_new_user)로만 생성. 직접 INSERT 금지 (admin 예외).';

-- ── SEC-M-06: notifications_log 사용자 INSERT deny ──────────────
drop policy if exists notifications_log_no_user_insert on public.notifications_log;
create policy notifications_log_no_user_insert on public.notifications_log
  for insert
  with check (false);

comment on policy notifications_log_no_user_insert on public.notifications_log is
  'notifications_log INSERT 는 service_role(notify-cron)만. 사용자가 dedup row 를 '
  '선삽입해 알림을 회피하지 못하도록 명시적 deny (admin 은 notifications_log_admin_all).';
