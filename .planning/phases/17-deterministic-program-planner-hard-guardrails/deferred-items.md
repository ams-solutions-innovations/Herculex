# Deferred Items — Phase 17

Out-of-scope discoveries found while executing 17-01, logged per the executor's
scope-boundary rule rather than fixed inline.

## 1. `assets/data/exercise_ergonomics.json` and its Dart consumers are missing from git history entirely

`lib/features/workouts/application/workouts_providers.dart` imports
`package:herculex/features/workouts/data/exercise_ergonomics_repository.dart`
and references `ExerciseErgonomicsRepository`, and `pubspec.yaml` declares
`assets/data/exercise_ergonomics.json` as a bundled asset. None of the
following paths have ever been committed on any branch/ref visible to this
worktree (`git log --all -- <path>` returns nothing for each):

- `assets/data/exercise_ergonomics.json`
- `lib/features/workouts/domain/exercise_ergonomics.dart`
- `lib/features/workouts/data/exercise_ergonomics_repository.dart`

`.planning/phases/14-anthropometric-ergonomics/14-02-SUMMARY.md` claims this
work is done, but it was apparently never committed (likely still sitting
uncommitted in the main checkout alongside the Android widget/icon refactor
noted at spawn time). This breaks `flutter analyze` (1 hard error) and
`flutter test` (fails outright at asset-bundle build time for *every* test,
not just ones touching this feature) in any clean worktree/checkout of this
branch.

**Verification workaround used for 17-01 only:** created two temporary,
untracked stub files (`assets/data/exercise_ergonomics.json` = `{}`,
`lib/features/workouts/data/exercise_ergonomics_repository.dart` = a
no-op `ExerciseErgonomicsRepository` with a `load()` method) purely to let
`flutter test` run long enough to verify this plan's own new/modified files.
Both stub files were deleted again before committing — nothing from this
workaround is present in 17-01's commits.

**Action needed:** commit the real Phase 14-02 deliverable from wherever it
currently lives (main checkout, uncommitted), or re-run that plan, before any
later Phase 17 wave that needs `flutter test` to pass end-to-end.

## 2. `lib/features/programs/presentation/views/program_review_view.dart` does not exist

Plan 17-05's `<files>`/`<read_first>` sections treat this file as already
existing (to be extended, not created), with specific line-number references
to `_load()`, `_DayCard`, `_ReviewDay`. It is not present in this worktree and
has no history under that path (`git log --all -- ...` empty) — the only
similarly-named file present is
`lib/features/programs/presentation/views/program_preview_view.dart`, which
does not contain the `_Notice`/`_ExerciseRow`/`_load()`/`_DayCard` structures
17-05 assumes. 17-01's own Task 3 (`EmptySlotNotice`) worked around this by
building directly from the code snippet already inlined in the 17-01 plan's
`<interfaces>` block rather than reading the (non-existent) analog file.

**Action needed:** before executing 17-05, confirm whether
`program_review_view.dart` is uncommitted work sitting in the main checkout
(same root cause as item 1) or needs to be created from scratch as part of an
earlier, currently-missing Phase 17 wave.

## 3. Baseline `flutter analyze` issue count is much larger than expected

`flutter analyze --no-fatal-infos` reports 394 issues (325 errors) on this
branch tip before any 17-01 changes, spanning multiple unrelated features
(`TrainingGoal`/`ExperienceLevel`/`ProgramBuildMode` undefined in
`test/smart_program_planner_test.dart`, `ExerciseReplacementSheet` undefined,
etc.) — consistent with substantial uncommitted work missing from git per
items 1-2. CLAUDE.md's "0 errors" expectation does not hold on a fresh
worktree checkout of `refactor/lib-restructure` right now. None of these
pre-existing errors are in files 17-01 touches (confirmed via targeted grep
against the analyze log); 17-01's own files are clean.
