---
phase: 29-weekly-report-herculex-ai-narrative
plan: 19
subsystem: weekly-report
tags: [verification, traceability, gates, validation-signoff]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "Plans 29-01 to 29-18 (everything built in the phase)"
provides:
  - "Phase-level verification record: full suite, analyzer, structure check, Deno suite, source gates"
  - "RPT-01..05 and D-01..D-12 traceability table, resolution list and known limitations"
  - "29-VALIDATION.md signed off (nyquist_compliant and wave_0_complete true)"
affects: [29-20]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - .planning/phases/29-weekly-report-herculex-ai-narrative/29-VALIDATION.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "RPT-01, RPT-02 and RPT-03 are un-ticked in REQUIREMENTS.md (corrected from plan 18's blanket tick): each still has a human-gated, remote or on-device step that plan 20 owns. RPT-04 and RPT-05 stay ticked."
  - "The Validation Sign-Off 'Feedback latency < 40 s' box is left unchecked: the quick command measured 86 s on this machine."
  - "Repo-wide dart format drift (62 files) is pre-existing and was not touched; every file this phase edited is format-clean except insights_view.dart and dashboard_view.dart, which were already unformatted before the phase."

requirements-completed: [RPT-04, RPT-05]
requirements-partial: [RPT-01, RPT-02, RPT-03]

duration: 40min
completed: 2026-10-03
---

# Phase 29 Plan 19: Phase verification and traceability Summary

**Phase 29 is green and gate-clean (2706 Flutter tests, 40 Deno tests, 0 analyzer errors, structure baseline unchanged), with RPT-01..05 and D-01..D-12 traced to code and tests; the three requirements that depend on the unapplied migration, undeployed Edge Function or a real device are un-ticked pending plan 20.**

## Verification results

| Check | Result |
| ----- | ------ |
| `flutter test` (full, output redirected) | 2706 passed, 9 skipped, 0 failed. Skipped count equals the baseline (9). |
| `flutter analyze` | 0 errors. 51 issues (warnings and infos), none in weekly_report, notifications or any file this phase added; all pre-existing. |
| `dart run tool/check_structure.dart` | 57 violations, identical to the pre-phase baseline; none mention weekly_report. |
| Deno `gemini-analyze` suite | 40 passed, 0 failed (10 weekly_report, plus prompts, usage and knowledge-base additions). |
| `dart format --set-exit-if-changed lib test tool` | Exit 1, 62 files changed repo-wide, all pre-existing line-ending or formatting drift (the same files fail on the pre-phase tree). Phase-touched files are clean except `insights_view.dart` and `dashboard_view.dart`, which were verified unformatted before plan 17 touched them. Nothing reformatted (out of scope). |
| `git diff --stat a5b20af^..HEAD -- pubspec.yaml pubspec.lock` | Empty. No package installs. |
| Supabase | Only change is the added `20261003000000_weekly_reports_v48.sql`; no other migration modified; nothing applied, nothing deployed. |

### Source gates

| Gate | Result |
| ---- | ------ |
| `grep -rn "DateTime.now" lib/features/weekly_report` | The literal acceptance regex reports 5 hits, all of them the unescaped `.` matching `DateTime now` in parameter declarations (the same false positive documented in plans 01, 04, 15, 16). With the dot escaped (`DateTime\.now`) there are 0 hits. No wall-clock read exists. |
| appDatabaseProvider / package:drift in presentation | 0 files |
| `AppColors.` / `Color(0x` in weekly_report | 0 |
| Relative imports in weekly_report | 0 |
| `upsertTarget` | Only `application/weekly_report_tdee_actions.dart` |
| `payloadJson: Value` | 1 match, `data/weekly_report_repository.dart` (insertSnapshot) |
| `'weekly_reports'` in sync_backfill, sync_table_specs, local_data_wipe | 1 match each; `WeeklyReports` in `database.dart` |
| `schemaVersion => 48`, v48 dump, generated helper, Supabase SQL | all present |
| `this month` in presentation | 0 |
| `generateWeeklyReportNarrative` in a class implementing `GeminiBackend` | 0 (method lives on `WeeklyReportBackend`) |
| Line counts | `gemini_backend_service.dart` 504, `notification_settings_view.dart` 596, `workout_notification_service.dart` 518, all under 600 |

No failure was caused by this phase, so no product code was changed.

## Requirement traceability

Test paths are under `test/` unless noted. Deno files are in `supabase/functions/gemini-analyze/`.

| Req | Delivered by (code) | Automated tests | Status |
| --- | ------------------- | --------------- | ------ |
| RPT-01 one persisted row per ISO week, opt-in, six sections | `IsoWeek`, `WeeklyReports` table (v48), `WeeklyReportRepository.insertSnapshot`, payload and five section calculators, notification opt-in, sync registration, `20261003000000_weekly_reports_v48.sql` | `features/weekly_report/iso_week_test`, `weekly_report_repository_test`, `section_calculators_test`, `section_calculators_recovery_test`, `weekly_report_payload_test`, `weekly_report_sync_registration_test`, `weekly_report_wipe_test`, `sync/weekly_reports_duplicate_pull_test`, `weekly_reports_supabase_migration_test`, `migration_test`, `schema_v25/27/28/29_test`, `features/notifications/notification_settings_weekly_test` | Partial: remote table not applied (plan 20) |
| RPT-02 measured numbers local, AI narrative on top, visually separate | Calculators with explicit inputs, `WeeklyReportFacts`, `WeeklyReportNarrativeService`, `generateWeeklyReportNarrative`, Edge kind `weekly_report`, `AiNarrativeCard` | `section_calculators_test`, `weekly_report_facts_test`, `narrative_service_test`, `gemini_backend_service_test`, `weekly_report_cards_test`, `weekly_report_view_test`, Deno `weekly_report_test.ts`, `prompts_test.ts`, `usage_test.ts`, `knowledge_base_test.ts` | Partial: function not deployed, no real round-trip (plan 20) |
| RPT-03 Sunday notification, `dayOfWeekAndTime`, deep link, generate on open | `WeeklyReportNotificationScheduler` (id 5001), tap dispatch plus background queue, `WeeklyReportDeepLink`, `WeeklyReportController.open`, `weeklyReportResumeProvider`, routes | `features/notifications/weekly_report_scheduler_test`, `weekly_report_sync_test`, `weekly_report_notification_payload_test`, `features/weekly_report/weekly_report_deep_link_test`, `weekly_report_controller_test`, `weekly_report_routes_test`, `weekly_report_resume_test`, `iso_week_test` (forNotificationTap) | Partial: Sunday fire and cold-start tap are manual-only device checks (plan 20) |
| RPT-04 history, past weeks never regenerate differently | Frozen payload, write-once `saveNarrative` and `recordTdeeDecision`, `WeeklyReportsHistoryView`, read-only past weeks | `weekly_report_repository_test`, `weekly_report_service_test` (back-edit and delete), `weekly_report_controller_test`, `weekly_reports_history_view_test`, `weekly_report_view_test` | Complete |
| RPT-05 correlation not causation using existing correlation providers | `CorrelationStatement` (n >= 8, r2 >= 0.3, sign from points), `CausalLanguageGuard`, `WeeklyNarrative`, Edge prompt wording | `causal_language_guard_test`, `correlation_statement_test`, `narrative_service_test`, Deno `weekly_report_test.ts`, `prompts_test.ts` | Complete (deterministic path and guard fully local) |

### Requirements correction

Plan 18's executor ticked RPT-01..05. Checked against the evidence, `REQUIREMENTS.md` now has RPT-04 and RPT-05 ticked and RPT-01, RPT-02, RPT-03 unticked. Reasons: RPT-01 needs the remote `weekly_reports` table (validation map lists the migration as a manual RPT-01 item, and a v48 build syncing before it is applied quarantines rows with PGRST204); RPT-02's narrative needs the deployed `weekly_report` Edge kind and a real round-trip; RPT-03's Sunday firing and cold-start tap need a device. Plan 20's frontmatter lists exactly `[RPT-01, RPT-02, RPT-03]`, consistent with this. The traceability row in `REQUIREMENTS.md` stays `Pending` until plan 20.

## Decision traceability (D-01..D-12)

| Decision | Code location | Test evidence |
| -------- | ------------- | ------------- |
| D-01 frozen JSON snapshot | `weekly_report_payload.dart`, `WeeklyReportRepository.insertSnapshot` (only payload writer) | `weekly_report_payload_test`, `weekly_report_repository_test`, `weekly_report_service_test` back-edit case |
| D-02 persist first, narrative failure keeps row, manual retry | `WeeklyReportService.generate` / `generateNarrative`, controller `retryNarrative` | `weekly_report_service_test` (all five failure kinds), `weekly_report_controller_test`, `weekly_report_view_test` |
| D-03 auto-fire once on first open, quota fail-closed | `WeeklyReportController._narrate` (attempts 0 only), Edge `kindLimits` | `weekly_report_controller_test` call counts, Deno `usage_test.ts` |
| D-04 current ISO week to date | `IsoWeek.windowEnd`, `WeeklyReportInputsRepository.load` window cut | `iso_week_test`, `weekly_report_inputs_repository_test` |
| D-05 missed week generated on open | `WeeklyReportService.generate` (window from `week.windowEnd(now)`) | `weekly_report_service_test` |
| D-06 at least one signal, AI skipped otherwise | `WeeklyReportPayload.hasSignal` / `hasNarrativeSignal` | `weekly_report_service_test` (empty and weight-only weeks) |
| D-07 single toggle, off keeps history | `notification_settings_view.dart`, `NotificationSettingsNotifier`, `_syncWeeklyReport` | `notification_settings_view_test`, `weekly_report_sync_test`, `weekly_reports_history_view_test` |
| D-08 Sunday 18:00 default, editable, own scheduler | `weekly_report_notification_scheduler.dart` | `weekly_report_scheduler_test`, `notification_settings_weekly_test` |
| D-09 Analytics history plus dashboard card, deep link | `WeeklyReportsHistoryView`, `WeeklyReportsEntryCard`, `WeeklyReportReadyCard`, `AppRoutes` / `AppPaths`, `router.dart` | `weekly_reports_history_view_test`, `weekly_report_routes_test`, `weekly_report_deep_link_test` |
| D-10 measured cards first, distinct Herculex AI card | `weekly_report_view.dart`, `AiNarrativeCard` | `weekly_report_cards_test`, `weekly_report_view_test` |
| D-11 material TDEE shift, user-confirmed, write-once | `TdeeShiftCalculator`, `TdeeTargetProposalCalculator`, `weekly_report_tdee_actions.dart` (sole `upsertTarget`), `TdeeShiftCard` | `tdee_shift_test`, `tdee_shift_card_test` |
| D-12 summary plus 2-3 suggestions, advisory, causal wording rejected | `WeeklyNarrative`, `CausalLanguageGuard`, Edge `weeklyReportPrompt` / `normalizeWeeklyReportResult` | `causal_language_guard_test`, `narrative_service_test`, Deno `weekly_report_test.ts` |

## Resolutions

User-confirmed 2026-10-03:

- **OQ1** late-tap week resolution: `IsoWeek.forNotificationTap` opens the week of the most recent Sunday-at-HH:MM instant at or before now (plan 01, 10).
- **OQ2** target semantics: delta-preserving "Update my target" (saved rule kcal plus new minus old estimate, nearest 10, protein and fat kept, carbs absorb the rest, PHYS-04 clamped) (plan 16).
- **A2 reading of D-06**: TDEE drift alone is not a signal (`hasSignal` excludes `tdee`).

Orchestrator defaults, for review:

- **OQ3** duplicate pull: the test proved a local unique key on (iso_year, iso_week) aborts the whole sync cycle (SQLite 2067 escaping `pullAll`); the fallback branch was taken: no unique key local or remote, uniqueness enforced inside `insertSnapshot`, reads pick the earliest row by (generated_at, id) (plan 05, 06).
- **OQ4** TDEE rows: new = newest estimate at or before window end, old = newest before week start, no card on a missing baseline or cold start (plan 12).
- **OQ5** consent: disclosure only, no consent gate; the toggle sub-label always shows the disclosure and three privacy docs were updated (plan 08).
- **Processor naming**: the toggle subtitle names "Herculex AI (powered by Google Gemini)", deliberately breaking the KB-03 brand-only copy rule so consent is informed; owner to confirm or reword.
- **Correlation gates**: n >= 8 and r2 >= 0.3 (assumption A3, named constants).
- **Quota**: default 5 per day (`GEMINI_LIMIT_WEEKLY_REPORT` overrides).
- **UI-SPEC quota-copy correction**: quota copy is per day ("today's ... Try again tomorrow"), not "this month"; `this month` has 0 hits in presentation.

## Known limitations

- No explicit AI-consent gate (disclosure only); adding one is a one-field `privacyConsent` check on the kind plus a UI step.
- The fasting-schedule notification tap has the same latent cold-start gap (no `getNotificationAppLaunchDetails` check); not changed here.
- The knowledge corpus is still a short placeholder, so narratives are only as grounded as that text.
- Physique and health samples are not versioned: a reinstall cannot recompute a past week, so the stored row is the only source of truth.
- `notification_settings_view.dart` is at 596 of 600 lines; its next edit must split a `part` file.
- `NutritionRepository.watchDailyTotalsForRange` does not filter tombstoned `food_entries` (plan 14 deferred item; shared code).
- `HxStatTile` renders 22/12 rather than the UI-SPEC 28/14 (plan 13); `insights_view.dart` (821) and `dashboard_view.dart` (1315) were already over the 600 cap.
- Quick-run latency (86 s) exceeds the 40 s validation target on this machine.

## Open for plan 20 (human-gated)

Apply `20261003000000_weekly_reports_v48.sql` (after 0015/0016 and the v45-v47 files), deploy `gemini-analyze`, then run the four Manual-Only checks in `29-VALIDATION.md`. Do not ship a build carrying local v48 before the migration is applied.

## Task Commits

1. **Task 1: verification and validation sign-off** - `c4da672` (docs)

## Deviations from Plan

None to scope. Two notes: (1) the literal `DateTime.now` acceptance grep false-positives on `DateTime now` parameters (verified clean with the dot escaped); (2) the instruction to correct plan 18's requirement ticks was applied to `REQUIREMENTS.md` as described above.

## Known Stubs

None.

## Threat Flags

None. T-29-77 held: single `upsertTarget` call site and single `payloadJson` writer verified by grep and their tests re-run in the full suite; T-29-SC held: `pubspec.yaml` and `pubspec.lock` unchanged.

## Self-Check: PASSED

`29-VALIDATION.md` flags verified by grep; commit `c4da672` present; all gate outputs above were produced in this session.
