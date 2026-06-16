-- 055: users 프로필 컬럼 추가
UPDATE public.users SET display_name = split_part(email, '@', 1) WHERE display_name IS NULL;
ALTER TABLE public.users RENAME COLUMN display_name TO name;
ALTER TABLE public.users ALTER COLUMN name SET NOT NULL;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS nickname text,
  ADD COLUMN IF NOT EXISTS avatar_url text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS birth_year int,
  ADD COLUMN IF NOT EXISTS gender text,
  ADD COLUMN IF NOT EXISTS bio text,
  ADD COLUMN IF NOT EXISTS primary_region text REFERENCES public.regions(code),
  ADD COLUMN IF NOT EXISTS interest_regions text[] NOT NULL DEFAULT '{}';
ALTER TABLE public.users ADD CONSTRAINT users_gender_check CHECK (gender IN ('male', 'female'));
ALTER TABLE public.users ADD CONSTRAINT users_interest_regions_max3 CHECK (array_length(interest_regions, 1) IS NULL OR array_length(interest_regions, 1) <= 3);
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ BEGIN INSERT INTO public.users (id, email, name) VALUES (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))) ON CONFLICT (id) DO NOTHING; RETURN new; END; $$;
