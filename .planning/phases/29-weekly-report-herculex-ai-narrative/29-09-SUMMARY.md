---
phase: 29-weekly-report-herculex-ai-narrative
plan: 09
subsystem: weekly-report
tags: [gemini-backend, narrative-service, failure-kinds, riverpod, tdd]

requires:
  - phase: 29-01
    provides: "WeeklyNarrative strict parser and CausalLanguageGuard"
  - phase: 29-03
    provides: "gemini-analyze weekly_report kind (facts in, result + provenance out)"
provides:
  - "WeeklyReportBackend interface (separate from GeminiBackend) and weeklyReportBackendProvider"
  - "generateWeeklyReportNarrative on UnconfiguredGeminiBackend and SupabaseGeminiBackend"
  - "WeeklyReportNarrativeService.generate(facts) -> (WeeklyNarrative, provenance) or WeeklyReportNarrativeException"
  - "NarrativeFailureKind { offline, unconfigured, quotaExhausted, rejected, unavailable }"
affects: [29-14, 29-15, 29-18]

tech-stack:
  added: []
  patterns:
    - "Capability interface beside GeminiBackend (PhysiqueCheckInBackend precedent) so existing fakes keep compiling"
    - "Substring failure classification with fixed user-safe messages per kind"

key-files:
  created:
    - lib/features/weekly_report/data/weekly_report_narrative_service.dart
    - test/features/weekly_report/narrative_service_test.dart
  modified:
    - lib/services/ai/gemini_backend_service.dart
    - test/gemini_backend_service_test.dart

key-decisions:
  - "weekly_report sends no privacyConsent field (facts are numeric aggregates, no photos); adding a gate later is a one-field change (open question 5 stays a human decision in plan 08 docs)"
  - "Quota is matched before offline and unconfigured so a 429 message is never misread"
  - "Both causal-wording rejection and structural parse failure map to rejected (D-12)"

patterns-established:
  - "NarrativeFailureKind selects copy only; every kind is handled the same way by the caller (D-02)"

requirements-completed: []
requirements-partial: [RPT-02, RPT-05]

duration: 15min
completed: 2026-10-03
---

# Phase 29 Plan 09: Weekly report narrative backend and service Summary

**A separate WeeklyReportBackend interface on both Gemini backends plus a database-free WeeklyReportNarrativeService that validates the model answer through WeeklyNarrative and classifies every failure into one of five typed kinds with fixed user-safe messages.**

## What was built

- `gemini_backend_service.dart` (474 -> 504 lines): `WeeklyReportBackend`, `weeklyReportBackendProvider` (falls back to `UnconfiguredGeminiBackend` when the watched backend does not implement it), and `generateWeeklyReportNarrative` on both backends. The Supabase one invokes `gemini-analyze` with `{'kind': 'weekly_report', 'facts': facts}` and returns via the existing `_resultWithProvenance`. `GeminiBackend` itself is untouched, so no existing test fake needed editing.
- `weekly_report_narrative_service.dart`: `weeklyReportNarrativeServiceProvider`, `NarrativeFailureKind`, `WeeklyReportNarrativeException` (`toString` returns the message), and `WeeklyReportNarrativeService.generate`. Classification: 'used up'/'try again tomorrow' -> quotaExhausted; 'Cannot connect'/'timed out' -> offline; 'not configured' -> unconfigured; `FormatException` from `WeeklyNarrative.fromJson` -> rejected; anything else -> unavailable. No drift/database import.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 | 1300e5d | WeeklyReportBackend interface, provider, both implementations, Unconfigured test |
| 2 RED | f9f76cf | failing narrative service test |
| 2 GREEN | bb1d7a3 | WeeklyReportNarrativeService |

## Verification

- `flutter test test/gemini_backend_service_test.dart test/herculex_ai_brief_service_test.dart`: 14 passed (Task 1).
- `flutter test test/features/weekly_report/narrative_service_test.dart test/gemini_backend_service_test.dart`: 22 passed.
- `flutter analyze lib/services/ai lib/features/weekly_report test`: 0 errors; 6 pre-existing warnings in unrelated test files.
- `dart run tool/check_structure.dart`: no violation mentions weekly_report or gemini_backend_service.
- `generateWeeklyReportNarrative` is declared only in `WeeklyReportBackend` and the two implementations, not in `GeminiBackend`.

## Deviations from Plan

None - plan executed as written.

The Supabase request body is not asserted: `SupabaseGeminiBackend` takes a concrete `SupabaseClient` and the existing test file has no fake client, which the plan allowed for. The call shape is covered by review and the Edge Function contract tests in plan 03.

## Deferred Issues

- `test/gemini_backend_service_test.dart` has a pre-existing `analyzePhysiqueCheckIn on Unconfigured throws not-configured` test nested inside `_resultMap` after a `throw`, so it is dead code and never runs (analyzer `dead_code` warning). Out of scope for this plan; it should be moved into `main()`.

## Known Stubs

None.

## Threat Flags

None. T-29-36 to T-29-39 mitigated: no database dependency (asserted by a source-scan test), causal wording -> rejected, fixed messages never include raw exception text (asserted with a sentinel string), quotaExhausted is its own kind.

## TDD Gate Compliance

Task 2: `test(29-09)` commit f9f76cf precedes `feat(29-09)` commit bb1d7a3. Task 1 added its test and implementation in one commit (the test depends on the new symbols).

## Self-Check: PASSED

Both created files exist; commits 1300e5d, f9f76cf, bb1d7a3 are in git history.
