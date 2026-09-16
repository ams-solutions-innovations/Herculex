---
phase: 19
plan: 01
subsystem: programs/domain
tags: [wave-label, periodization, tdd, pure-function]
requires: []
provides:
  - WaveLabel.compute
  - WaveLabel.selectAnchorSlot
  - WaveLabelInfo
affects:
  - lib/features/programs/domain/wave_label.dart
tech-stack:
  added: []
  patterns:
    - "Map<int, int?>-keyed wave-boundary walk with explicit bounds checks (mirrors programs_repository.dart's null-safe Map lookup shape, adapted for a map whose keys are always in-range)"
    - "Contiguous-run segmentation over the full week range to derive total wave count and current wave index in one pass"
key-files:
  created:
    - lib/features/programs/domain/wave_label.dart
    - test/wave_label_test.dart
  modified: []
decisions:
  - "Day order is the primary sort key in selectAnchorSlot; ProgramExerciseSlots.orderIndex only breaks ties within a day (resolves RESEARCH.md Open Question 1 / Assumption A2, locked in by an explicit test)."
  - "compute() treats a currentWeekIndex out of 0..totalWeeks-1, and a currentWeekIndex with no exerciseIdByWeek entry, identically: both return null rather than throwing."
metrics:
  duration: "~25 minutes"
  completed: "2026-09-16"
---

# Phase 19 Plan 01: Wave-label pure domain functions Summary

One-liner: Pure, unit-tested `WaveLabel.compute()`/`selectAnchorSlot()` functions that derive the "Exercise wave X of Y · Weeks A–B" indicator from a week's anchor slot, with zero drift/Riverpod dependency.

## What Was Built

`lib/features/programs/domain/wave_label.dart` exports:

- `WaveLabelInfo` — immutable `const` record (`waveIndex`, `waveCount`, `waveStartWeek`, `waveEndWeek`) with a `label` getter producing the exact 19-UI-SPEC.md copy string, e.g. `'Exercise wave 2 of 4 · Weeks 3–4'`.
- `WaveLabel.compute({totalWeeks, currentWeekIndex, exerciseIdByWeek})` — walks the wave boundary around `currentWeekIndex` using explicit bounds-checked `Map` lookups, then segments the entire `0..totalWeeks-1` range into contiguous runs to derive the total wave count and which 1-based run contains the viewed week. Returns `null` for an out-of-range week index or an unresolved week (no map entry).
- `WaveLabel.selectAnchorSlot({daysInOrder, allSlots})` — walks days in order, resolves each day's label via the existing `slotLabel ?? name` fallback, filters/sorts that day's slots by `orderIndex`, and returns the first slot with `role == 'main'`. Day order is the primary sort key; `orderIndex` only breaks ties within a day. Returns `null` if no day yields a `main` slot.

Both are pure `static` methods on `abstract final class WaveLabel` — no I/O, no widget/provider dependency, matching `periodization.dart`'s existing style.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - blocking setup] Worktree branch was created from a stale base commit**
- **Found during:** Startup HEAD assertion / plan file read
- **Issue:** The worktree's `worktree-agent-aa3e42379bab05428` branch pointed at `d0c152a`, an ancestor commit that predates the phase 19 planning docs entirely (`.planning/phases/19-.../` didn't exist; `19-01-PLAN.md` was unreadable). The orchestrator's stated expected base was `e40b5c8`, a strict descendant of `d0c152a` on the same `refactor/lib-restructure` line, with zero divergent commits and a clean working tree.
- **Fix:** `git merge --ff-only e40b5c8` — a pure fast-forward (no rebase, no reset, no history rewrite; not a destructive operation) bringing the branch to the expected base so the plan file and its referenced context existed.
- **Files modified:** None (branch pointer only).
- **Commit:** N/A (fast-forward, not a new commit).

**2. [Rule 2 - missing test coverage] Task 2's acceptance criteria required a specific string assertion not present in Task 1's RED test file**
- **Found during:** Task 2 (GREEN)
- **Issue:** Task 2's `<acceptance_criteria>` explicitly requires `WaveLabelInfo.label` to produce `'Exercise wave 2 of 4 · Weeks 3–4'` verbatim, but Task 1's `<behavior>` list (which the RED test file was written against) did not enumerate a dedicated test for the `label` getter itself.
- **Fix:** Added one `test()` block to `test/wave_label_test.dart` asserting the exact string, folded into Task 2's commit alongside the implementation (test-only addition, no change to Task 1's original assertions).
- **Files modified:** `test/wave_label_test.dart`.
- **Commit:** `17822af`.

## Verification

- `flutter test test/wave_label_test.dart` — 12/12 passed (RED confirmed as a missing-symbol compile error before implementation; GREEN confirmed after).
- `flutter analyze lib/features/programs/domain/wave_label.dart test/wave_label_test.dart` — 0 issues.
- `flutter analyze` (full project) — 40 pre-existing issues, none in either file this plan touched.
- `dart run tool/check_structure.dart` — 59 pre-existing violations (baseline drift from CLAUDE.md's stated 51, unrelated to this plan); `wave_label.dart` (114 lines) is not among them.

## TDD Gate Compliance

RED gate: `test(19-01): add failing unit tests for WaveLabel.compute and selectAnchorSlot` (`4f84494`) — confirmed failing via missing-symbol compile error before any production code existed.
GREEN gate: `feat(19-01): implement WaveLabel.compute and selectAnchorSlot` (`17822af`) — confirmed all 12 tests pass.
No REFACTOR commit needed — implementation matched the design cleanly on the first pass.

## Self-Check: PASSED

- FOUND: lib/features/programs/domain/wave_label.dart
- FOUND: test/wave_label_test.dart
- FOUND commit 4f84494
- FOUND commit 17822af
