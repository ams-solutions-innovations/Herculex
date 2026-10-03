---
phase: 29
slug: weekly-report-herculex-ai-narrative
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-10-03
---

# Phase 29 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source of truth for the requirement→test map is `29-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (unit / widget / drift in-memory) + Deno test runner (`jsr:@std/assert@1`) for the Edge Function |
| **Config file** | none — standard `flutter test` discovery; Deno needs no config |
| **Quick run command** | `flutter test test/features/weekly_report/ test/features/notifications/` |
| **Full suite command** | `flutter test > flutter_test.log 2>&1` (redirect, do not pipe) + `cd supabase/functions/gemini-analyze && deno test --allow-env --allow-net .` |
| **Static gates** | `flutter analyze` (0 errors), `dart run tool/check_structure.dart` (no new violations), `dart format lib test tool` |
| **Estimated runtime** | quick ~20–40 s; full ~2 min |

---

## Sampling Rate

- **After every task commit:** the targeted test file(s) for the touched area (single `flutter test <file>`; Deno file for Edge work)
- **After every plan wave:** `flutter test test/features/weekly_report/ test/features/notifications/ test/migration_test.dart` + Deno suite + `flutter analyze` error count
- **Before `/gsd:verify-work`:** full `flutter test` green (count checked), analyze 0 errors, structure check clean, Deno suite green
- **Max feedback latency:** 40 seconds

---

## Per-Task Verification Map

Requirement-level map (task IDs are assigned once plans exist; the planner must map each task to a row below).

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| RPT-01 | `IsoWeek` correct incl. 2026-W53, 2024-12-30→2025-W01, 2021-01-03→2020-W53; DST-safe window | unit | `flutter test test/features/weekly_report/iso_week_test.dart` | ❌ W0 |
| RPT-01 | one row per week; `insertSnapshot` idempotent; soft-deleted excluded | repository | `flutter test test/features/weekly_report/weekly_report_repository_test.dart` | ❌ W0 |
| RPT-01 | section calculators over fixtures; empty → "no data"; row iff ≥1 signal | unit | `flutter test test/features/weekly_report/section_calculators_test.dart` | ❌ W0 |
| RPT-01 | payload JSON round-trip, `payloadVersion`, malformed → `FormatException` | unit | `flutter test test/features/weekly_report/weekly_report_payload_test.dart` | ❌ W0 |
| RPT-01 | opt-in default off; `NotificationSettings` back-compat | unit | `flutter test test/features/notifications/notification_settings_weekly_test.dart` | ❌ W0 |
| RPT-01 (schema) | v47→v48 replay, index + outbox trigger, `migrateAndValidate(…, 48)` | migration | `flutter test test/migration_test.dart test/schema_v25_test.dart test/schema_v27_test.dart test/schema_v28_test.dart test/schema_v29_test.dart` | existing, retarget |
| RPT-01 (sync) | registered in `syncedTableNames` + `syncTableSpecs`; SQL column parity | unit/text | `flutter test test/weekly_reports_supabase_migration_test.dart test/features/weekly_report/weekly_report_sync_registration_test.dart` | ❌ W0 |
| RPT-02 | calculators use explicit inputs only; same inputs + different clock → same output | unit | `flutter test test/features/weekly_report/section_calculators_test.dart` | ❌ W0 |
| RPT-02 | Edge kind `weekly_report`: limits/names, normalizer, prompt rules | Deno | `cd supabase/functions/gemini-analyze && deno test --allow-env --allow-net weekly_report_test.ts prompts_test.ts usage_test.ts` | ❌ W0 |
| RPT-02 | `generateWeeklyReportNarrative` on all 3 backends; existing fakes still compile | unit | `flutter test test/features/weekly_report/narrative_service_test.dart` + `flutter analyze` | ❌ W0 |
| RPT-02 | AI card separate widget + pill; measured cards carry no `hx.primary`; all states | widget | `flutter test test/features/weekly_report/weekly_report_view_test.dart` | ❌ W0 |
| RPT-03 | scheduler id 5001, `dayOfWeekAndTime`, first fire is a Sunday, cancel on disable | unit | `flutter test test/features/notifications/weekly_report_scheduler_test.dart` | ❌ W0 |
| RPT-03 | `IsoWeek.forNotificationTap` table test (Sun 17:59/18:01, Mon, year rollover) | unit | `flutter test test/features/weekly_report/iso_week_test.dart` | ❌ W0 |
| RPT-03 | payload-prefix dispatch; no generation in callback | unit | `flutter test test/weekly_report_notification_payload_test.dart` | ❌ W0 |
| RPT-03 | open route generates once; concurrent opens → 1 backend call; row persisted before narrative call | controller | `flutter test test/features/weekly_report/weekly_report_controller_test.dart` | ❌ W0 |
| RPT-03 | route constants in `AppRoutes`/`AppPaths`; route builds views | widget/router | `flutter test test/features/weekly_report/weekly_report_routes_test.dart` | ❌ W0 |
| RPT-04 | edit/delete source data after generation → report identical; `saveNarrative` write-once; no `payload_json` mutator | repository | `flutter test test/features/weekly_report/weekly_report_repository_test.dart` | ❌ W0 |
| RPT-04 | failed narrative → row kept, no auto-retry; retry fires once | controller | `flutter test test/features/weekly_report/weekly_report_controller_test.dart` | ❌ W0 |
| RPT-04 | history newest first; past-week read-only; pending pill; opt-in off keeps history | widget | `flutter test test/features/weekly_report/weekly_reports_history_view_test.dart` | ❌ W0 |
| RPT-05 | `CausalLanguageGuard` rejects causal table; accepts "tended to go with"; causal narrative → pending | unit | `flutter test test/features/weekly_report/causal_language_guard_test.dart` | ❌ W0 |
| RPT-05 | `CorrelationStatement` sign from `points`, n/r² gates, never uses `.interpretation` | unit | `flutter test test/features/weekly_report/correlation_statement_test.dart` | ❌ W0 |
| D-11 / TDEE-05 | material-shift boundary, old/new selection, decision write-once, `upsertTarget` only on tap, clamps, no saved rule → read-only | unit/widget | `flutter test test/features/weekly_report/tdee_shift_test.dart` | ❌ W0 |

*Status column is maintained per task once plans exist.*

---

## Wave 0 Requirements

- [x] `test/features/weekly_report/` — entire directory and every file listed above
- [x] `test/weekly_reports_supabase_migration_test.dart` — clone of `physique_supabase_migration_test.dart`
- [x] `supabase/functions/gemini-analyze/weekly_report_test.ts` — clone of `program_brief_test.ts`
- [x] Reuse `FakeLocalNotificationsPlugin` (already supports `zonedSchedule` with payload + `matchDateTimeComponents`); do not fork
- [x] Drift artifacts after the schema change: `drift_schemas/drift_schema_v48.json`, `test/generated_migrations/schema_v48.dart` (+ `schema.dart`)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sunday notification fires on a real device | RPT-03 | OS alarm scheduling not testable in CI | Enable opt-in, set time ~2 min ahead on a Sunday (or adjust device clock), confirm notification posts |
| Cold-start tap from killed app lands on the report | RPT-03 | Needs `getNotificationAppLaunchDetails` on a real process restart | Force-stop app, tap notification, confirm report route opens and generates once |
| Supabase migration applied and verified | RPT-01 | Writes to remote project `ldzgyzigvbwofbswitrv` (human-gated; 0015/0016 also outstanding — apply in order) | Apply migrations in order; confirm `weekly_reports` columns match drift; one sync round-trip |
| Edge Function deployed + one real narrative round-trip | RPT-02 | Needs deployed function and quota env | `supabase functions deploy gemini-analyze`; open a report; confirm narrative saved and quota decremented |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [ ] Feedback latency < 40 s (not met: quick command measured 86 s on this machine, cold compile; targeted single-file runs are shorter)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-10-03 (plan 29-19; automated gates green, the four Manual-Only items above remain open for plan 29-20)
