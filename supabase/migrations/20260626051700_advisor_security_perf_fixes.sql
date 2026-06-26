-- JY-79: Supabase Advisor 보안/성능 점검 수정
--
-- 1) invalidate_tournament_embedding search_path 재설정 (077에서 재생성 후 누락)
-- 2) RLS 헬퍼 함수 anon EXECUTE REVOKE (is_admin, is_club_manager 등)
-- 3) auth_rls_initplan: auth.uid() → (SELECT auth.uid()) 변환 (44건)
--    Postgres는 initplan 으로 한 번만 평가하여 성능 향상.

BEGIN;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 1) search_path 재설정
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ALTER FUNCTION public.invalidate_tournament_embedding() SET search_path = public;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 2) RLS 헬퍼 함수 — anon 직접 호출 차단
--    이 함수들은 RLS USING 절에서만 사용됨. REST /rpc/ 노출 불필요.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REVOKE EXECUTE ON FUNCTION public.is_admin()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin()
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_active_club_member(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_active_club_member(uuid)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_club_manager(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_club_manager(uuid)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_event_club_manager(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_event_club_manager(uuid)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_event_club_member(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_event_club_member(uuid)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_post_club_member(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_post_club_member(uuid)
  TO authenticated, service_role;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 3) auth_rls_initplan: auth.uid() → (SELECT auth.uid())
--    ALTER POLICY 로 USING/WITH CHECK 표현식만 교체. 정책 삭제 없음.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- users
ALTER POLICY users_self_read ON users
  USING ((SELECT auth.uid()) = id);

ALTER POLICY users_self_update ON users
  USING ((SELECT auth.uid()) = id)
  WITH CHECK (
    ((SELECT auth.uid()) = id)
    AND (role = (SELECT u.role FROM users u WHERE u.id = (SELECT auth.uid())))
  );

-- user_sports
ALTER POLICY user_sports_self_read ON user_sports
  USING ((SELECT auth.uid()) = user_id);

ALTER POLICY user_sports_self_write ON user_sports
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- user_tennis_orgs
ALTER POLICY user_tennis_orgs_self ON user_tennis_orgs
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- tournaments
ALTER POLICY tournaments_published_read ON tournaments
  USING (
    status IN ('published', 'closed')
    OR (SELECT auth.uid()) = submitted_by
    OR is_admin()
  );

ALTER POLICY tournaments_user_submit ON tournaments
  WITH CHECK (
    (SELECT auth.uid()) = submitted_by
    AND status = 'draft'
    AND approved_by IS NULL
  );

ALTER POLICY tournaments_self_draft_update ON tournaments
  USING ((SELECT auth.uid()) = submitted_by AND status = 'draft')
  WITH CHECK ((SELECT auth.uid()) = submitted_by AND status = 'draft');

ALTER POLICY tournaments_self_draft_delete ON tournaments
  USING ((SELECT auth.uid()) = submitted_by AND status = 'draft');

-- tournament_favorites
ALTER POLICY tournament_favorites_self ON tournament_favorites
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- chat_messages
ALTER POLICY chat_messages_self ON chat_messages
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- device_tokens
ALTER POLICY device_tokens_self ON device_tokens
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- notifications
ALTER POLICY notifications_self_read ON notifications
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY notifications_self_update ON notifications
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- clubs
ALTER POLICY clubs_select ON clubs
  USING (status = 'approved' OR created_by = (SELECT auth.uid()) OR is_admin());

ALTER POLICY clubs_insert ON clubs
  WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND created_by = (SELECT auth.uid()));

ALTER POLICY clubs_update ON clubs
  USING (is_admin() OR created_by = (SELECT auth.uid()));

-- club_members
ALTER POLICY club_members_select ON club_members
  USING (user_id = (SELECT auth.uid()) OR is_admin() OR is_active_club_member(club_id));

ALTER POLICY club_members_update ON club_members
  USING (is_admin() OR user_id = (SELECT auth.uid()));

-- club_join_requests
ALTER POLICY club_join_requests_insert ON club_join_requests
  WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND user_id = (SELECT auth.uid()));

ALTER POLICY club_join_requests_select ON club_join_requests
  USING (user_id = (SELECT auth.uid()) OR is_admin() OR is_club_manager(club_id));

-- club_favorites
ALTER POLICY club_favorites_self ON club_favorites
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- club_events
ALTER POLICY club_events_insert ON club_events
  WITH CHECK (
    created_by = (SELECT auth.uid())
    AND (
      is_club_manager(club_id)
      OR EXISTS (
        SELECT 1 FROM club_members
        WHERE club_members.club_id = club_events.club_id
          AND club_members.user_id = (SELECT auth.uid())
          AND club_members.status = 'active'
          AND club_members.can_create_event = true
      )
    )
  );

ALTER POLICY club_events_update ON club_events
  USING (is_admin() OR created_by = (SELECT auth.uid()) OR is_club_manager(club_id))
  WITH CHECK (is_admin() OR created_by = (SELECT auth.uid()) OR is_club_manager(club_id));

ALTER POLICY club_events_delete ON club_events
  USING (is_admin() OR created_by = (SELECT auth.uid()) OR is_club_manager(club_id));

-- club_event_attendees
ALTER POLICY club_event_attendees_insert ON club_event_attendees
  WITH CHECK (user_id = (SELECT auth.uid()) AND is_event_club_member(event_id));

ALTER POLICY club_event_attendees_update ON club_event_attendees
  USING (user_id = (SELECT auth.uid()) AND is_event_club_member(event_id));

ALTER POLICY club_event_attendees_delete ON club_event_attendees
  USING (user_id = (SELECT auth.uid()));

-- club_posts
ALTER POLICY club_posts_insert ON club_posts
  WITH CHECK (
    author_id = (SELECT auth.uid())
    AND is_active_club_member(club_id)
    AND (
      tag <> 'notice'
      OR is_club_manager(club_id)
      OR EXISTS (
        SELECT 1 FROM club_members
        WHERE club_members.club_id = club_posts.club_id
          AND club_members.user_id = (SELECT auth.uid())
          AND club_members.status = 'active'
          AND club_members.can_post_notice = true
      )
    )
  );

ALTER POLICY club_posts_update ON club_posts
  USING (author_id = (SELECT auth.uid()) OR is_club_manager(club_id) OR is_admin());

ALTER POLICY club_posts_delete ON club_posts
  USING (author_id = (SELECT auth.uid()) OR is_club_manager(club_id) OR is_admin());

-- club_post_comments
ALTER POLICY club_post_comments_insert ON club_post_comments
  WITH CHECK (author_id = (SELECT auth.uid()) AND is_post_club_member(post_id));

ALTER POLICY club_post_comments_delete ON club_post_comments
  USING (author_id = (SELECT auth.uid()) OR is_admin());

-- club_post_mentions
ALTER POLICY club_post_mentions_select ON club_post_mentions
  USING (is_post_club_member(post_id) OR mentioned_user_id = (SELECT auth.uid()) OR is_admin());

-- match_entries
ALTER POLICY match_entries_self ON match_entries
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

ALTER POLICY match_entries_partner_read ON match_entries
  USING (partner_id = (SELECT auth.uid()));

-- match_rounds
ALTER POLICY match_rounds_read ON match_rounds
  USING (
    EXISTS (SELECT 1 FROM match_entries WHERE match_entries.id = match_rounds.entry_id AND match_entries.user_id = (SELECT auth.uid()))
    OR opponent_1_id = (SELECT auth.uid())
    OR opponent_2_id = (SELECT auth.uid())
    OR is_admin()
  );

ALTER POLICY match_rounds_write ON match_rounds
  USING (
    EXISTS (SELECT 1 FROM match_entries WHERE match_entries.id = match_rounds.entry_id AND match_entries.user_id = (SELECT auth.uid()))
    OR is_admin()
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM match_entries WHERE match_entries.id = match_rounds.entry_id AND match_entries.user_id = (SELECT auth.uid()))
    OR is_admin()
  );

-- schedule_shares
ALTER POLICY schedule_shares_select ON schedule_shares
  USING (shared_by = (SELECT auth.uid()) OR shared_with = (SELECT auth.uid()));

ALTER POLICY schedule_shares_insert ON schedule_shares
  WITH CHECK (shared_by = (SELECT auth.uid()));

ALTER POLICY schedule_shares_update ON schedule_shares
  USING (shared_by = (SELECT auth.uid()) OR shared_with = (SELECT auth.uid()))
  WITH CHECK (shared_by = (SELECT auth.uid()) OR shared_with = (SELECT auth.uid()));

ALTER POLICY schedule_shares_delete ON schedule_shares
  USING (shared_by = (SELECT auth.uid()));

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 완료: NOTIFY pgrst 로 PostgREST 스키마 캐시 갱신
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTIFY pgrst, 'reload schema';

COMMIT;
