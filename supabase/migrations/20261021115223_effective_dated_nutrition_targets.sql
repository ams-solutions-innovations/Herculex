-- Existing targets form the baseline; subsequent edits are dated versions.
ALTER TABLE public.nutrition_targets
  ADD COLUMN IF NOT EXISTS effective_from_date_iso text NOT NULL DEFAULT '0001-01-01';

ALTER TABLE public.nutrition_targets
  DROP CONSTRAINT IF EXISTS nutrition_targets_user_id_applies_to_key;

CREATE UNIQUE INDEX IF NOT EXISTS nutrition_targets_user_scope_start_key
  ON public.nutrition_targets (user_id, applies_to, effective_from_date_iso);

COMMENT ON COLUMN public.nutrition_targets.effective_from_date_iso IS
  'Inclusive local calendar date (YYYY-MM-DD); 0001-01-01 denotes the migrated baseline.';
NOTIFY pgrst, 'reload schema';
