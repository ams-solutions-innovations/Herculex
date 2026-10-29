-- Web track W4: the EU food catalogue as a shared, read-only table.
--
-- Phones ship the 49 MB catalogue (assets/data/food_database_eu.v1.json) and
-- import it into SQLite on first run. A browser can't reasonably do that, so
-- the web searches this table and caches the rows it actually uses into its
-- local `foods` table — through the same FoodCatalogueImporter mapping as the
-- phone, which is why the raw source item is stored instead of mapped
-- columns. Food entries keep pointing at catalogue foods by the text key
-- (`food_catalogue_ref` = `catalogue_id` here), so nothing about sync changes.
--
-- Shared data, like product_catalogue (0012): no owner column, no sync
-- columns, not in the realtime publication, and excluded from the per-user
-- wipe.
-- Populated by tool/web/upload_food_catalogue.dart with the service role.

create extension if not exists pg_trgm;

create table food_catalogue (
  catalogue_id text primary key,
  name text not null,
  brand text,
  barcode text,
  item jsonb not null,
  source_version text not null,
  updated_at timestamptz not null default now()
);

alter table food_catalogue enable row level security;

-- Signed-in users read; nobody writes except the service role (which bypasses
-- RLS). There are deliberately no insert/update/delete policies.
create policy food_catalogue_select_authenticated
  on food_catalogue for select to authenticated using (true);

create index food_catalogue_name_trgm_idx
  on food_catalogue using gin (name gin_trgm_ops);
create index food_catalogue_brand_trgm_idx
  on food_catalogue using gin (brand gin_trgm_ops);
create index food_catalogue_barcode_idx
  on food_catalogue (barcode) where barcode is not null;

-- Search used by the web food picker. Prefix matches on the name rank first
-- (what someone typing "chick" expects), then trigram similarity, so a typo
-- still finds the food. LIKE wildcards in the query are escaped so "100%"
-- doesn't match everything. security invoker: the caller's RLS applies.
create or replace function search_food_catalogue(q text, max_results int default 20)
returns setof food_catalogue
language sql
stable
security invoker
set search_path = public
as $$
  with term as (
    select
      lower(trim(q)) as raw,
      replace(replace(replace(lower(trim(q)), '\', '\\'), '%', '\%'), '_', '\_') as escaped
  )
  select f.*
  from food_catalogue f, term t
  where length(t.raw) >= 2
    and (
      lower(f.name) like '%' || t.escaped || '%'
      or lower(coalesce(f.brand, '')) like '%' || t.escaped || '%'
      or f.name % t.raw
    )
  order by
    (lower(f.name) like t.escaped || '%') desc,
    similarity(f.name, t.raw) desc,
    f.name
  limit least(greatest(coalesce(max_results, 20), 1), 50);
$$;

-- Functions are executable by PUBLIC by default; narrow it to signed-in users
-- (the table's RLS would return nothing to anon anyway).
revoke execute on function search_food_catalogue(text, int) from public;
grant execute on function search_food_catalogue(text, int) to authenticated;
