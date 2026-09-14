-- Fix a naming mismatch between local (drift) and remote (Postgres) columns
-- on `foods` that has been broken since 0001.
--
-- drift's default naming strategy turns `kcalPer100g` into `kcal_per100g`
-- (no underscore before `100g` — the case boundary is `s`→`P`, not inside
-- `Per100g`). 0001 hand-wrote the Postgres side as `kcal_per_100g` (with the
-- extra underscore) instead. `SyncService` forwards drift's column names
-- verbatim, so every push of a `foods` row has always failed with PGRST204
-- ("Could not find the 'carbs_per100g' column of 'foods' in the schema
-- cache"), quarantining the row after 8 attempts.
--
-- `product_catalogue` (0012) has the same `_per_100g` spelling but is NOT
-- touched here: it's written only through `product_catalogue_submit`
-- (0018), which builds its payload by hand with the underscore already
-- correct — renaming those columns would break that function instead of
-- fixing anything.
alter table public.foods
  rename column kcal_per_100g to kcal_per100g;
alter table public.foods
  rename column protein_per_100g to protein_per100g;
alter table public.foods
  rename column carbs_per_100g to carbs_per100g;
alter table public.foods
  rename column fat_per_100g to fat_per100g;
alter table public.foods
  rename column fiber_per_100g to fiber_per100g;
alter table public.foods
  rename column sodium_mg_per_100g to sodium_mg_per100g;
alter table public.foods
  rename column potassium_mg_per_100g to potassium_mg_per100g;
alter table public.foods
  rename column cholesterol_mg_per_100g to cholesterol_mg_per100g;
