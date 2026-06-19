-- 065: rate limit 보안 강화 (P0, 코덱스 교차검증으로 발견)
--
-- 1) consume_rate_limit quota poisoning 방지:
--    SECURITY DEFINER 함수인데 anon/authenticated 에게 EXECUTE 권한이 있어
--    일반 로그인 사용자가 REST /rpc/consume_rate_limit 로 임의 p_user_id 를 넘겨
--    남의 rate quota 를 소진시킬 수 있었음.
--    Edge Function(_shared/rate_limit.ts)은 serviceClient 로만 호출하므로
--    anon/authenticated 권한을 회수해도 정상 동작에는 영향 없음.
--
-- 2) chat_rate_limit RLS no-policy advisor 해소:
--    RLS 가 켜졌으나 정책이 없어 의도가 불명확(현재는 정책 부재로 일반 유저 차단,
--    service_role 만 bypass). service_role 전용임을 정책으로 명시.
--    service_role 은 RLS 를 bypass 하므로 동작 변화는 없다.

begin;

-- 1) consume_rate_limit: service_role 전용으로 제한
--    PostgreSQL 함수는 기본적으로 PUBLIC 에 EXECUTE 권한이 있고 anon/authenticated 가
--    이를 상속하므로, PUBLIC 에서 회수한 뒤 service_role 에만 부여해야 한다.
--    (anon/authenticated 만 revoke 하면 PUBLIC 상속 권한이 남아 우회 가능)
revoke execute on function public.consume_rate_limit(uuid, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_rate_limit(uuid, text, integer, integer)
  to service_role;

-- 2) chat_rate_limit: service_role 전용 의도 명시
drop policy if exists chat_rate_limit_service_only on public.chat_rate_limit;
create policy chat_rate_limit_service_only on public.chat_rate_limit
  for all
  to service_role
  using (true)
  with check (true);

commit;
