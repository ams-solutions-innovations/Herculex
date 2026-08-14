-- Catalogue tables must carry `is_custom` across the wire.
--
-- 0001 deliberately omitted it: only custom rows are ever pushed (the local
-- `trg_outbox_*` triggers guard on `NEW.is_custom = 1`), so the column would
-- be constantly true and looked redundant. That reasoning holds on the push
-- side and breaks on the pull side — `Foods.isCustom` and friends default to
-- **false** locally (`lib/data/local/tables.dart`), so a custom row pulled on
-- a second device lands as a *seeded* row.
--
-- That is not cosmetic. `SyncIdResolver.resolveCatalogueRefForPush` branches
-- on `is_custom` to decide whether a catalogue reference travels as a uuid
-- (custom) or a natural key (seeded). With the flag lost, device B takes the
-- seeded branch for a custom parent and:
--
--   * exercise_catalog / foods — the natural key (`slug` / `catalogue_id`) is
--     null on custom rows, so the payload carries *both* catalogue columns
--     null and Postgres rejects it on the `check` constraint in 0001/0002.
--     Eight retries, then quarantine, then a red sync badge.
--   * accessories — every custom row has `kind = 'custom'`, so the natural
--     key resolves to whichever custom accessory happens to be first. Silent
--     mis-association rather than a hard failure.
--   * bands — resolves by `(color, tension_kg)`, which can collide with a
--     seeded band of the same colour and tension. Also silent.
--
-- `default true` is the correct backfill: every row already in these tables
-- got there through the custom-only push path.

alter table public.exercise_catalog
  add column if not exists is_custom boolean not null default true;

alter table public.foods
  add column if not exists is_custom boolean not null default true;

alter table public.accessories
  add column if not exists is_custom boolean not null default true;

alter table public.bands
  add column if not exists is_custom boolean not null default true;

comment on column public.exercise_catalog.is_custom is
  'Always true in practice — only custom rows are pushed. Present so the '
  'receiving device does not fall back to its local default of false. See '
  'SyncIdResolver.resolveCatalogueRefForPush.';
comment on column public.foods.is_custom is
  'See exercise_catalog.is_custom.';
comment on column public.accessories.is_custom is
  'See exercise_catalog.is_custom.';
comment on column public.bands.is_custom is
  'See exercise_catalog.is_custom.';
