-- JY-112: 회원 탈퇴(계정 삭제) — 익명화 정책
--
-- 정책(kimabba 결정): 개인정보/개인 데이터는 삭제, 타인이 참조하는 작성 콘텐츠
-- (클럽 게시글·댓글)는 작성자만 익명화("탈퇴한 사용자")하고 내용은 보존.
--
-- 현재 FK 실측:
--  - 대부분의 개인 데이터(user_sports, user_tennis_orgs, chat_messages, notifications,
--    device_tokens, tournament_favorites, club_favorites, match_entries, chat_rate_limit)는
--    public.users FK가 ON DELETE CASCADE → users 삭제 시 자동 삭제.
--  - clubs.created_by / tournaments.submitted_by 는 SET NULL(이미 익명화).
--  - club_posts.author_id / club_post_comments.author_id 는 CASCADE + NOT NULL →
--    그대로면 탈퇴 시 게시글·댓글이 삭제됨. 정책(보존)에 맞게 nullable + SET NULL 로 변경.
--  - club_members / club_join_requests / club_event_attendees / gemini_usage / rate_limits 는
--    public.users FK가 없어 자동 삭제 안 됨 → 삭제 함수에서 명시 삭제(고아 방지).
--  - public.users 는 auth.users 로의 삭제 연쇄가 없음 → 앱 데이터는 반드시 public.users 를
--    직접 삭제해야 CASCADE 가 작동. auth 계정 삭제는 Edge Function 이 admin API 로 별도 수행.

-- 1) 작성 콘텐츠 익명화: author_id nullable + ON DELETE SET NULL
ALTER TABLE public.club_posts ALTER COLUMN author_id DROP NOT NULL;
ALTER TABLE public.club_posts DROP CONSTRAINT club_posts_author_id_fkey;
ALTER TABLE public.club_posts
  ADD CONSTRAINT club_posts_author_id_fkey
  FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.club_post_comments ALTER COLUMN author_id DROP NOT NULL;
ALTER TABLE public.club_post_comments DROP CONSTRAINT club_post_comments_author_id_fkey;
ALTER TABLE public.club_post_comments
  ADD CONSTRAINT club_post_comments_author_id_fkey
  FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- 2) 계정 데이터 삭제/익명화 함수 (service_role 전용).
--    한 트랜잭션에서 원자적으로 처리. auth.users 삭제는 호출측(Edge Function)이 담당.
CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- FK 미연결 개인 데이터 명시 삭제(고아 방지)
  DELETE FROM public.club_members WHERE user_id = p_user_id;
  DELETE FROM public.club_join_requests WHERE user_id = p_user_id;
  DELETE FROM public.club_event_attendees WHERE user_id = p_user_id;
  DELETE FROM public.gemini_usage WHERE user_id = p_user_id;
  DELETE FROM public.rate_limits WHERE user_id = p_user_id;

  -- 클럽 일정(공유 데이터) 작성자 익명화
  UPDATE public.club_events SET created_by = NULL WHERE created_by = p_user_id;

  -- public.users 삭제 → CASCADE(개인 데이터) + SET NULL(clubs/tournaments/club_posts/comments)
  DELETE FROM public.users WHERE id = p_user_id;
END;
$function$;

-- 아무 사용자나 임의 uid 로 호출하지 못하게 service_role 전용으로 제한.
REVOKE ALL ON FUNCTION public.delete_account_data(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_account_data(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_account_data(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
