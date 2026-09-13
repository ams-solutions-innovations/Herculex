-- Program-generation metadata & discipline taxonomy mirrors local Drift v41.
alter table public.exercise_catalog
  alter column programming_commonness set default 'manualOnly',
  add column if not exists disciplines text not null default '[]',
  add column if not exists prerequisite_slugs text not null default '[]',
  add column if not exists scaling_group text,
  add column if not exists scaling_order integer,
  add column if not exists competition_anchor text,
  add column if not exists specialization_tags text not null default '[]';

-- Update commonness check constraint to include all 4 explicit tiers:
-- basic, common, specialty, manualOnly
alter table public.exercise_catalog
  drop constraint if exists exercise_catalog_programming_commonness_check;

alter table public.exercise_catalog
  add constraint exercise_catalog_programming_commonness_check
    check (programming_commonness in ('basic', 'common', 'specialty', 'manualOnly')) not valid;

alter table public.exercise_catalog
  validate constraint exercise_catalog_programming_commonness_check;

-- Scaling ladder index for indexed SQL ordering and traversal
create index if not exists idx_exercise_catalog_scaling
  on public.exercise_catalog(scaling_group, scaling_order);
