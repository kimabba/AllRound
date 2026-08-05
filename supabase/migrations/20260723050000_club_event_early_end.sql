ALTER TABLE public.club_events
  ADD COLUMN ended_early_at timestamptz;

CREATE INDEX club_events_reminder_candidates_idx
  ON public.club_events (starts_at)
  WHERE ended_early_at IS NULL;

COMMENT ON COLUMN public.club_events.ended_early_at IS
  'Set when club operators end a scheduled event before it starts; reminder workers exclude it.';
