---
status: resolved
trigger: "preveri zakaj syncing ne deluje"
created: 2026-09-12
updated: 2026-09-12
---

# Symptoms

- expected: Cloud Sync should upload the user's local records to the configured Supabase backend.
- actual: The app displays a Sync error and quarantines records during sync.
- errors: PGRST204 reports missing `foods.carbs_per100g` and `program_day_exercises.percent_of1_rm` schema-cache columns.
- timeline: Unknown; the attached screen reports 366 pending outbox items and 316 quarantined items.
- reproduction: Start Cloud Sync or use “Re-upload All Local Data” while records from the affected tables are pending.

# Current Focus

- hypothesis: The linked Supabase project is missing local migrations 0019 and 0020, so the remote schema retains incompatible column names.
- test: Compare local and linked remote migration histories and inspect both migrations.
- expecting: 0019 and 0020 are present locally but absent remotely, and they contain the exact column corrections reported by PGRST204.
- next_action: On the signed-in device, choose Sync Now / Retry to release and process quarantined operations.

# Evidence

- timestamp: 2026-09-12; local migrations 0019 and 0020 rename/add the exact missing columns named by the logs.
- timestamp: 2026-09-12; `supabase migration list --linked` shows 0019 and 0020 locally with no remote counterpart.
- timestamp: 2026-09-12; `supabase db push --linked --dry-run --include-all` would apply only 0019 and 0020; no remote state was changed.
- timestamp: 2026-09-12; both migration source columns are created by remote-applied migrations 0001 and 0002, respectively.
- timestamp: 2026-09-12; migrations 0019 and 0020 were applied to the linked Supabase project successfully.
- timestamp: 2026-09-12; remote information_schema confirms `foods.carbs_per100g`, `program_day_exercises.percent_of1_rm`, and `nutrition_targets.fiber_g` exist; obsolete spellings are absent.

# Eliminated

- hypothesis: Authentication or network connectivity is the direct blocker.
  reasoning: The backend returned PGRST204 for missing schema columns, which the app classifies as a schema error.

# Resolution

- root_cause: The linked Supabase project is missing local migrations 0019 and 0020. The remote retains `foods.*_per_100g` and `program_day_exercises.percent_of_1rm`, while the Flutter/Drift sync payload sends `*_per100g` and `percent_of1_rm`.
- fix: Applied 0019 and 0020 to the linked project with `supabase db push --linked --include-all`; use Sync Now / Retry in the app to release the queued operations.
- verification: Remote migration history now includes 0019 and 0020, and a read-only information_schema query confirms all expected corrected columns exist.
- files_changed: Remote Supabase schema migrated; debug record only: .planning/debug/sync-schema-drift.md.
