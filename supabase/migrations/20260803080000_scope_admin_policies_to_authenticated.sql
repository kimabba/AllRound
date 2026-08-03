-- anon 세션에서 42501 로 죽는 RLS 정책을 로그인 롤로 좁힌다 (#365)
--
-- 증상: 비로그인(anon)으로 조회하면 빈 결과가 아니라 에러가 난다.
--   ERROR: 42501 permission denied for function is_admin
--
-- 원인: is_admin() 등 일부 SECURITY DEFINER 헬퍼는 anon 에게 EXECUTE 가 없다
--   (20260626055521 에서 의도적으로 뺐다 — 이건 옳다). 그런데 그 함수를 부르는 정책이
--   `TO` 절 없이(=PUBLIC) 걸려 있어서 anon 쿼리에서도 평가 대상이 된다. 정책 표현식은
--   호출자 권한으로 평가되므로 실행 권한이 없으면 그 자리에서 죽는다.
--   AND/OR 단락평가로는 피할 수 없다 — 플래너가 InitPlan 으로 먼저 뽑는다(#365 실측).
--
-- 범위: 이슈는 grades·tennis_divisions 를 지목했지만 같은 형태가 전면적이었다.
--   anon 으로 SELECT 했을 때 실제로 죽는 테이블이 **33개**였다(로컬 전수 실측).
--   tournaments·regions·grades·tennis_orgs·rule_articles 같은 공개 카탈로그가 전부 포함된다.
--   증상만 고치면 나머지 31개가 그대로 남으므로 원인 형태 전체를 고친다.
--
-- 해법: 대상 정책에 `TO authenticated` 를 붙인다. anon 세션에서는 그 정책이 평가 대상이
--   아니게 되어 함수가 호출되지 않는다. **anon 이 잃는 것은 없다** — 아래 정책들은
--   모든 분기가 auth.uid() 나 멤버십·관리자 확인을 요구해서 anon 에게는 어차피 0행이다.
--   에러가 0행으로 바뀔 뿐이다. 인증 사용자의 동작은 그대로다.
--
-- service_role 은 rolbypassrls=true 라 정책 범위와 무관하다(확인함). 서버 경로 영향 없음.
--
-- 공개 분기(로그인을 요구하지 않는 OR 분기)가 섞인 정책은 딱 둘이었다. 나머지 55개는
-- 전부 순수 is_admin() 이거나 모든 분기가 로그인·멤버십을 요구한다(전수 확인).
--
--   1) tournaments_published_read — 아래에서 분리한다. 비로그인 대회 조회는 살려야 한다.
--   2) clubs_select — `status='approved' or created_by=uid or is_admin()`.
--      같은 형태지만 **의도적으로 분리하지 않고 authenticated 로 좁힌다**(2026-08-03 Commander 결정).
--      clubs 에는 contact·address·latitude/longitude 가 있어 승인 클럽을 비로그인에 공개하면
--      연락처·위치가 그대로 열린다. 지금까지 anon 은 이 정책이 42501 로 죽어 어차피 못 봤으므로
--      닫아 두는 쪽이 동작 변화가 없다. 여는 것은 공개할 컬럼을 고른 뒤 별건으로 결정한다.
--      (022 가 anon 의 clubs 조회가 0행임을 고정한다 — 나중에 버그로 오인해 조용히 열지 않도록.)

begin;

alter policy chat_messages_admin_read on public.chat_messages to authenticated;
alter policy club_bans_manager_select on public.club_bans to authenticated;
alter policy club_dues_audit_manager_select on public.club_dues_audit to authenticated;
alter policy club_dues_payments_member_select on public.club_dues_payments to authenticated;
alter policy club_dues_periods_member_select on public.club_dues_periods to authenticated;
alter policy club_event_attendees_insert on public.club_event_attendees to authenticated;
alter policy club_event_attendees_select on public.club_event_attendees to authenticated;
alter policy club_event_attendees_update on public.club_event_attendees to authenticated;
alter policy club_events_delete on public.club_events to authenticated;
alter policy club_events_insert on public.club_events to authenticated;
alter policy club_events_select on public.club_events to authenticated;
alter policy club_events_update on public.club_events to authenticated;
alter policy club_favorites_admin_read on public.club_favorites to authenticated;
alter policy club_inquiry_messages_participant_select on public.club_inquiry_messages to authenticated;
alter policy club_inquiry_threads_participant_select on public.club_inquiry_threads to authenticated;
alter policy club_join_requests_select on public.club_join_requests to authenticated;
alter policy club_join_requests_update on public.club_join_requests to authenticated;
alter policy club_members_select on public.club_members to authenticated;
alter policy club_post_comments_delete on public.club_post_comments to authenticated;
alter policy club_post_comments_insert on public.club_post_comments to authenticated;
alter policy club_post_comments_select on public.club_post_comments to authenticated;
alter policy club_post_mentions_insert on public.club_post_mentions to authenticated;
alter policy club_post_mentions_select on public.club_post_mentions to authenticated;
alter policy club_posts_delete on public.club_posts to authenticated;
alter policy club_posts_insert on public.club_posts to authenticated;
alter policy club_posts_select on public.club_posts to authenticated;
alter policy club_posts_update on public.club_posts to authenticated;
alter policy club_recruiting_posts_delete on public.club_recruiting_posts to authenticated;
alter policy club_recruiting_posts_insert on public.club_recruiting_posts to authenticated;
alter policy club_recruiting_posts_select on public.club_recruiting_posts to authenticated;
alter policy club_recruiting_posts_update on public.club_recruiting_posts to authenticated;
alter policy clubs_admin_all on public.clubs to authenticated;
alter policy crawl_audit_admin_only on public.crawl_audit to authenticated;
alter policy device_tokens_admin_read on public.device_tokens to authenticated;
alter policy futsal_details_admin on public.futsal_tournament_details to authenticated;
alter policy gemini_usage_admin_all on public.gemini_usage to authenticated;
alter policy grades_admin on public.grades to authenticated;
alter policy match_entries_admin on public.match_entries to authenticated;
alter policy match_rounds_read on public.match_rounds to authenticated;
alter policy match_rounds_write on public.match_rounds to authenticated;
alter policy notifications_admin_all on public.notifications to authenticated;
alter policy regions_admin_all on public.regions to authenticated;
alter policy rule_articles_admin_all on public.rule_articles to authenticated;
alter policy tennis_divisions_admin on public.tennis_divisions to authenticated;
alter policy tennis_orgs_admin on public.tennis_orgs to authenticated;
alter policy tennis_details_admin on public.tennis_tournament_details to authenticated;
alter policy tournament_favorites_admin_read on public.tournament_favorites to authenticated;
alter policy tournaments_admin_all on public.tournaments to authenticated;
alter policy tournaments_self_draft_update on public.tournaments to authenticated;
alter policy tournaments_user_submit on public.tournaments to authenticated;
alter policy ugc_moderation_terms_admin_all on public.ugc_moderation_terms to authenticated;
alter policy ugc_reports_admin_all on public.ugc_reports to authenticated;
alter policy user_blocks_admin_all on public.user_blocks to authenticated;
alter policy user_penalties_admin_all on public.user_penalties to authenticated;
alter policy user_sports_admin_all on public.user_sports to authenticated;
alter policy user_tennis_orgs_admin_all on public.user_tennis_orgs to authenticated;
alter policy users_admin_all on public.users to authenticated;

-- ── 예외: 공개 대회 목록은 anon 도 읽어야 한다 ───────────────────────
-- 기존: (status in ('published','closed')) or auth.uid() = submitted_by or is_admin()
--   첫 분기는 공개 의도인데, 뒤의 is_admin() 때문에 anon 이 통째로 죽었다.
--   TO authenticated 로 좁히면 에러는 사라지지만 **비로그인 대회 조회가 막힌다**(의도 아님).
--   그래서 공개 분기와 로그인 분기를 두 정책으로 나눈다. 인증 사용자는 두 정책의 합집합을
--   보므로 기존과 동일하다(permissive 정책은 OR 로 합쳐진다).
drop policy tournaments_published_read on public.tournaments;

create policy tournaments_public_read on public.tournaments
  for select to anon, authenticated
  using (status = any (array['published'::tournament_status, 'closed'::tournament_status]));

create policy tournaments_owner_admin_read on public.tournaments
  for select to authenticated
  using ((select auth.uid()) = submitted_by or is_admin());

commit;
