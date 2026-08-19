-- GSD 12-04 (EXR-05): a set is stored in the unit its exercise is actually
-- measured in, so a Sled Push logs weight x distance and a Plank logs a
-- duration instead of both being forced into weight x reps.
--
-- The remote half of local schema v31. Three nullable columns on an
-- already-synced table and nothing else — no RLS, trigger, tombstone or
-- publication work is needed, because `set_entries` already has all of it
-- from 0002-0005, and `SyncService` derives the push/pull payload generically
-- from whatever local columns exist beyond the registered FK/localOnly/
-- dateTime ones. Same shape and same reasoning as
-- `0010_schedule_start_time.sql`; `sync_table_specs.dart` is unchanged.
--
-- ORDERING: apply this BEFORE any build carrying local schema v31 reaches a
-- user. That same generic pass-through copies every unconsumed local column
-- including the null ones, so a v31 client puts all three of these in every
-- `set_entries` upsert whether or not the set uses them. Against a project
-- that has not run this migration, PostgREST rejects the payload (PGRST204,
-- unknown column) and *every* set push fails, not just the non-rep ones.
--
-- Nullable with no default, deliberately. Null means "this metric does not
-- apply to this movement"; 0 would mean "logged, and it was zero". Analytics
-- has to tell those apart, or a duration-only set starts contributing
-- zero-weight tonnage and a sled push starts counting as rep work it never
-- had. Every row that predates this migration is correctly null: all of them
-- were logged as weight x reps.
--
-- `reps` and `weight_kg` stay NOT NULL. A non-rep set writes 0 into them and
-- is excluded from rep/tonnage aggregation by its exercise's logging metric,
-- not by its stored numbers — widening those two columns would silently break
-- every existing query that assumes they are present.

alter table set_entries add column duration_seconds integer;
alter table set_entries add column distance_m double precision;
alter table set_entries add column calories integer;
