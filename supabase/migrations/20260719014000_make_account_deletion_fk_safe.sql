BEGIN;

-- A user can be referenced as another player's partner/opponent. Those shared
-- match records must survive account deletion without retaining the account ID.
ALTER TABLE public.match_entries
  DROP CONSTRAINT IF EXISTS match_entries_partner_id_fkey;
ALTER TABLE public.match_entries
  ADD CONSTRAINT match_entries_partner_id_fkey
  FOREIGN KEY (partner_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.match_rounds
  DROP CONSTRAINT IF EXISTS match_rounds_opponent_1_id_fkey;
ALTER TABLE public.match_rounds
  ADD CONSTRAINT match_rounds_opponent_1_id_fkey
  FOREIGN KEY (opponent_1_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.match_rounds
  DROP CONSTRAINT IF EXISTS match_rounds_opponent_2_id_fkey;
ALTER TABLE public.match_rounds
  ADD CONSTRAINT match_rounds_opponent_2_id_fkey
  FOREIGN KEY (opponent_2_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- Moderation audit rows remain, but staff account IDs are anonymized when that
-- staff member deletes their account.
ALTER TABLE public.user_penalties
  ALTER COLUMN created_by DROP NOT NULL;

ALTER TABLE public.user_penalties
  DROP CONSTRAINT IF EXISTS user_penalties_created_by_fkey;
ALTER TABLE public.user_penalties
  ADD CONSTRAINT user_penalties_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.user_penalties
  DROP CONSTRAINT IF EXISTS user_penalties_revoked_by_fkey;
ALTER TABLE public.user_penalties
  ADD CONSTRAINT user_penalties_revoked_by_fkey
  FOREIGN KEY (revoked_by) REFERENCES public.users(id) ON DELETE SET NULL;

COMMIT;
