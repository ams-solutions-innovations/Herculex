---
phase: 28-adaptive-tdee-activity-calibration
plan: 10
subsystem: nutrition-profile-onboarding
tags: [tdee, activity-level, profile, onboarding, widget-test]
requires:
  - phase: 28-07
    provides: latestTdeeEstimateProvider and the forced recalibration on ActivityLevel change
provides:
  - ActivityResetPolicy (pure state rules, actionFor branching, locked copy)
  - ActivityLevelSection (Profile picker with caption, confirm dialog, snackbar)
  - Onboarding activity step reframed as a starting estimate
affects: [28-11]
tech-stack:
  patterns: [pure policy in domain/, small ConsumerWidget extracted so a huge view stays out of widget tests]
key-files:
  created:
    - lib/features/nutrition/domain/activity_reset_policy.dart
    - lib/features/profile/presentation/widgets/activity_level_section.dart
    - test/activity_reset_policy_test.dart
    - test/features/profile/activity_reset_flow_test.dart
  modified:
    - lib/features/onboarding/presentation/onboarding_view.dart
    - lib/features/profile/presentation/profile_view.dart
    - lib/features/profile/presentation/profile_view/_body.part.dart
    - lib/features/profile/presentation/profile_view/_identity.part.dart
key-decisions:
  - "goals_view.dart activity sheet deliberately not relabelled (out of 28-UI-SPEC scope); it writes the same seed field so behaviour is identical. Follow-up if the user wants the third surface relabelled."
  - "_ActivityTile moved verbatim into activity_level_section.dart; its hard-coded literals are left to the UI-rework P9 sweep."
  - "Loading (no emission yet) is treated as calibrating: saves immediately, no dialog."
requirements-completed: [TDEE-02, TDEE-04]
duration: ~20min
completed: 2026-09-28
---

# Phase 28 Plan 10: Activity picker reframed as a seed, guarded Profile reset Summary

Onboarding now says "How active are you right now?" with a starting-point subtitle, and the Profile picker becomes a manual reset for calibrated users (confirm dialog plus a measured-aware snackbar) while staying save-on-tap during calibration.

## Tasks

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | ActivityResetPolicy (rules, branching, copy) plus 13 unit tests | 4fa210e |
| 2 | ActivityLevelSection, Profile wiring, onboarding copy, 15-case widget test | 62739cc |

## What changed

- `ActivityResetPolicy` (nutrition/domain, imports only `tdee_estimate.dart`): `isCalibrated`, `isMeasured` (observed and qualified only, so the aging state gets the D-14 snackbar), `actionFor` returning none / saveNow / confirm, and all UI-SPEC strings as constants.
- `ActivityLevelSection` watches only `latestTdeeEstimateProvider`. The reset is the existing profile save passed in as `onChanged`; `ProfileView` still does `setState` plus `_onFieldChanged`, so the plan 07 controller turns the change into a forced recalibration. No Profile code references the estimates table or repository (grep-verified).
- Dialog is a plain `AlertDialog` (non-destructive, no `hx.danger`); scrim dismissal is treated as Keep Current Level.

## Deviations from Plan

None. The unit test was written before the policy file but I did not run it red separately (the import could not resolve until the file existed); the widget test was likewise written first and ran green on first execution.

## Verification

- Full `flutter test`: 1586 passed, 9 skipped, 0 failed.
- `flutter analyze`: 0 errors (42 pre-existing info/warning items; the `directives_ordering` info in `profile_view.dart` is on an existing import pair, not the new line).
- `dart run tool/check_structure.dart`: 58 violations, none new. `onboarding_view.dart` (685 lines) and `_body.part.dart` (1198 lines) were already over 600 and listed; `_body.part.dart` shrank, onboarding grew by 8 lines.
- Acceptance greps: no `_ActivityTile` left in `profile_view/`, no tdee-estimates references under `lib/features/profile`, old onboarding heading gone, `goals_view.dart` untouched, parts have no imports.

## Known Stubs

None.

## Threat Flags

None. The mitigations T-28-39/40/41 hold: no history access from Profile, dialog and method-specific snackbar are widget-tested, and the reset only changes the seed.

## Self-Check: PASSED

Created files exist and commits 4fa210e and 62739cc are in `git log`.
