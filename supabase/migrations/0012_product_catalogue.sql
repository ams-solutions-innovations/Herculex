-- Shared/public barcode product catalogue.
--
-- Unlike every other table in this schema, this one is NOT per-user synced
-- data (see 0001_sync_schema_core.sql's header comment) — it's a shared,
-- community-contributed lookup table keyed by barcode, deliberately left out
-- of the 0003_sync_rls.sql per-user policy loop and the Drift/sync layer
-- entirely. Any signed-in user can read it; only the service-role
-- `product-catalogue-publish` Edge Function can write to it, so a
-- malicious/buggy client can never corrupt shared data directly.

create table product_catalogue (
  barcode text primary key,
  name text not null,
  brand text,
  kcal_per_100g double precision not null,
  protein_per_100g double precision not null default 0,
  carbs_per_100g double precision not null default 0,
  fat_per_100g double precision not null default 0,
  fiber_per_100g double precision,
  sodium_mg_per_100g double precision,
  potassium_mg_per_100g double precision,
  cholesterol_mg_per_100g double precision,
  serving_grams double precision,
  serving_label text,
  reference_basis text not null default '100 g',
  source text not null default 'gemini',
  contributed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table product_catalogue enable row level security;

-- Any authenticated (or anon, if ever enabled) client can read.
create policy product_catalogue_select_all on product_catalogue
  for select using (true);

-- No insert/update/delete policy for anon/authenticated roles. Writes only
-- happen via the service-role key inside product-catalogue-publish, which
-- bypasses RLS entirely — that is the sole write path by design.
