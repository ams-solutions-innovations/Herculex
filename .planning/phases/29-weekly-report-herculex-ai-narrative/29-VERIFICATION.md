---
phase: 29-weekly-report-herculex-ai-narrative
verified: 2026-10-04T00:00:00Z
status: human_needed
score: 5/5 roadmap truths verified in code; RPT-02/RPT-03 and sync half of RPT-01 await on-device confirmation
human_verification:
  - test: "Sunday notification posts, text contains no numbers"
    expected: "Notification fires at the configured Sunday time with generic text"
    why_human: "OS alarms cannot be exercised by grep or unit tests"
  - test: "Tap from foreground and background opens the right week; narrative generates; wording is 'tended to go with'"
    expected: "Report for the tapped week opens, Herculex AI card fills, correlation wording only"
    why_human: "Real Gemini round trip and OS notification tap"
  - test: "Cold-start tap from a killed app (assumption A10)"
    expected: "App launches and lands on the weekly report (see review IN-02)"
    why_human: "Never device-tested; router redirect timing"
  - test: "Re-open and food edit leave the report unchanged; offline shows 'Narrative pending'; Retry works"
    expected: "Frozen snapshot, retry succeeds when online"
    why_human: "Needs signed-in session and connectivity toggling"
  - test: "TDEE shift card writes only the saved target, then goes read-only"
    expected: "One target write, card becomes read-only (see review WR-03, WR-06)"
    why_human: "Interactive UI flow"
  - test: "Sync round trip of a weekly_reports row without PGRST204; quota counter moves for weekly_report"
    expected: "Row appears remotely; ai_usage increments"
    why_human: "Needs live Supabase session"
---

# Phase 29: Weekly Report & Herculex AI Narrative Verification

**Phase Goal:** Opt-in Sunday report snapshotting the week across nutrition, training, recovery, physique and TDEE drift, with a knowledge-grounded narrative over measured numbers.
**Status:** human_needed (no code gaps blocking; device UAT deferred)
**Re-verification:** No

## Observable Truths

| # | Truth (ROADMAP Success) | Status | Evidence |
|---|---|---|---|
| 1 | One persisted row per ISO week with all sections | VERIFIED (code) | `weekly_reports` table, `WeeklyReportRepository`, section calculators for nutrition/training/recovery/physique/TDEE in `lib/features/weekly_report/domain/`; migration v48 applied remotely with 17 columns, RLS, 4 policies (29-20 summary). Caveat: no DB unique index; dedupe is app-level (review WR-01/02). |
| 2 | Measured sections local, visually separated from AI narrative | VERIFIED (code) | Calculators are pure Dart; separate Herculex AI card widget with disclaimer text; gemini-analyze `weekly_report` kind present (index.ts:569), function redeployed. Real narrative round trip not device-confirmed. |
| 3 | Sunday `dayOfWeekAndTime` notification deep-links; report generated on open, not in callback | VERIFIED (code) / device pending | `weekly_report_notification_scheduler.dart:64,78`; `AppRoutes.weeklyReport(s)` registered in router.dart:195-198; callbacks only queue/navigate. Cold-start untested (IN-02). |
| 4 | Past weeks browsable, never regenerate differently | VERIFIED | History view + route; write-once snapshot; no `DateTime.now` in feature; service tests pass. |
| 5 | Recovery/sleep/activity stated as correlation | VERIFIED | `correlation_statement.dart` fixed templates ("tended to"), `CausalLanguageGuard` rejects causal narrative. |

**Score:** 5/5 truths verified in code.

## Behavioral Spot-Checks

| Behavior | Command | Result |
|---|---|---|
| weekly_report test directory | `flutter test test/features/weekly_report` | 406 passed, 0 failed |
| Plan 19 gates (per summary, not re-run by me) | full suite 2706 pass; analyzer 0 errors; Deno 40 pass; structure baseline unchanged | claimed |

## Requirements Coverage

| ID | Status | Evidence |
|---|---|---|
| RPT-01 | SATISFIED in code; sync not device-verified | Table, repo, calculators, migration applied |
| RPT-02 | SATISFIED in code; real narrative round trip pending UAT | Narrative service, card, edge function deployed |
| RPT-03 | SATISFIED in code; notification and cold start pending UAT | Scheduler, payload, deep link |
| RPT-04 | SATISFIED | Immutable snapshot, history |
| RPT-05 | SATISFIED | Correlation templates and guard |

No orphaned IDs: REQUIREMENTS.md maps only RPT-01-05 to Phase 29. Note: REQUIREMENTS.md traceability row (line 141) still reads "Pending"; RPT-01-03 checkboxes intentionally unticked until UAT.

## Code Review Findings (29-REVIEW.md, 0 critical, 7 warnings) vs must-haves

| Finding | Affects must-have? |
|---|---|
| WR-01 hard-delete of tombstoned rows can resurrect old report | Yes, partially: RPT-01 (one row per week) and RPT-04 (never differs) under sync/regenerate edge cases |
| WR-02 cross-device duplicate swaps displayed report, orphaning narrative/TDEE decision | Yes: RPT-04 across devices (no unique DB index) |
| WR-03 TDEE write non-atomic, no stale-proposal check | TDEE card behavior (RPT-01 TDEE drift action); not a stated criterion |
| WR-04 invalid/failed requests consume quota | No (cost/UX) |
| WR-05 prompt injection / numbers-verbatim not enforced server-side | RPT-02 quality (hallucinated figure persisted write-once); not a stated criterion |
| WR-06 TDEE card stuck busy on false return | UX only |
| WR-07 mid-week open freezes partial-week snapshot | Yes: RPT-04 semantics, "Sunday report" content quality when opened early |
| IN-01..03 | IN-02 relates to RPT-03 cold start (UAT item 3) |

None are blockers for the stated roadmap criteria on a single device, but WR-01, WR-02 and WR-07 weaken RPT-01/RPT-04 in multi-device or early-open cases and are recommended follow-ups.

## Anti-Patterns

Debt-marker scan not exhaustively run on all phase files; reviewer and plan 19 report no blockers.

## Gaps Summary

No code gaps found against roadmap criteria. Status is human_needed because the six UAT checks (plan 29-20 task 2) are outstanding. Plan 29-20 is partial: migrations 20261002000000 and 20261003000000 applied and gemini-analyze redeployed on 2026-10-04 to project ldzgyzigvbwofbswitrv.

---
_Verifier: Claude (gsd-verifier)_
