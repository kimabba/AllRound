-- 056: user_tennis_orgs PK 변경
ALTER TABLE public.user_tennis_orgs ADD COLUMN IF NOT EXISTS division text NOT NULL DEFAULT 'default';
UPDATE public.user_tennis_orgs SET division = COALESCE(NULLIF(TRIM(division_local), ''), 'default');
ALTER TABLE public.user_tennis_orgs ALTER COLUMN division DROP DEFAULT;
ALTER TABLE public.user_tennis_orgs DROP CONSTRAINT user_tennis_orgs_pkey;
ALTER TABLE public.user_tennis_orgs ADD PRIMARY KEY (user_id, org, division);
ALTER TABLE public.user_tennis_orgs DROP COLUMN IF EXISTS division_local;
ALTER TABLE public.user_tennis_orgs DROP COLUMN IF EXISTS expires_at;
ALTER TABLE public.user_tennis_orgs DROP CONSTRAINT IF EXISTS user_tennis_orgs_score_check;
ALTER TABLE public.user_tennis_orgs ALTER COLUMN score TYPE numeric(5,1);
ALTER TABLE public.user_tennis_orgs ADD COLUMN IF NOT EXISTS ranking_points int;
ALTER TABLE public.user_tennis_orgs ADD COLUMN IF NOT EXISTS player_origin text;
ALTER TABLE public.user_tennis_orgs ADD CONSTRAINT user_tennis_orgs_player_origin_check CHECK (player_origin IS NULL OR player_origin IN ('elementary', 'middle', 'high', 'university', 'professional', 'instructor'));
