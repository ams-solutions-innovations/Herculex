---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 16
subsystem: ui
tags: [flutter, riverpod, go_router, physique, roadmap, check-in]

requires:
  - phase: 23-11
    provides: physique providers (phase status, eligibility, check-ins, photos)
  - phase: 23-12
    provides: chart cards and chart providers
  - phase: 23-13
    provides: RoadmapEditorSheet, CheckInHistorySheet, PastGoalsSheet, GoalDisplayCopy
  - phase: 23-14
    provides: CheckInSheet.show(resumed:), physiqueResumedCaptureProvider
provides:
  - PhysiqueProgressView(goalId?) at AppRoutes.dreamPhysiqueProgress
  - GoalHeaderCard, ActivePhaseCard (advance prompt), RoadmapTimelineCard, CheckInCard
  - PhysiqueLoading / PhysiqueLoadError shared card states
affects: [23-17]

tech-stack:
  added: []
  patterns:
    - "Cards are ConsumerWidgets keyed by goalId; the view only composes and derives advancePromptVisible"
    - "Wrap(spaceBetween) instead of Row for title + trailing label so 320 dp / 2.0x text reflows"

key-files:
  created:
    - lib/features/physique/presentation/widgets/goal_header_card.dart
    - lib/features/physique/presentation/widgets/active_phase_card.dart
    - lib/features/physique/presentation/widgets/roadmap_timeline_card.dart
    - lib/features/physique/presentation/widgets/check_in_card.dart
    - lib/features/physique/presentation/widgets/load_state_views.dart
    - lib/features/physique/presentation/views/physique_progress_view.dart
    - test/features/physique/presentation/phase_cards_test.dart
    - test/features/physique/presentation/physique_progress_view_test.dart
  modified:
    - lib/app/router/router.dart

key-decisions:
  - "Proposal state, baseline-less label and nutrition deep links follow the plan's flagged decisions"
  - "Legacy photos-only goal heading 'Imported progress photos' comes from the shared GoalDisplayCopy helper"
  - "Added widgets/load_state_views.dart (not in the plan's file list) so the loading and 'Try again' lines exist once"

patterns-established:
  - "Real-DB advance/postpone tests tap inside tester.runAsync so drift futures complete"
  - "Route registration verified through the real routerProvider with provider overrides"

requirements-completed: []

duration: ~110min
completed: 2026-10-02
---

# Phase 23 Plan 16: Physique Progress View Summary

**Progress screen at /dream-physique/progress: active phase with exit criteria and a confirm-or-postpone advance prompt that never writes calorie targets, cap-aware check-in card with verdict, range tabs over three charts, read-only archived mode.**

## Accomplishments

- ActivePhaseCard shows phase, "Phase i of n", "Week w of n" with an 8-high bar, tempo line (never kcal), "Exit when" rows, and the advance prompt. "Move to {Phase}" calls only `advancePhase`; "Not yet" calls `postponeAdvance`. Verified against a real in-memory DB: phase rows flip to done/current and `nutrition_targets` row count is unchanged.
- CheckInCard: verdict block (no `%` in the subtree), disabled capped button "Next check-in available Mon, Oct 12" with lock semantics label, outlined "Add check-in" while the advance prompt shows, "Add baseline photo" (never capped) for baseline-less goals, 3-thumbnail strip and "See all check-ins".
- PhysiqueProgressView (203 lines): S1 layout in order, `HxTopTabs` bound to `physiqueChartRangeProvider`, past goals row, empty state, archived read-only mode, resumed-capture hand-off (opens `CheckInSheet` once and clears the provider).
- Route registered in `router.dart` (+7 lines) with `int.tryParse(queryParameters['goalId'])`; tested through the real `routerProvider` for `?goalId=7`, absent and `abc`.
- Tests: 21 in `phase_cards_test.dart`, 28 in `physique_progress_view_test.dart`; `flutter test test/features/physique` passes (452). `flutter analyze lib test` 0 errors (43 pre-existing issues, none in physique/router); `check_structure` still 57 violations, none in `features/physique`.

## Task Commits

1. Task 1: goal header, active phase, roadmap timeline cards - `0862304`
2. Task 2: progress view, check-in card, route - `23b280c`
3. Test cleanup (unused import) - `f32b007`

## Decisions Made (planner-silent areas)

- Proposal state: first proposed phase, "Phase 1 of n", proposal sentence, "Edit roadmap" only (no "Review nutrition targets", no time/exit rows).
- Photos-only legacy goal: heading "Imported progress photos", line "Started {date}".
- When an accepted roadmap has no current phase (all done), the card shows the last phase read-only.
- The restriction notice sits between header and phase card and is hidden for archived goals.
- Past goals row text reads "Past goals · {n}" with a chevron.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Overflow at 320 dp / 2.0 text scale**
- **Found during:** both tasks (320 dp tests)
- **Issue:** The phase-card header Row, the footer "Review nutrition targets" button Row and the check-in card header Row overflowed.
- **Fix:** Header and card titles use `Wrap(spaceBetween)`; the review link is `TextButton.icon(iconAlignment: end)`.
- **Files modified:** active_phase_card.dart, check_in_card.dart
- **Commits:** 0862304, 23b280c

**2. [Rule 3 - Blocking] Added widgets/load_state_views.dart**
- Shared loading and "Couldn't load this right now." / "Try again" widgets used by four cards; not in the plan's file list.

**3. [Rule 1 - Bug] Capped-button semantics not exposed**
- The lock label was merged away; added `container: true, button: true, enabled: false` so the "Check-in locked until ..." label is exposed.

## Known Stubs

None.

## Threat Flags

None. T-23-80..85 mitigations present: non-integer `goalId` parses to null; archived view hides every action; advance only calls `advancePhase`; nutrition links push `AppRoutes.nutritionTargets` with a coerced `DietPhase` only; cap shown as text plus lock semantics while the repository stays the gate.

## Notes for Plan 17

- `requirements-completed` left empty: PHYS-05..08 surfaces exist but the orchestrator reconciles at phase close.
- `.claude/settings.json` and `outputs/` were left untouched and unstaged.

## Self-Check: PASSED

All eight created files and the router edit exist; commits 0862304, 23b280c, f32b007 present.
