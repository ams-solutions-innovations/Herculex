---
phase: 27-herculex-ai-program-generation
plan: 11
subsystem: ui
tags: [flutter, riverpod, herculex-ai, program-builder, guardrails]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation (plan 01)
    provides: block_builder_view.dart split into part/part-of mixins, with
      _stepBuildModeAndPriorities() and _create() confirmed stable edit
      targets
  - phase: 27-herculex-ai-program-generation (plan 07)
    provides: "AiBriefRejectionBanner(heading, body, footer) - reused verbatim
      for both D-05 rejection and AIP-05 degradation"
  - phase: 27-herculex-ai-program-generation (plan 08)
    provides: "ProgramGuardrails.validateConfiguration() - the guardrail gate
      this plan calls against the parsed brief's implied configuration"
  - phase: 27-herculex-ai-program-generation (plan 09)
    provides: "HerculexAiBriefService.generateBrief() and
      HerculexAiBriefException.isQuotaExhausted"
provides:
  - "ProgramBuildMode.herculexAi - the 4th build mode, with its mode-picker
    tile and exhaustive-switch subtitle case"
  - "_generateHerculexBrief() (actions.part.dart) - Generate/Regenerate action
    wired end-to-end: generate -> guardrail-gate -> success/rejection/
    degradation, exactly one network call per tap (D-04)"
  - "New _BuilderStateBase fields: _generatingBrief, _acceptedHerculexBrief,
    _herculexBriefProvenance, _herculexRejectionMessage,
    _herculexDegradationMessage - the accepted-brief signal plan 27-13's
    pre-fill/persistence wiring consumes directly"
affects: ["27-13 (pre-fill/persistence wiring consumes _acceptedHerculexBrief
  and _herculexBriefProvenance directly)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Herculex-AI-scoped state fields on _BuilderStateBase are the only
      state _generateHerculexBrief() ever touches - every outcome branch
      (success/rejection/offline/quota) leaves _model/_split/
      _mainMethodByDayLabel untouched, so the existing Smart/Guided
      recommendation is always the fallback by construction, never by a
      separate reset step"
    - "AiBriefRejectionBanner reused for both the 3-part D-05 rejection
      message (heading/body/footer all populated) and the single-sentence
      AIP-05 degradation copy (heading = full sentence, body/footer empty) -
      same widget, two different field-population shapes, per its
      caller-supplies-everything contract from plan 27-07"

key-files:
  created: []
  modified:
    - lib/features/programs/domain/programming_models.dart
    - lib/features/programs/presentation/views/block_builder_view.dart
    - lib/features/programs/presentation/views/block_builder_view/step_mode_and_split.part.dart
    - lib/features/programs/presentation/views/block_builder_view/actions.part.dart
    - test/block_builder_view_test.dart
    - .planning/REQUIREMENTS.md

key-decisions:
  - "AIP-05's two single-sentence degradation messages are rendered via
    AiBriefRejectionBanner with the full sentence in `heading` and empty
    strings for `body`/`footer` - the widget's three fields are all
    required, and UI-SPEC explicitly permits 'adapting as needed' since it
    only locks the copy, not the field split. Chosen over a new component to
    honor the Component Inventory's 'reuse this one widget for every
    distinct rejection/degradation message' instruction from 27-07."
  - "mainMethodByDayLabel: const {} is passed to
    ProgramGuardrails.validateConfiguration() when validating a fresh brief,
    per the plan's interfaces section - documented inline in
    _generateHerculexBrief()'s doc comment so a future reader does not
    mistake the always-zero-issues Max-Effort-per-week check for a skipped
    check; only the 6-day-PPL+Max-Effort structural check is meaningful
    pre-apply."
  - "_generateHerculexBrief() clears _acceptedHerculexBrief/
    _herculexRejectionMessage/_herculexDegradationMessage at the START of
    every call (including Regenerate), so a second call's loading state
    never shows stale Applied/rejection/degradation UI from the prior
    outcome while the new one is in flight."
  - "_herculexBriefProvenance carries an `// ignore: unused_field` directive
    - this plan stores it (per the plan's explicit instruction to leave it
    for 27-13) but never reads it itself, which flutter analyze correctly
    flags as unused; suppressing is more honest than adding a throwaway
    read just to silence the warning."

patterns-established: []

requirements-completed: [AIP-01, AIP-03, AIP-05]

# Metrics
duration: ~70min
completed: 2026-09-30
---

# Phase 27 Plan 11: Herculex AI mode wiring in block_builder_view Summary

**ProgramBuildMode gains a 4th "Herculex AI" value with its mode-picker tile, and an explicit Generate/Regenerate action (D-04: never auto-fired) that calls HerculexAiBriefService.generateBrief(), gates the result through ProgramGuardrails.validateConfiguration(), and renders one of three distinct outcomes (Applied, guardrail-rejected, or offline/quota-degraded) - every branch falling back to the existing Smart/Guided recommendation, never a dead end.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-09-30
- **Completed:** 2026-09-30
- **Tasks:** 2 (Task 1 `type="auto"`, Task 2 `type="auto" tdd="true"`)
- **Files modified:** 5 (plus REQUIREMENTS.md)

## Accomplishments
- `ProgramBuildMode.herculexAi` (`'herculex_ai'`, `'Herculex AI'`) added as the 4th value; the mode picker's `for (final mode in ProgramBuildMode.values)` loop renders its tile automatically once the exhaustive `switch (mode)` subtitle case compiles (Pitfall 3's compile-enforced touch point).
- `_generateHerculexBrief()` (actions.part.dart): calls `HerculexAiBriefService.generateBrief()` exactly once per Generate/Regenerate tap, then `ProgramGuardrails.validateConfiguration()` against the parsed brief's own `splitType`/`periodizationModel` (with an empty `mainMethodByDayLabel`, documented inline per the plan's interfaces section) - a second, independent safety-rule-level gate after the brief's own strict schema parse.
- Three distinct, UI-SPEC-exact outcomes, each leaving the existing Smart/Guided recommendation as the active builder state:
  - **Success (guardrail passes):** `_acceptedHerculexBrief`/`_herculexBriefProvenance` stored; tile shows an "Applied" status chip plus a "Regenerate" secondary action.
  - **Guardrail rejection (D-05):** `AiBriefRejectionBanner` with heading "Herculex AI suggestion couldn't be used", body = the validator's specific issue message verbatim, footer stating the automatic Smart/Guided fallback.
  - **Offline/unconfigured or over-quota (AIP-05):** the respective UI-SPEC-exact single-sentence degradation message, distinguished via `HerculexAiBriefException.isQuotaExhausted`.
- 7 new widget tests in `test/block_builder_view_test.dart` against a fake `GeminiBackend` (`geminiBackendProvider` override, mirroring `test/herculex_ai_brief_service_test.dart`'s `_FakeGeminiBackend` convention) cover every behavior case from the plan's `<behavior>` block, including "selecting the tile alone never fires a network call" (D-04) and "Regenerate re-fires exactly one new call."
- REQUIREMENTS.md: **AIP-03 and AIP-05 marked complete** - this plan is the piece both were waiting on (the guardrail call + fallback UI, and the degrade-to-Smart/Guided UI respectively). AIP-01 was already checked from plan 27-01's original 3-value-enum context but is reconfirmed true with the 4th value now real. AIP-04 remains unchecked (plan 27-12's job).

## Task Commits

1. **Task 1: ProgramBuildMode.herculexAi and the 4th mode tile** - `99aba50` (feat)
2. **Task 2: Generate/Regenerate action, guardrail validation, and the 3 failure states** - `601dfd0` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `lib/features/programs/domain/programming_models.dart` - `ProgramBuildMode.herculexAi` 4th enum value
- `lib/features/programs/presentation/views/block_builder_view.dart` - new imports (`herculex_ai_brief_service.dart`, `program_brief.dart`, `ai_brief_rejection_banner.dart`), 5 new `_BuilderStateBase` fields, `_generateHerculexBrief()` abstract stub
- `lib/features/programs/presentation/views/block_builder_view/step_mode_and_split.part.dart` - the herculexAi subtitle switch case; a 4th-mode-only card (Generate/Regenerate `PremiumButton`, "Applied" status chip) plus conditional `AiBriefRejectionBanner` rendering for both rejection and degradation states
- `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` - `_generateHerculexBrief()`: generate -> guardrail-gate -> success/rejection/degradation state machine
- `test/block_builder_view_test.dart` - `_FakeHerculexGeminiBackend`, `_pumpBuilderWithBackend()` helper, and a 7-test `group('Herculex AI mode (27-11)', ...)`
- `.planning/REQUIREMENTS.md` - AIP-03 and AIP-05 marked `[x]` with updated annotations

## Decisions Made
See `key-decisions` in frontmatter: the AiBriefRejectionBanner field-population split for single-sentence AIP-05 copy, the documented-empty `mainMethodByDayLabel` guardrail call, clearing all three Herculex-AI-scoped outcome fields at the start of every Generate/Regenerate tap, and the `unused_field` suppression on `_herculexBriefProvenance`.

## Deviations from Plan

None - plan executed exactly as written. The `// ignore: unused_field` addition on `_herculexBriefProvenance` is not a deviation from the plan's design (the plan explicitly asks for this field to exist for 27-13 to consume, unused by this plan) - it is the minimal, honest way to keep `flutter analyze` clean without inventing a throwaway read.

## Issues Encountered

None. One minor mechanical correction during implementation: the first `// ignore: unused_field` directive placement (same line as an explanatory comment) did not suppress the warning - Dart's ignore-comment syntax requires the directive to be its own line immediately above the declaration with no trailing text after the rule name. Fixed by moving the explanation to its own comment line above the ignore directive.

## User Setup Required

None - no external service configuration required.

## Validation

- `flutter analyze` on all 5 touched production/test files - **0 issues**.
- `flutter test test/block_builder_view_test.dart` - **17/17 passing** (10 pre-existing unchanged + 7 new).
- Full-repo `flutter analyze` - **0 errors** (42 pre-existing warnings/info across unrelated files, matching the baseline recorded in 27-08/27-09's summaries - no new issues introduced).
- `wc -l` confirms all touched files stay well under CLAUDE.md's 600-line cap: `block_builder_view.dart` 419, `step_mode_and_split.part.dart` 547, `actions.part.dart` 272.

## Next Phase Readiness

- **For plan 27-13:** `_acceptedHerculexBrief` (`ProgramBrief?`) and `_herculexBriefProvenance` (`Map<String, dynamic>`) on `_BuilderStateBase` are the exact "brief accepted, ready to pre-fill" signal to consume - non-null `_acceptedHerculexBrief` means a guardrail-passing brief is sitting in state, ready for 27-13's pre-fill-the-builder-screens and `persistBrief()` call. Neither field is written to any other state during this plan; 27-13's own logic decides when/how to apply them.
- **For plan 27-12:** No overlap - this plan does not touch `program_review_view.dart`; `AiDayRationaleCard` remains fully unwired there, per plan 27-07's summary.
- No blockers for Phase 27's remaining plans.

## Threat Flags

None beyond the plan's own `<threat_model>` (T-27-17, T-27-18), both fully mitigated as designed: every accepted brief passes `ProgramGuardrails.validateConfiguration()` before being stored (T-27-17), and `_generatingBrief` guards the Generate/Regenerate button to a no-op while a call is in flight, preventing concurrent quota-consuming taps (T-27-18).

## Known Stubs

None. Both the success and every failure path are fully wired to the real `HerculexAiBriefService`/`ProgramGuardrails` - no placeholder/mock data in production code.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*

## Self-Check: PASSED

All 5 modified production/test files, this SUMMARY.md, and REQUIREMENTS.md verified
present on disk; both task commit hashes (`99aba50`, `601dfd0`) verified present in
`git log --oneline --all`.
