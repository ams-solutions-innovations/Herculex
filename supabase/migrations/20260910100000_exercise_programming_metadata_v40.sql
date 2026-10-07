-- Program-generation safety metadata mirrors local Drift v40.  Existing
-- seeded rows are never pushed, but custom exercises do sync; matching local
-- defaults keeps an uncurated custom movement out of automatic programmes.
alter table public.exercise_catalog
  add column if not exists programming_difficulty text not null default 'advanced',
  add column if not exists programming_commonness text not null default 'specialty',
  add column if not exists allowed_training_styles text not null default '[]',
  add column if not exists technical_eligibility text not null default 'manual_only';

alter table public.exercise_catalog
  add constraint exercise_catalog_programming_difficulty_check
    check (programming_difficulty in ('novice', 'intermediate', 'advanced')) not valid,
  add constraint exercise_catalog_programming_commonness_check
    check (programming_commonness in ('basic', 'specialty')) not valid,
  add constraint exercise_catalog_technical_eligibility_check
    check (technical_eligibility in ('automatic', 'technical_review', 'manual_only')) not valid;

-- Validate separately so an operationally unusual historical row cannot make
-- the schema deployment fail; newly written rows are still constrained.
alter table public.exercise_catalog
  validate constraint exercise_catalog_programming_difficulty_check,
  validate constraint exercise_catalog_programming_commonness_check,
  validate constraint exercise_catalog_technical_eligibility_check;
