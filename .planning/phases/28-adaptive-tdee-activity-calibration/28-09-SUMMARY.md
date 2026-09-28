---
phase: 28-adaptive-tdee-activity-calibration
plan: 09
subsystem: nutrition-ui
tags: [tdee, badge, sheet, riverpod, design-system]
requires:
  - phase: 28-07
    provides: tdeeEstimateProvider, latestTdeeEstimateProvider
  - phase: 28-08
    provides: maintenance field reads maintenanceKcalProvider
provides:
  - TdeeEstimateBadge (public, presentation/widgets)
  - TdeeEstimateSheet + showTdeeEstimateSheet + tdeeBadgeVisuals (public, presentation/sheets)
  - savedTargetForTodayProvider (saved manual rule, never the baseline fallback)
affects: [phase-29-weekly-report]
tech-stack:
  added: []
  patterns:
    - "Public badge/sheet files instead of part files so Phase 29 can reuse them"
    - "Saved target comes from TargetResolver.resolveRule, not effectiveTargetsProvider"
key-files:
  created:
    - lib/features/nutrition/application/tdee_display_providers.dart
    - lib/features/nutrition/presentation/sheets/tdee_estimate_sheet.dart
    - lib/features/nutrition/presentation/widgets/tdee_estimate_badge.dart
    - test/features/nutrition/tdee_estimate_sheet_test.dart
    - test/features/nutrition/tdee_estimate_badge_test.dart
  modified:
    - lib/features/nutrition/presentation/views/nutrition_targets_view.dart
    - lib/design_system/components/hx_stat_tile.dart
key-decisions:
  - "HxStatTile label and value are now Flexible so long captions and figures wrap instead of overflowing"
  - "Badge hit area is a 44px GestureDetector around an HxPill that keeps its own onTap"
  - "Held (aging) estimates with no measured_at fall back to estimatedAt for the relative date"
requirements-completed: [TDEE-04]
duration: about 55 min
completed: 2026-09-28
---

# Phase 28 Plan 09: TDEE Badge and Detail Sheet Summary

**Inline "Measured / Classified / Calibrating" badge under Maintenance calories that opens a read-only sheet with method, true data span (span_days + 1), confidence, per-method inputs and a no-delta comparison against the saved manual target.**

## Accomplishments

- Badge always shows method and confidence once an estimate exists (cold start, stream error and stored cold-start rows all read "Calibrating — using onboarding estimate"), reserves 44px while the profile or estimate stream loads, renders nothing when the profile lacks weight, height or age, and reports a stream error once through `ErrorLog`.
- Sheet lists classifier inputs individually; active calories, sleep and resting HR sit under a separate "Also recorded (not used in the estimate)" caption, never in WHAT WE USED. The window line and food-days denominator use `span_days + 1`; the winning-candidate `window_days` is never printed and is omitted when `span_days` is missing.
- Saved target and estimate render as two tiles (stacked below 400dp) with a `set manually` caption under the saved tile and no delta, arrow or judgement colour. No accept/dismiss controls exist (D-10 stays in Phase 29).
- `nutrition_targets_view.dart` grew by 3 lines (2615 to 2618, ceiling 2635).

## Task Commits

1. Task 1: sheet, provider, HxStatTile fix - `c796dfd`
2. Task 2: badge and placement - `3f1ca3d`

## Deviations from Plan

**1. [Rule 3 - Blocking] HxStatTile overflowed in the narrow and 2x-text cases the plan requires**
- **Found during:** Task 1 (sheet tests at 360dp and 2x text scale, and side by side at 600dp)
- **Issue:** The plan said not to modify `HxStatTile` and to stack below 400dp. Measured, the `MAINTENANCE ESTIMATE` label alone needs about 290dp of tile width at 1x, so even a full-width tile at 360dp with 2x text (label about 520px, value `2,400 kcal` about 436px) overflowed, and a half-width tile at 600dp overflowed by 9px. The plan's "no overflow at 360dp / 2x" and "side by side at 600dp" acceptance cannot be met with the unmodified tile.
- **Fix:** In `hx_stat_tile.dart`, wrapped the label and the value in `Flexible` (plus an `HxSpace.x2` gap before the icon bubble). No visual change when content fits; it wraps instead of overflowing. The 400dp stack rule from the plan is kept as written.
- **Files modified:** lib/design_system/components/hx_stat_tile.dart
- **Verification:** sheet tests at 360dp (1x, 2x), 600dp side by side, and 2x; full suite green (existing users `macro_grid.dart`, `training_level_view.dart` unaffected).
- **Commit:** c796dfd

**2. [Rule 3 - Blocking] Literal grep gate matched `DateTime now` parameters**
- `grep -n "DateTime.now"` treats `.` as a wildcard and matched `DateTime now` / `DateTime(now`. Renamed those locals to `asOf` / `at` so the gate returns nothing. No behaviour change; all time still goes through `Clock`.

**3. [Rule 2 - Missing coverage] Added provider tests**
- The plan listed only widget tests. Added four `savedTargetForTodayProvider` unit tests (no rows is null, global rule, weekday beats global, training-day rule only on a training day) to the sheet test file.

Otherwise the plan executed as written.

## Verification

- Full `flutter test`: **1627 passed, 9 skipped, 0 failed** (previous baseline 1586 passed, 9 skipped).
- `flutter analyze`: 0 errors (42 pre-existing infos/warnings).
- `dart run tool/check_structure.dart`: 58 violations, none in the new files.
- Grep gates: no `AppColors`/colour literals, no `secondaryValue`, no accept copy, no `subtitle:`, no `window_days` outside comments in the sheet; `TdeeEstimateBadge` appears once in the view.

## Known Stubs

None.

## Threat Flags

None. The sheet is read-only (T-28-36), reads inputs with `is num` / `is String` checks and omits rows instead of throwing (T-28-35), clamps classifier confidence via `TdeeBadgeState.label` (T-28-38) and derives the window from `span_days + 1` (T-28-38b).

## Notes for later plans

- `dart format` on `lib/features/nutrition` reformats the unrelated `rambler_food_dialog.dart`; it was reverted, not committed.
- Content narrower than 400dp (every phone in portrait) stacks the tiles; wider hosts show them side by side with the tile captions wrapping onto two lines if needed.

## Self-Check: PASSED

All five created files exist; commits `c796dfd` and `3f1ca3d` exist in `git log`.
