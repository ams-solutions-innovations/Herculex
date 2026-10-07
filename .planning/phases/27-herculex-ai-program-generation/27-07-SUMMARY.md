---
phase: 27-herculex-ai-program-generation
plan: 07
subsystem: ui
tags: [flutter, design-system, hx-colors, widget-test, herculex-ai]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation
    provides: "27-UI-SPEC.md's Component Inventory / Spacing / Typography / Color / Copywriting Contract sections for these two widgets"
provides:
  - "AiBriefRejectionBanner(heading, body, footer) - stateless warning-tinted banner for Herculex AI rejection/degradation messages (D-05, AIP-05)"
  - "AiDayRationaleCard(rationale) - stateless primary-tinted card rendering a brief's per-day rationale verbatim under a fixed 'Why this day' heading (AIP-04, D-09)"
affects: ["27-11 (block_builder_view.dart wiring)", "27-12 (program_review_view.dart wiring)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "New Herculex AI presentational widgets read colors exclusively via context.hx.* (HxColorsContext), never AppColors.* or literal Color(0xFF...), per UI-SPEC's scope-local token rule for new code in legacy AppColors-era files"
    - "New widgets use HxSpace/HxRadius geometry tokens instead of hardcoded padding/radius literals"

key-files:
  created:
    - lib/features/programs/presentation/widgets/ai_brief_rejection_banner.dart
    - lib/features/programs/presentation/widgets/ai_day_rationale_card.dart
    - test/ai_brief_rejection_banner_test.dart
    - test/ai_day_rationale_card_test.dart
  modified: []

key-decisions:
  - "Footer text in AiBriefRejectionBanner uses context.hx.onSurfaceVariant (the codebase's established muted-text token, confirmed via grep against 5+ existing files) since UI-SPEC's Color section doesn't name an explicit token for the footer line, only 'slightly muted/secondary color' in the plan's action guidance"
  - "AiDayRationaleCard's heading 'Why this day' is a private static const (widget-internal, per UI-SPEC's explicit note it never varies), while AiBriefRejectionBanner's heading/body/footer are all required constructor parameters so plan 27-11 can reuse the same widget for both the D-05 rejection message and the distinct AIP-05 offline/unconfigured/over-quota degradation copy"
  - "Icon choice: Icons.warning_amber_rounded for the rejection banner (Material's canonical warning glyph, matches the _rounded family UI-SPEC mandates) since UI-SPEC named the icon family/color but not an exact glyph"

requirements-completed: [AIP-03, AIP-04]

# Metrics
duration: 15min
completed: 2026-09-30
---

# Phase 27 Plan 07: Herculex AI Rejection Banner & Day Rationale Card Summary

**Two new token-compliant stateless widgets — AiBriefRejectionBanner (warning-tinted, heading/body/footer) and AiDayRationaleCard (primary-tinted, fixed "Why this day" heading) — both visual siblings of EmptySlotNotice, independently unit-tested, ready for plans 27-11/27-12 to import with zero further design decisions.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-09-30T08:23:44Z
- **Completed:** 2026-09-30T08:30:30Z
- **Tasks:** 1
- **Files modified:** 4 (all new)

## Accomplishments
- `AiBriefRejectionBanner(heading, body, footer)` built: `context.hx.warning`-tinted `Container`/`Column` with an icon+heading `Row`, then body, then footer — all three strings passed in by the caller, never hardcoded, so plan 27-11 can reuse this one widget for both the D-05 rejection message and the AIP-05 offline/unconfigured/over-quota degradation copy (different text, same shape).
- `AiDayRationaleCard(rationale)` built: `context.hx.primary`-tinted `Container` with an `auto_awesome_rounded` icon, the fixed "Why this day" heading, and the rationale rendered verbatim below with no `maxLines`/`overflow` restriction.
- 12 widget tests across both new test files (6 each: verbatim-text rendering, token-color assertions on the `Icon` and heading `Text` widgets, no-throw smoke test — each run against both light and dark `AppTheme`).
- Confirmed via grep: zero occurrences of `AppColors` or a literal `Color(0xFF...)` in either new widget file.

## Task Commits

Each task was committed atomically:

1. **Task 1: AiBriefRejectionBanner and AiDayRationaleCard** - `7058d9c` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `lib/features/programs/presentation/widgets/ai_brief_rejection_banner.dart` - Warning-tinted rejection/degradation banner widget (77 lines)
- `lib/features/programs/presentation/widgets/ai_day_rationale_card.dart` - Primary-tinted per-day rationale card widget (63 lines)
- `test/ai_brief_rejection_banner_test.dart` - 6 widget tests (light/dark)
- `test/ai_day_rationale_card_test.dart` - 6 widget tests (light/dark)

## Decisions Made
See `key-decisions` in frontmatter: footer text color token choice, heading parameterization split between the two widgets, and the specific warning icon glyph — all filled gaps the plan's `<interfaces>`/UI-SPEC left as implementation discretion, not deviations from anything explicitly specified.

## Deviations from Plan

None - plan executed exactly as written. Both widgets match every UI-SPEC requirement (HxSpace.x3 padding on the rejection banner, titleSmall/w700/15px headings, bodySmall/13px/400 body/footer text, warning token on the rejection banner never danger, primary token on the rationale card never applied to its body text).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both widgets are drop-in ready for plan 27-11 (`AiBriefRejectionBanner` inside `block_builder_view.dart`) and plan 27-12 (`AiDayRationaleCard` inside `program_review_view.dart`) — zero further design decisions left for those plans on these two components.
- This was the last plan in Wave 1; no shared files with any of the other 6 Wave 1 plans, so no regression risk introduced to their work.
- `flutter analyze` on the 4 touched files: 0 issues. `flutter test` on the 2 new test files: 12/12 passing. Full-repo `flutter test`/`flutter analyze` were not re-run standalone this session (per this plan's own scope note — pure new-file addition, no existing file touched); the orchestrator's wave-level full-suite check still applies before the phase gate.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*

## Self-Check: PASSED

All 5 claimed files found on disk; commit `7058d9c` found in git log.
