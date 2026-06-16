-- 058: club_posts + comments + mentions + Storage
CREATE TABLE public.club_posts (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE, author_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, tag text NOT NULL CHECK (tag IN ('notice','free','recruit','photo')), title text NOT NULL CHECK (length(title) >= 1 AND length(title) <= 200), body text NOT NULL, image_urls text[] NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT club_posts_max_images CHECK (array_length(image_urls, 1) IS NULL OR array_length(image_urls, 1) <= 5));
CREATE INDEX club_posts_club_created_idx ON public.club_posts (club_id, created_at DESC);
CREATE INDEX club_posts_tag_idx ON public.club_posts (club_id, tag);
CREATE TRIGGER club_posts_touch_updated_at BEFORE UPDATE ON public.club_posts FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
ALTER TABLE public.club_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY club_posts_select ON public.club_posts FOR SELECT USING (is_active_club_member(club_id) OR is_admin());
CREATE POLICY club_posts_insert ON public.club_posts FOR INSERT WITH CHECK (author_id = auth.uid() AND is_active_club_member(club_id) AND (tag != 'notice' OR is_club_manager(club_id) OR EXISTS (SELECT 1 FROM public.club_members WHERE club_id = club_posts.club_id AND user_id = auth.uid() AND status = 'active' AND can_post_notice = true)));
CREATE POLICY club_posts_update ON public.club_posts FOR UPDATE USING (author_id = auth.uid() OR is_club_manager(club_id) OR is_admin());
CREATE POLICY club_posts_delete ON public.club_posts FOR DELETE USING (author_id = auth.uid() OR is_club_manager(club_id) OR is_admin());

CREATE TABLE public.club_post_comments (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), post_id uuid NOT NULL REFERENCES public.club_posts(id) ON DELETE CASCADE, author_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, body text NOT NULL CHECK (length(body) >= 1), created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX club_post_comments_post_idx ON public.club_post_comments (post_id, created_at);
ALTER TABLE public.club_post_comments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_post_club_member(p_post_id uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$ SELECT EXISTS (SELECT 1 FROM public.club_posts p JOIN public.club_members m ON m.club_id = p.club_id WHERE p.id = p_post_id AND m.user_id = auth.uid() AND m.status = 'active'); $$;

CREATE POLICY club_post_comments_select ON public.club_post_comments FOR SELECT USING (is_post_club_member(post_id) OR is_admin());
CREATE POLICY club_post_comments_insert ON public.club_post_comments FOR INSERT WITH CHECK (author_id = auth.uid() AND is_post_club_member(post_id));
CREATE POLICY club_post_comments_delete ON public.club_post_comments FOR DELETE USING (author_id = auth.uid() OR is_admin());

CREATE TABLE public.club_post_mentions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), post_id uuid NOT NULL REFERENCES public.club_posts(id) ON DELETE CASCADE, comment_id uuid REFERENCES public.club_post_comments(id) ON DELETE CASCADE, mentioned_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX club_post_mentions_user_idx ON public.club_post_mentions (mentioned_user_id);
ALTER TABLE public.club_post_mentions ENABLE ROW LEVEL SECURITY;
CREATE POLICY club_post_mentions_select ON public.club_post_mentions FOR SELECT USING (is_post_club_member(post_id) OR mentioned_user_id = auth.uid() OR is_admin());
CREATE POLICY club_post_mentions_insert ON public.club_post_mentions FOR INSERT WITH CHECK (is_post_club_member(post_id));

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('club-posts','club-posts',true,10485760,ARRAY['image/jpeg','image/png','image/webp']) ON CONFLICT (id) DO NOTHING;
