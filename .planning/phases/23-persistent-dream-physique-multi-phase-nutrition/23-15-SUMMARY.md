---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 15
subsystem: ui
tags: [flutter, riverpod, physique, nutrition, guardrails, providers]

requires:
  - phase: 23-09
    provides: PhysiqueSummaryBridge
  - phase: 23-11
    provides: physique providers, PhysiqueGoalStarter, eligibility providers
  - phase: 23-13
    provides: StartNewGoalDialog, NoFaceFoundDialog
provides:
  - Eligibility-gated phase chips at both nutrition editor sites (PHYS-04)
  - savePhysiqueGoal (D-03 confirm, D-07 blur toggle and no-face dialog, stage then persist)
  - BaselinePrivacyDialog
  - Database-backed dreamPhysiqueSummaryProvider and dreamPhysiqueSummaryHistoryProvider
  - Profile summary card link to the progress route
  - Coerced "Set targets" deep link on the nutrition-direction card
affects: [23-16, 23-17, 27]

tech-stack:
  added: []
  patterns:
    - "Effective phase derived live from eligibility (getter), never captured into state"
    - "Save path never throws: failure is logged and staged files discarded"

key-files:
  created:
    - lib/features/physique/presentation/save_physique_goal.dart
    - lib/features/physique/presentation/dialogs/baseline_privacy_dialog.dart
    - test/features/physique/save_physique_goal_test.dart
    - test/features/physique/physique_summary_providers_test.dart
  modified:
    - lib/features/nutrition/presentation/views/nutrition_targets_view.dart
    - lib/features/profile/presentation/dream_physique_view.dart
    - lib/features/profile/presentation/widgets/dream_physique_summary_card.dart
    - lib/features/profile/presentation/widgets/dream_physique_nutrition_direction_card.dart
    - lib/app/providers.dart
    - test/features/nutrition/nutrition_targets_view_test.dart
    - test/dream_physique_summary_card_test.dart
    - test/dream_physique_nutrition_direction_card_test.dart

key-decisions:
  - "No phys04_gate part file was needed: nutrition_targets_view.dart grew by 28 lines net (budget 40)"
  - "dream_physique_view.dart shrank by 9 lines net and dropped the summary-repository import"
  - "dreamPhysiqueSummaryRepositoryProvider kept as the legacy migration source"

requirements-completed: []

duration: 55min
completed: 2026-10-02
---

# Phase 23 Plan 15: Wire physique machinery into existing surfaces Summary

**Cut and Bulk are blocked for under-18 and missing-age users at both nutrition editor gate sites, and a Dream Physique analysis now creates a persistent goal (confirm, blur choice, sanitised photos, proposed roadmap) while the old summary providers read the database.**

## Tasks

1. Eligibility gates in the nutrition targets editor - `02e6b71`
2. Goal-creating save path, DB-backed providers, summary card link, coerced deep link - `9700713`

## Accomplishments

- Quick planner and `TargetEditorView` pass `eligibility` to `DietPhaseCalculator.apply`, disable restricted chips (not removed), show `RestrictionNoticeList` with "Add age in Profile" for a missing age, and guard `_applyPhase` / `_onPhaseSelected`. `_effectivePhase` is a live getter so an allowed phase returns when the profile arrives.
- `savePhysiqueGoal` runs after the result is revealed; failures are logged and never discard the result.
- `dreamPhysiqueSummaryProvider` / history are StreamProviders over `physiqueSummaryBridgeProvider`; names and model unchanged.
- Summary card: with a goal, "New analysis" pill, "View progress" label and body tap to `AppRoutes.dreamPhysiqueProgress`; without a goal identical to before.
- Direction card "Set targets" pushes `eligibility.coerce(dietPhase)` using roadmap eligibility when a goal exists, else editor eligibility.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Direction card read an unloaded provider on press**
- **Found during:** Task 2 (low-confidence coercion test)
- **Issue:** `ref.read(activePhysiqueGoalProvider).valueOrNull` at press time returned null because nothing had listened, so a low-confidence goal fell back to age-only eligibility and Cut was not coerced.
- **Fix:** the card now `ref.watch`es `activePhysiqueGoalProvider` in build so the goal is loaded.
- **Files modified:** dream_physique_nutrition_direction_card.dart
- **Commit:** 9700713
- The existing direction-card test also gained an `activePhysiqueGoalProvider` null override (setup only).

### Planner-added copy (flagged)
- `BaselinePrivacyDialog`: title "Photo privacy" and a "Cancel" TextButton (not in UI-SPEC S3 step 2).
- Summary card subtitle "Your imported progress photos" for a goal with no analysis.

## Verification

- `flutter test` (compat suite + `test/features/physique` + `test/features/nutrition`): 570 passed
- `flutter analyze lib test`: 0 errors; none of the remaining 42 infos/warnings are in files touched here
- `dart format` clean; `check_structure`: 57 violations (baseline), none in `features/physique`
- No string-literal `/dream-physique` routes outside `routes.dart`

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

Created files exist; commits 02e6b71 and 9700713 present.
