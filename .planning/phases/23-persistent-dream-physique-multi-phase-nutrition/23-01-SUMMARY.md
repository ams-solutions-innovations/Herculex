---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 01
subsystem: physique-domain
tags: [dart, domain, guardrails, roadmap, nutrition]
requires: []
provides:
  - PhaseEligibility / PhaseRestrictionReason (nutrition domain)
  - PhysiqueGuardrails, AssessmentConfidence, PhysiqueTuning
  - PhysiqueTempoPolicy, PhysiqueDirectionRule
  - PhysiqueRoadmapGenerator, RoadmapPhaseDraft, RoadmapDraftEditor
affects: [DietPhaseCalculator.apply, DreamPhysiqueNutritionRecommender]
tech-stack:
  added: []
  patterns: [pure-Dart domain, eligibility clamp at single calorie choke point]
key-files:
  created:
    - lib/features/nutrition/domain/phase_eligibility.dart
    - lib/features/physique/domain/physique_tuning.dart
    - lib/features/physique/domain/physique_guardrails.dart
    - lib/features/physique/domain/physique_direction.dart
    - lib/features/physique/domain/physique_tempo_policy.dart
    - lib/features/physique/domain/physique_roadmap.dart
    - lib/features/physique/domain/roadmap_draft_editor.dart
    - test/features/physique/physique_guardrails_test.dart
    - test/features/physique/physique_tempo_policy_test.dart
    - test/features/physique/physique_roadmap_test.dart
  modified:
    - lib/features/nutrition/domain/diet_phase.dart
    - lib/features/profile/domain/dream_physique_nutrition_recommendation.dart
    - test/diet_phase_test.dart
key-decisions:
  - "PhaseEligibility lives in nutrition/domain so nutrition never imports physique"
  - "Old recommender delegates to PhysiqueDirectionRule so first-phase equality is structural"
  - "Unknown confidence is not restricted while unknownConfidenceRestricts is false"
requirements-completed: [PHYS-03, PHYS-04]
duration: ~35min
completed: 2026-10-02
---

# Phase 23 Plan 01: Physique domain core Summary

Pure-Dart eligibility guardrails (under-18, missing age, low confidence) enforced at `DietPhaseCalculator.apply`, plus a deterministic, editable multi-phase roadmap generator whose first phase matches the legacy recommender.

## Commits
- e2fcc00: PhaseEligibility, PhysiqueTuning, PhysiqueGuardrails, eligibility param on apply
- 5dbd096: PhysiqueTempoPolicy, PhysiqueDirectionRule, recommender delegation
- bc6c175: PhysiqueRoadmapGenerator, RoadmapDraftEditor

## Deviations from Plan
None of substance. Small choices where the plan was silent: follow-on maintain phases carry the previous target weight; maintain/recomp drafts carry `weeklyRateKg` 0.0; `plannedWeeks` and `isCapped` use a 1e-9 tolerance against float noise.

## Verification
- `flutter test test/features/physique test/diet_phase_test.dart` plus the two pre-existing dream_physique tests: all pass (33 + 14 + diet_phase).
- `flutter analyze` on touched lib/test paths: no issues. `dart format` clean. No Flutter, `/data/` or `DateTime.now` in `lib/features/physique/domain`.
- `check_structure`: nothing for `features/physique` or `phase_eligibility.dart`.

## Known Stubs
None. Several `PhysiqueTuning` constants are `[ASSUMED]` and unused until later plans (by design).

## Self-Check: PASSED
