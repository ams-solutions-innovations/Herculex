---
phase: 29-weekly-report-herculex-ai-narrative
plan: 20
status: partial
completed: 2026-10-04
requirements: [RPT-01, RPT-02, RPT-03]
---

# Plan 29-20 Summary: production gate

**Task 1 (migration + function deploy): done. Task 2 (on-device UAT): deferred.**

## Task 1: applied on the user's instruction (2026-10-04)

The user confirmed the project URL `https://ldzgyzigvbwofbswitrv.supabase.co` and authorised the migrations and function deploys.

- **Project:** `supabase/.temp/project-ref` = `ldzgyzigvbwofbswitrv`.
- **Remote state before:** `0001`..`0021` and everything through `20260929000000` applied. `0015` and `0016` were already applied (CLAUDE.md was stale). `20261002000000_physique_v47` was **not** applied, although `docs/supabase-migrations.md` said it was.
- **Dry-run:** listed `20261002000000_physique_v47.sql`, then `20261003000000_weekly_reports_v48.sql` last.
- **Push:** `supabase db push` applied both, in that order.
- **Post-push verification (read-only):**
  - 17 columns, exactly the expected set.
  - 4 policies: `weekly_reports_{select,insert,update,delete}_own`.
  - Triggers `t_set_updated_at_weekly_reports`, `t_record_tombstone_weekly_reports`.
  - Indexes: `weekly_reports_pkey` and `weekly_reports_user_updated_idx (user_id, updated_at, id)`. No unique index on `(user_id, iso_year, iso_week)`.
  - RLS enabled.
- **Function:** `gemini-analyze` redeployed (was v24, no `weekly_report` kind). `GEMINI_API_KEY` secret already present. `GEMINI_LIMIT_WEEKLY_REPORT` left unset, so the per-day default of 5 applies.
- **Smoke check:** unauthenticated POST returns HTTP 401 (function live, JWT enforced).
- **Account deletion:** `weekly_reports.user_id` is `on delete cascade` to `auth.users`; `delete-account` needs no change.

## Task 2: on-device UAT, deferred

Not run: an executor cannot exercise OS alarms, process restarts or a signed-in session. All six checks in `29-VALIDATION.md` remain for the user:

1. Sunday notification posts, with no numbers in the text.
2. Tap from foreground and background opens the right week; narrative generates; wording is "tended to go with".
3. Cold-start tap from a killed app (assumption A10, never device-tested).
4. Re-open and food edit leave the report unchanged; offline gives "Narrative pending", Retry works.
5. TDEE shift card writes only the saved target, then goes read-only.
6. Sync round trip of a `weekly_reports` row without PGRST204; quota counter moves for `weekly_report`.

Consequence: RPT-02 (real narrative round-trip) and RPT-03 (notification, cold start) stay unconfirmed until these pass. The sync half of RPT-01 is now unblocked server-side but not device-verified.

## Doc corrections made

- `docs/supabase-migrations.md`: v47 row corrected (it was applied today, not earlier); v48 row marked applied with the verification results.
- `CLAUDE.md`: removed the stale "0015 and 0016 outstanding" note.
