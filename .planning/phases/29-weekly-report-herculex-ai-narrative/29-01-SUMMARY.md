---
phase: 29-weekly-report-herculex-ai-narrative
plan: 01
subsystem: weekly-report
tags: [iso-week, dst, causal-language-guard, narrative-parser, routes, tdd]

requires: []
provides:
  - "IsoWeek value type (ISO 8601 key, DST-safe window, notification-tap week resolution)"
  - "CausalLanguageGuard.firstViolation and its single-source word list"
  - "WeeklyNarrative strict parser (fromJson, tryDecodeStored, toJson)"
  - "AppRoutes.weeklyReports, AppRoutes.weeklyReport, AppPaths.weeklyReport"
affects: [29-02, 29-05, 29-06, 29-07, 29-09, 29-10, 29-18]

tech-stack:
  added: []
  patterns:
    - "Thursday-rule ISO week with UTC-normalised day numbers and DateTime(y, m, d + n) window boundaries"
    - "Strict FormatException parse with an optional guard flag so stored AI text re-parses structurally"

key-files:
  created:
    - lib/features/weekly_report/domain/iso_week.dart
    - lib/features/weekly_report/domain/causal_language_guard.dart
    - lib/features/weekly_report/domain/weekly_narrative.dart
    - test/features/weekly_report/iso_week_test.dart
    - test/features/weekly_report/causal_language_guard_test.dart
    - test/features/weekly_report/weekly_report_routes_test.dart
  modified:
    - lib/app/router/routes.dart

key-decisions:
  - "forNotificationTap opens the ISO week of the most recent Sunday-at-HH:MM instant <= now (OQ1, user-confirmed 2026-10-03); malformed time falls back to 18:00"
  - "CausalLanguageGuard.patterns holds regex fragments (caus(?:e|es|ed|ing), that's/that’s/that is why) with a space meaning any whitespace run; the list lives only in causal_language_guard.dart"
  - "tryDecodeStored skips the guard on purpose so a later word-list change can never orphan a saved narrative"

patterns-established:
  - "Routes: constants in AppRoutes, concrete builders in AppPaths; router.dart registration deferred to plan 18"

requirements-completed: []
requirements-partial: [RPT-01, RPT-03, RPT-05]

duration: 20min
completed: 2026-10-03
---

# Phase 29 Plan 01: IsoWeek, CausalLanguageGuard, WeeklyNarrative and route constants Summary

**Pure-Dart foundation for the weekly report: a Thursday-rule IsoWeek key with DST-safe windows and tap-time week resolution, a table-tested causal-wording guard feeding a strict WeeklyNarrative parser, and the report route constants.**

## What was built

- `IsoWeek` (`domain/iso_week.dart`): `fromDate`, `tryCreate` (rejects week 0, week 53 in 52-week years, years outside 2000..2100), `weeksInYear`, `start` / `endExclusive` / `startIso` / `endIso`, `previous`, `windowEnd(now)`, `isAfter`, `compareTo`, `==`/`hashCode` (usable as a Map or Riverpod family key), and `forNotificationTap(now, 'HH:MM')`. No wall-clock reads and no Flutter or drift imports.
- `CausalLanguageGuard` (`domain/causal_language_guard.dart`): word-boundary, case-insensitive matcher over a single `patterns` list. `caus*` is matched as `caus(e|es|ed|ing)` so `caution` and `pause` never match.
- `WeeklyNarrative` (`domain/weekly_narrative.dart`): summary of at most 700 characters plus 2-3 suggestions of at most 300 each, `FormatException` on every miss, causal rejection naming the token, `checkCausalLanguage: false` to skip only the guard, `tryDecodeStored` that never throws, and `toJson`.
- Route constants and `AppPaths.weeklyReport(isoYear, isoWeek)`; `router.dart` is untouched (plan 18 registers the GoRoutes).

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | a5b20af | failing IsoWeek test |
| 1 GREEN | 800cc4d | IsoWeek implementation |
| 2 RED | e68b744 | failing guard and narrative tests |
| 2 GREEN | bcdea9a | CausalLanguageGuard and WeeklyNarrative |
| 3 | d98c195 | route constants plus route test |

## Verification

- `flutter test test/features/weekly_report`: 79 passed.
- `flutter analyze lib/features/weekly_report lib/app/router/routes.dart test/features/weekly_report`: no issues.
- `dart run tool/check_structure.dart`: no violation mentions weekly_report or routes.dart.
- `'/weekly-report` literals appear only in `lib/app/router/routes.dart`; `responsible for` appears in lib only in `causal_language_guard.dart`.
- TDD gate: `test(...)` commits precede `feat(...)` commits for tasks 1 and 2.

## Deviations from Plan

None - plan executed exactly as written.

Note on an acceptance check: `grep -c "DateTime.now" iso_week.dart` is documented as outputting 0, but the unescaped `.` in the pattern also matches the parameter text `DateTime now`, so it reports 2. There is no call to the wall clock; the only literal mention in a doc comment was reworded.

## Requirements

RPT-01, RPT-03 and RPT-05 are listed in the plan frontmatter but only their foundation is delivered here (week key and window, tap-week resolution and route constants, and the correlation-only wording gate). Following the repo's partial-completion convention they are left unchecked in REQUIREMENTS.md until the persistence, notification, calculator and UI plans land.

## Known Stubs

None.

## Threat Flags

None. T-29-01 to T-29-03 are mitigated as planned (strict parse plus guard; `tryCreate` returns null for impossible deep-link weeks, to be consumed in plan 18); T-29-04 accepted.

## Self-Check: PASSED

All six created files and the modified routes.dart exist; commits a5b20af, 800cc4d, e68b744, bcdea9a and d98c195 are present in git history.
