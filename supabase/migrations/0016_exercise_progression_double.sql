-- The remote half of local schema v37: double progression and per-exercise
-- set/rep overrides on exercise_progressions.
--
-- Same failure mode 0013 and 0015 both document, so it is repeated here only
-- because it keeps happening: `SyncService._buildRemotePayload` does
-- `SELECT *` on the local row and forwards every column that is not a
-- registered FK / localOnly / dateTime column. exercise_progressions is in
-- `syncTableSpecs` (with only `exercise_id` registered as an FK), so a v37
-- client sends all six columns below in *every* exercise_progressions upsert,
-- including the null ones. Against a project without this migration PostgREST
-- answers PGRST204 (unknown column), `_pushOne` records the failure, retries
-- with backoff, and quarantines the op after `maxPushAttempts = 8` — every
-- progression edit stops reaching the cloud, silently.
--
-- ORDERING: apply this BEFORE any build carrying local schema v37 reaches a
-- user. NOTE that 0015 is, per the project notes, still unapplied — apply it
-- first, then this, then retry anything already quarantined from either.
--
-- Defaults mirror `tables.dart` exactly so a row written by a v36 client and
-- one written by a v37 client converge on the same values:
--   progression_model  'linear'   (linear | double)
--   auto_add_sets      false
--   auto_add_sets_count 3
-- The three target_* columns are nullable on both sides — null means "no
-- override, fall back to the goal-derived prescription".

alter table exercise_progressions
  add column progression_model text not null default 'linear';
alter table exercise_progressions add column target_sets integer;
alter table exercise_progressions add column target_reps_min integer;
alter table exercise_progressions add column target_reps_max integer;
alter table exercise_progressions
  add column auto_add_sets boolean not null default false;
alter table exercise_progressions
  add column auto_add_sets_count integer not null default 3;
