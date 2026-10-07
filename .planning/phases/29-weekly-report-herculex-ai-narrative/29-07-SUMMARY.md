---
phase: 29-weekly-report-herculex-ai-narrative
plan: 07
subsystem: weekly-report
tags: [payload, strict-json, prompt-injection, data-minimisation, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "IsoWeek (29-01), used for the payload week identity and impossible-week rejection"
provides:
  - "WeeklyReportPayload: versioned (v1) strict-parsed snapshot for weekly_reports.payload_json"
  - "NutritionSection, TrainingSection, RecoverySection, PhysiqueSection, TdeeSection, TopFood, E1rmMover, CorrelationLine value classes plus ReportJson strict readers"
  - "WeeklyReportFacts.fromPayload: sanitised, deterministic, 8000-char-capped model input"
affects: [29-08, 29-09, 29-10, 29-11, 29-12, 29-13, 29-18]

tech-stack:
  added: []
  patterns:
    - "ReportJson strict readers (num-tolerant, finite-only, FormatException, no ! casts) shared by every section"
    - "Facts reduction ladder keyed by level, rebuilt from the payload each step so output stays deterministic"

key-files:
  created:
    - lib/features/weekly_report/domain/weekly_report_sections.dart
    - lib/features/weekly_report/domain/weekly_report_payload.dart
    - lib/features/weekly_report/domain/weekly_report_facts.dart
    - test/features/weekly_report/weekly_report_payload_test.dart
    - test/features/weekly_report/weekly_report_facts_test.dart
  modified: []

key-decisions:
  - "hasSignal excludes tdee (history-derived, D-06); hasNarrativeSignal is nutrition/training/recovery only"
  - "Null sections are omitted from the facts map rather than sent as null"
  - "fromJson also rejects impossible ISO weeks via IsoWeek.tryCreate, in addition to the version/type checks the plan requires"
  - "WeeklyReportFacts.fromPayload takes an optional maxLength (default 8000) purely so tests can exercise the reduction ladder"
  - "Facts enforce their own list caps (3 foods, 3 movers, 5 warnings, 4 correlations) so the 8000 cap is a backstop and the ladder is reached only for absurd text lengths"

patterns-established:
  - "sanitizeText: whitespace-like controls become a space, other controls are dropped, runs collapsed, truncation by code point"

requirements-completed: []
requirements-partial: [RPT-01, RPT-02, RPT-05]

duration: 25min
completed: 2026-10-03
---

# Phase 29 Plan 07: Weekly report payload, sections and facts Summary

**A strict, versioned weekly-report payload with five section value classes, plus a facts builder that sanitises user text, strips ids and notes, and keeps the model input deterministic and under the 8000-character server cap.**

## What was built

- `weekly_report_sections.dart`: `NutritionSection`, `TrainingSection`, `RecoverySection`, `PhysiqueSection`, `TdeeSection` and the small `TopFood`, `E1rmMover`, `CorrelationLine` types. `ReportJson` holds the strict readers (accept `num` for numeric fields, reject NaN and infinity, throw `FormatException`, no `!` casts). `TopFood.truncated` / `fromJson` cap names at 60 characters.
- `weekly_report_payload.dart`: `WeeklyReportPayload` with `currentVersion = 1`, `week`, `hasSignal`, `hasNarrativeSignal`, `toJson`, `fromJson`, `fromJsonString` (throws) and `tryDecode` (null on any failure). Unknown or missing `payloadVersion`, a bad `windowEnd`, an impossible ISO week or any wrong-typed section field throws.
- `weekly_report_facts.dart`: `WeeklyReportFacts.sanitizeText` and `fromPayload`. Output carries week identity, per-section aggregates, up to 3 sanitised food names (40 chars), up to 3 sanitised mover names, up to 5 warnings (80 chars), up to 4 pre-templated correlation statements (160 chars) and the TDEE drift numbers. Reduction ladder: drop top foods, cap warnings at 2, keep correlation text only for the first line, then (last resorts) drop all warnings, all correlations, all movers.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | 0b2ba0f | failing payload test |
| 1 GREEN | e0cc8bd | sections and payload |
| 2 RED | 5974d9b | failing facts test |
| 2 GREEN | 7081636 | WeeklyReportFacts |

## Verification

- `flutter test test/features/weekly_report`: 124 passed (includes the 79 from plan 01 and the plan 05 tests).
- `flutter analyze lib/features/weekly_report test/features/weekly_report`: no issues.
- `check_structure` reports nothing for weekly_report. No `package:flutter` / `package:drift` imports in any new domain file; no `DateTime.now`.
- TDD gate: `test(...)` commit precedes `feat(...)` commit for both tasks.

## Deviations from Plan

### Auto-added

**1. [Rule 2 - Missing critical] Impossible ISO week rejected in fromJson**
- **Found during:** Task 1
- **Issue:** The plan lists version and type checks only; a pulled row with `isoWeek: 99` would produce a payload whose `week` getter is not a real week.
- **Fix:** `fromJson` calls `IsoWeek.tryCreate` and throws `FormatException` when null.
- **Files modified:** weekly_report_payload.dart

**2. [Rule 3 - Testability] Optional `maxLength` parameter on `fromPayload`**
- **Issue:** With the per-list caps the facts never approach 8000 characters from realistic input, so the ladder could not be tested through the default cap.
- **Fix:** `fromPayload(payload, {maxLength = maxJsonLength})`; default behaviour is unchanged.

No other deviations.

## Requirements

RPT-01, RPT-02 and RPT-05 are only partly delivered here (the data contract and the model-input builder). They stay unchecked in REQUIREMENTS.md until the calculators, service and UI plans land, following the repo's partial-completion convention.

## Known Stubs

None.

## Threat Flags

None. T-29-28 to T-29-31 mitigated as planned: sanitisation and name caps (T-29-28), aggregate-only facts with a forbidden-key test (T-29-29), strict parsing with no `!` casts (T-29-30), client-side reduction ladder under 8000 characters (T-29-31).

## Self-Check: PASSED

All five created files exist; commits 0b2ba0f, e0cc8bd, 5974d9b and 7081636 are present in git history.
