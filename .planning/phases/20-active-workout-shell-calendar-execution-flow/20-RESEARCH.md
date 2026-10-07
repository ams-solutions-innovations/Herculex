# Phase 20: Active Workout Shell & Calendar Execution Flow - Research

**Researched:** 2026-09-16
**Domain:** Flutter/Riverpod widget extraction, go_router route addition, drift-service-backed read-only preview
**Confidence:** HIGH

## Summary

Phase 20 is a low-ambiguity refactor/wiring phase, not greenfield work — `.planning/phases/20-.../20-CONTEXT.md` (D-01 through D-11) already resolved every architectural question via `/gsd:discuss-phase`, and this research's job was to verify those decisions against current code rather than explore alternatives. All eleven decisions check out against the live codebase, with three material corrections/additions the planner needs:

1. **A second call site shares FLOW-03's bug.** `WeekBoard` (`week_board.dart`) already passes a full `ScheduledWorkoutRow` to `onOpenSession`, and `TrainingBlocksView._openDay` (`training_blocks_view.dart:76-83`) already discards `row.id` there too (`_openDay(context, ref, row.date, program)`), exactly like the `month_calendar.dart` `SessionTile.onTap` bug D-04 names. CONTEXT.md's canonical refs only name the `month_calendar.dart` instance. `_openDay`'s signature needs an optional `int? initialScheduleId` param fed by **both** callers.
2. **D-02's "instant offscreen translation" is an approximation.** The actual current behavior splits across two nested animated widgets: `AnimatedPositioned` (200ms `easeOutCubic` for `bottom`) wrapping `AnimatedOpacity` (`Duration.zero` when hiding, 150ms when restoring). Only the opacity fade is instant on hide; the position slide is always animated. The extraction must preserve this exact split, not just "no animation."
3. **No test in this repo currently exercises `go_router`'s `context.push`/`MaterialApp.router`.** `PlannedWorkoutPreviewView` becoming a real pushed route (D-09) means `test/widgets/day_detail_sheet_test.dart`'s existing "View workout opens preview sheet" test (which asserts against an inline `HxSheet` in the same widget tree) will need a `GoRouter`-backed harness — new infrastructure for this codebase, not just an assertion tweak.

**Primary recommendation:** Follow CONTEXT.md's D-01–D-11 as written; additionally (a) thread `initialScheduleId` through `WeekBoard`'s existing `onOpenSession` path alongside `month_calendar`'s, (b) preserve the exact two-stage animation split when extracting `KeyboardObstructionScope`, and (c) budget a task for building a minimal `GoRouter` test harness before rewriting the "View workout" widget tests.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Keyboard/focus-driven chrome hiding | Presentation (design_system shell primitive) | — | Pure UI state (`workoutInputFocusedProvider` bool + `MediaQuery` inset); no data layer involvement |
| Calendar → specific occurrence routing | Presentation (feature widgets) | Application (Riverpod callback plumbing) | `row.id` already exists in the read model; this is UI wiring, not new data |
| Status-based "View workout" routing | Presentation (navigation decision in `DayDetailSheet`) | Application (`ScheduledWorkoutService`) | Route target depends on `schedule.status`/`completedSessionId`, already resolved by the application-layer service |
| Planned workout preview rendering | Presentation (new `PlannedWorkoutPreviewView`) | Application (new provider wrapping `previewScheduledWorkout`) | UI never touches drift directly (CLAUDE.md) — the view resolves data via a Riverpod provider, not direct queries |
| Read-only guarantee (no session created on preview) | Data (`ScheduledWorkoutService.previewScheduledWorkout`) | — | Already implemented and reused, not re-derived |

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLOW-01 | `KeyboardObstructionScope` manages keyboard visibility, animations, and hit-testing across shell and active workout screens | Verified exact current implementation in `main_scaffold.dart:283-320`ish and `active_workout_view.dart:373-410`ish; confirmed structural shape the extraction must preserve for `test/widgets/active_workout_keyboard_test.dart` to keep passing |
| FLOW-02 | `PlannedWorkoutPreviewView` renders full workout preview with exercise details without writing to the database | Verified `ScheduledWorkoutService.previewScheduledWorkout` (read-only, no session materialization) and the existing `_WorkoutPlanPreviewSheet` rendering logic to lift into the new route |
| FLOW-03 | Calendar entries correctly route to Preview & Start, Resume active session, or History detail based on status | Verified `ScheduleStatus`, `ScheduledWorkoutRow`, `completedSessionId` FK, and **both** existing call sites (`month_calendar.dart` and `week_board.dart` via `training_blocks_view.dart`) that need `initialScheduleId`/routing fixes |
</phase_requirements>

## Standard Stack

This phase adds no new dependencies — it is a refactor/wiring phase using only libraries already in `pubspec.yaml`.

| Library | Version (installed) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter_riverpod | per `pubspec.lock` (already used throughout) | State/provider plumbing for the new preview provider | Project standard; `StreamProvider`/`FutureProvider.autoDispose.family` patterns already established |
| go_router | `^14.6.2` [VERIFIED: pubspec.yaml] | New `plannedWorkoutPreview` route registration | Project standard, `AppRoutes`/`AppPaths` constants pattern already in place |
| drift | already in use | No schema change — `completedSessionId` column (v1.., unchanged) already exists | N/A — no new drift work this phase |

**No installation step required.** No `flutter pub add` / `npm install` equivalents — do not run the Package Legitimacy Gate for this phase; it introduces zero new third-party packages.

## Package Legitimacy Audit

**Not applicable.** This phase installs no external packages — it extracts/refactors existing widgets and adds one new internal route + provider using libraries already declared in `pubspec.yaml`. No `slopcheck`/registry verification needed.

## Architecture Patterns

### System Architecture Diagram

```
User taps a session (SessionTile in MonthCalendar's _SelectedDayList,
                      or WeekBoard's session row)
        │
        ▼
onOpenSession(row: ScheduledWorkoutRow)  ── carries row.id today, but it is
        │                                   discarded before this phase (BUG)
        ▼
TrainingBlocksView._openDay(context, ref, date, program, {initialScheduleId})
        │
        ▼
DayDetailSheet.show(context, date:, programId:, initialScheduleId:)
        │
        ├─ renders all of that day's sessions (unchanged)
        └─ scrolls/highlights the card matching initialScheduleId (new, D-05)
                │
                ▼
        Each _SessionCard's "View workout" button
                │
        switch (row.status)
                │
    ┌───────────┼─────────────────────┬───────────────────────┐
    ▼                                 ▼                        ▼
planned / moved                 in_progress                  done
    │                                 │                        │
    ▼                                 ▼                        ▼
Navigator.pop(sheet)          Navigator.pop(sheet)     Navigator.pop(sheet)
    │                                 │                        │
    ▼                                 ▼                        ▼
context.push(                 context.push(             context.push(
  AppPaths.plannedWorkout       AppPaths.workoutHistory(   AppPaths.workoutHistory(
    Preview(row.id))               schedule.completedSessionId!))  schedule.completedSessionId!))
    │                                 │                        │
    ▼                                 ▼                        ▼
PlannedWorkoutPreviewView      WorkoutHistoryView          WorkoutHistoryView
  (new route, resolves via       (existing route,            (existing route,
   new provider wrapping          sessionId: live/           sessionId: final
   previewScheduledWorkout)        partial session)            session)
    │
    ▼
"Start workout" CTA (planned/moved only)
    │
    ▼
startScheduledWorkoutById(row.id)  →  switches to Workouts tab (index 2)
```

### Recommended Project Structure

No new folders. New files land in existing feature directories, following established placement:

```
lib/
├── design_system/components/
│   └── keyboard_obstruction_scope.dart   # NEW — FLOW-01, shell primitive beside hx_sheet.dart
├── features/workouts/
│   ├── application/workouts_providers.dart      # ADD: plannedWorkoutPreviewProvider (or similar)
│   └── presentation/views/
│       └── planned_workout_preview_view.dart     # NEW — FLOW-02, sibling of workout_history_view.dart
├── features/programs/
│   ├── domain/scheduled_workout_row.dart          # ADD: completedSessionId getter (Claude's discretion detail)
│   └── presentation/
│       ├── sheets/day_detail_sheet.dart           # MODIFY: _viewWorkout routing, initialScheduleId param, extract _WorkoutPlanPreviewSheet body
│       ├── widgets/month_calendar.dart            # MODIFY: thread row.id through _SelectedDayList.onOpenSession
│       └── views/training_blocks_view.dart        # MODIFY: _openDay gains initialScheduleId; both MonthCalendar and WeekBoard callers wire it
├── app/router/
│   ├── routes.dart                                 # ADD: AppRoutes.plannedWorkoutPreview, AppPaths.plannedWorkoutPreview(id)
│   └── router.dart                                 # ADD: GoRoute registration mirroring workoutHistory's _intParam/_badParam pattern
```

### Pattern 1: Shell primitive wrapping a focus/visibility signal

**What:** `KeyboardObstructionScope` wraps a child in the same `AnimatedPositioned(bottom) → ExcludeSemantics → IgnorePointer → AnimatedOpacity` stack both current consumers hand-roll, parameterized by the hidden-offset value (-120 for nav bar, -140 for action bar) and the boolean "should hide" signal.

**When to use:** Any bottom-anchored control that must clear the keyboard/focused-input area.

**Example (current hand-rolled shape to replicate exactly — source: `main_scaffold.dart:283-303`):**
```dart
AnimatedPositioned(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOutCubic,
  left: 0,
  right: 0,
  bottom: hideWorkoutChrome ? -120 : 0,
  child: ExcludeSemantics(
    excluding: hideWorkoutChrome,
    child: IgnorePointer(
      ignoring: hideWorkoutChrome,
      child: AnimatedOpacity(
        duration: hideWorkoutChrome
            ? Duration.zero
            : const Duration(milliseconds: 150),
        opacity: hideWorkoutChrome ? 0 : 1,
        child: /* HxNavBar or floating action row */,
      ),
    ),
  ),
),
```
`active_workout_view.dart:373-410` is the same shape with `-140`/`keyboardOpen`. `KeyboardObstructionScope` should accept `{required bool hidden, required double hiddenOffset, required Widget child}` (naming at planner's/Claude's discretion) and reproduce this exact tree — including widget **types and order** (`AnimatedPositioned` → `ExcludeSemantics` → `IgnorePointer` → `AnimatedOpacity`), because `test/widgets/active_workout_keyboard_test.dart` locates them via `find.ancestor(of: ..., matching: find.byType(AnimatedPositioned))` / `find.byType(IgnorePointer)`.

### Pattern 2: Parameterized route resolving its own data (no `extra` payload)

**What:** `PlannedWorkoutPreviewView({required int scheduleId})` registered as a `GoRoute` with a `:id` path segment, matching `WorkoutHistoryView`'s exact shape.

**Example (source: `router.dart:122-129`, to replicate for the new route):**
```dart
GoRoute(
  path: AppRoutes.workoutHistory,
  builder: (context, state) {
    final id = _intParam(state, 'id');
    if (id == null) return _badParam(context, state, 'id');
    return WorkoutHistoryView(sessionId: id);
  },
),
```
And in `routes.dart`:
```dart
static const workoutHistory = '/workout-history/:id';
static String workoutHistory(int id) => '/workout-history/$id';
```
`plannedWorkoutPreview` should mirror both the `AppRoutes` constant and `AppPaths` builder, plus a `GoRoute` entry using the same `_intParam`/`_badParam` helpers already defined in `router.dart`.

### Pattern 3: Data-resolving provider for a route-pushed detail view

**What:** A `FutureProvider.autoDispose.family<T, int>` that a standalone view watches by id, rather than pre-fetching and passing via `extra`.

**Example precedent (source: `workouts_providers.dart:144`):**
```dart
final sessionSummaryProvider = FutureProvider.autoDispose
    .family<WorkoutSessionSummary, int>((ref, sessionId) async {
  final session = await ref.watch(workoutSessionProvider(sessionId).future);
  // ...
});
```
`PlannedWorkoutPreviewView`'s new provider should follow this exact shape: `FutureProvider.autoDispose.family<PlannedSessionSnapshot?, int>` (or a small wrapper record combining the snapshot + resolved exercise catalog map), wrapping `ScheduledWorkoutService.previewScheduledWorkout(scheduleId)` the same way `DayDetailSheet._viewWorkout` currently does inline (`day_detail_sheet.dart:428-453`).

### Anti-Patterns to Avoid

- **Threading `plan`/`exercises` through `context.push(..., extra: ...)`:** D-10 explicitly rejects this — it breaks deep-link/back-stack restoration (a restored route has no `extra`). Resolve everything from `scheduleId` via a provider instead.
- **Collapsing `DayDetailSheet` to single-session rendering when `initialScheduleId` is set:** D-05 is explicit that the sheet still lists every session for that day; `initialScheduleId` only affects scroll/highlight, never the list contents.
- **Re-deriving the animation timing from scratch:** the -120/-140 offsets and the asymmetric instant-hide/150ms-restore opacity durations are exact values already tuned and covered by tests — copy them, don't redesign them (D-02).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Resolving a scheduled workout's planned content | A new query/resolver in the view | `ScheduledWorkoutService.previewScheduledWorkout` | Already read-only, already handles template-override vs. inline-exercise resolution (`planned_session_resolver.dart`) |
| Starting/resuming a scheduled workout | New transaction logic in `PlannedWorkoutPreviewView` | `ScheduledWorkoutService.startScheduledWorkoutById` | Already idempotent (returns existing open session id on Resume), already transaction-wrapped, already throws the right `StateError`s |
| Determining if a schedule row has a linked session | A new "started" flag / boolean column | `schedule.completedSessionId != null` (already how `TodaysScheduledWorkout.isStarted` works) | Single source of truth already exists; no schema change needed |
| Route param parsing/validation | Ad hoc `int.tryParse` per route | Existing `_intParam`/`_badParam` helpers in `router.dart` | Already used by every other parameterized route (`workoutHistory`, `exercise`, `measurementDetail`, etc.) |

**Key insight:** every "don't hand-roll" item here isn't a generic ecosystem library — it's project-internal, already-written code this phase must call, not reimplement. The whole phase is wiring, not building.

## Common Pitfalls

### Pitfall 1: `AnimatedPositioned`/`IgnorePointer` ancestor-order regression breaks Phase 15's test
**What goes wrong:** Extracting `KeyboardObstructionScope` changes the widget subtree shape (e.g. wraps everything in an extra `Builder` or reorders `IgnorePointer`/`ExcludeSemantics`), and `find.ancestor(of: find.byType(HxNavBar), matching: find.byType(AnimatedPositioned))` in `test/widgets/active_workout_keyboard_test.dart` stops matching or matches the wrong widget.
**Why it happens:** The test asserts on *implementation-shape* (`.bottom`, `.ignoring`, `.opacity` on the concrete Flutter widget types), not on a black-box behavior contract, because no such contract existed pre-extraction.
**How to avoid:** Keep the exact tree: `AnimatedPositioned → ExcludeSemantics → IgnorePointer → AnimatedOpacity → child`. Verify the test passes with only import-path changes (swapping direct nav-bar/action-bar construction for `KeyboardObstructionScope(...)`), not assertion changes.
**Warning signs:** `flutter test` reports "found 0 widgets" for the `find.ancestor` calls, or `hiddenNavPos.bottom` reads `0` instead of `-120` (extraction defaulted the offset param wrong).

### Pitfall 2: `context.push` in a widget test with no `GoRouter` ancestor
**What goes wrong:** `DayDetailSheet._viewWorkout`/`_start`'s new done/in-progress branches call `context.push(AppPaths.workoutHistory(...))` or `context.push(AppPaths.plannedWorkoutPreview(...))`. Existing tests (`day_detail_sheet_test.dart`) pump `MaterialApp(home: Scaffold(body: DayDetailSheet(...)))` — no `GoRouter` in the tree. `go_router`'s `context.push` throws (`GoRouter not found in context` / a null-check on `GoRouter.maybeOf`) at runtime.
**Why it happens:** This is the **first** phase to add `context.push` calls inside a widget that's currently only tested in a bare `MaterialApp`. No prior test in `test/` exercises `go_router` push navigation at all (verified via grep — zero matches for `GoRouter`/`MaterialApp.router`/`context.push` under `test/`).
**How to avoid:** Build a minimal `GoRouter`-backed test harness (e.g. `MaterialApp.router(routerConfig: GoRouter(routes: [...minimal stub routes for the pushed paths...]))`) for the rewritten "View workout" tests, or inject a fake navigation callback instead of exercising real `go_router` (verify with whatever the planner decides is proportionate — this is a real new cost, not a trivial assertion edit).
**Warning signs:** `flutter test` throwing during the "View workout" tests with a `GoRouter`-related exception rather than a normal assertion failure.

### Pitfall 3: `WeekBoard`'s `onOpenSession` is a second, un-named instance of the FLOW-03 bug
**What goes wrong:** Planner scopes the `initialScheduleId` fix only to `month_calendar.dart`'s `_SelectedDayList.SessionTile.onTap` (as CONTEXT.md's D-04 literally describes), missing that `week_board.dart` already calls `onOpenSession(ScheduledWorkoutRow)` with the row available, and `training_blocks_view.dart:55-56`'s `onOpenSession: (row) => _openDay(context, ref, row.date, program)` discards `row.id` identically.
**Why it happens:** D-04's canonical refs cite only `month_calendar.dart`; `week_board.dart`/`training_blocks_view.dart`'s week-view path wasn't in the discussed file list even though it shares the exact same callback signature and bug shape.
**How to avoid:** When widening `_openDay`'s signature to accept `int? initialScheduleId`, update **both** call sites in `training_blocks_view.dart` (`MonthCalendar.onSelect` and `WeekBoard.onOpenSession`), not just the one CONTEXT.md named.
**Warning signs:** Week-view mode (`blocksViewModeProvider == BlocksViewMode.week`) still opens `DayDetailSheet` without highlighting the tapped session, while month-view mode works correctly.

### Pitfall 4: `ScheduledWorkoutRow` has no `completedSessionId` getter today
**What goes wrong:** Code written against `row.completedSessionId` fails to compile — the getter doesn't exist.
**Why it happens:** `ScheduledWorkoutRow` (`scheduled_workout_row.dart:31-91`) exposes `id`, `status`, `isDone`, `isInProgress`, etc., all derived from `schedule`, but never re-exposes `schedule.completedSessionId` directly.
**How to avoid:** Either add `int? get completedSessionId => schedule.completedSessionId;` to `ScheduledWorkoutRow`, or read `row.schedule.completedSessionId` directly at the two call sites (`_viewWorkout`'s done/in-progress branches). Adding the getter is more consistent with the class's existing pattern of never exposing `schedule` fields raw.
**Warning signs:** Dart analyzer error "The getter 'completedSessionId' isn't defined for the type 'ScheduledWorkoutRow'."

## Code Examples

### Status-gated "View workout" routing (D-06/D-07/D-08 combined)

```dart
// Source pattern: existing _start (day_detail_sheet.dart:410-424) shows the
// pop-then-navigate sequencing to reuse; _viewWorkout (428-453) is the method
// this logic replaces.
Future<void> _viewWorkout(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context);
  if (row.isDone || row.isInProgress) {
    final completedSessionId = row.schedule.completedSessionId; // or row.completedSessionId if a getter is added
    if (completedSessionId == null) {
      // Defensive: status says started/done but the link is missing.
      // Fall through to snackbar error, same shape as the existing null-plan guard.
      return;
    }
    navigator.pop();
    if (!context.mounted) return;
    context.push(AppPaths.workoutHistory(completedSessionId));
    return;
  }
  // planned / moved / skipped — unchanged preview path
  navigator.pop();
  if (!context.mounted) return;
  context.push(AppPaths.plannedWorkoutPreview(row.id));
}
```

### Existing read-only preview call (unchanged, now consumed by a provider instead of inline)

```dart
// Source: day_detail_sheet.dart:428-453 — the logic to lift into a
// FutureProvider.autoDispose.family<..., int> that PlannedWorkoutPreviewView watches.
final plan = await ref
    .read(scheduledWorkoutServiceProvider)
    .previewScheduledWorkout(scheduleId);
if (plan == null) {
  // "This scheduled workout no longer exists." — same message, now shown as
  // the view's empty/error state rather than a SnackBar.
}
final catalog = await ref.read(appDatabaseProvider).select(
  ref.read(appDatabaseProvider).exerciseCatalog,
).get();
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `workoutInputFocusedProvider` bool consumed independently by `MainScaffold` and `ActiveWorkoutView` with duplicated hide logic | Single `KeyboardObstructionScope` shell primitive both consume | This phase (FLOW-01) | One place to fix future keyboard-obstruction bugs; existing Phase 15 test suite is the regression guard |
| `DayDetailSheet.show(date:, programId:)` only, whole-day granularity | `DayDetailSheet.show(date:, programId:, initialScheduleId:)`, scrolls to/highlights a specific occurrence | This phase (FLOW-03) | Resolves ambiguity when a day has 2+ sessions |
| `_viewWorkout` always shows the planned preview regardless of status | Routes to `WorkoutHistoryView` for done/in-progress, `PlannedWorkoutPreviewView` for planned/moved | This phase (FLOW-03) | Fixes a real bug — completed days no longer show stale plan data instead of what was actually logged |
| `_WorkoutPlanPreviewSheet` private class nested in `day_detail_sheet.dart`, opened as a sheet-on-sheet | `PlannedWorkoutPreviewView` standalone pushed route | This phase (FLOW-02) | Gets a real back-stack entry, matches `WorkoutHistoryView`'s pattern, supports a `Start workout` CTA |

**Deprecated/outdated:**
- `_WorkoutPlanPreviewSheet` (private class in `day_detail_sheet.dart:547-658`): body content (exercise cards, `formatPlannedExerciseSets`) is reused, but the `HxSheet`-nested-in-sheet shell is retired in favor of a full route. `formatPlannedExerciseSets` is `@visibleForTesting` and public — check whether any existing unit test imports it directly from `day_detail_sheet.dart`; if so, moving it to the new view file needs an import-path update in that test.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Exact prop names for `KeyboardObstructionScope` (e.g. `hidden`, `hiddenOffset`) are illustrative, not prescribed — CONTEXT.md leaves the API name to Claude's discretion | Architecture Patterns, Pattern 1 | Low — naming only, no behavioral risk |
| A2 | `PlannedWorkoutPreviewView` and its provider belong in `features/workouts/` (mirroring `WorkoutHistoryView`'s location) rather than `features/programs/` | Recommended Project Structure | Low-medium — if placed in `programs/`, works functionally but breaks the "mirror `WorkoutHistoryView`" precedent D-09 calls for; also `ScheduledWorkoutService` already lives in `features/workouts/data/`, reinforcing the `workouts/` placement |
| A3 | A full `GoRouter` test harness (vs. a lighter navigation-stub approach) is the right fix for Pitfall 2 — this is a judgment call, not verified against a specific `go_router` testing doc | Common Pitfalls, Pitfall 2 | Medium — wrong harness choice costs rework time, but does not affect production behavior |

## Open Questions

1. **(RESOLVED)** ~~Should `formatPlannedExerciseSets` move with the preview body, and does any test import it directly?~~
   - What we know: it's `@visibleForTesting` and public specifically so it can be unit-tested; it currently lives in `day_detail_sheet.dart`.
   - Resolution: Plan 20-03 Task 3 greps `test/` for `formatPlannedExerciseSets` before moving the function and updates the import if found.

2. **(RESOLVED)** ~~What should `PlannedWorkoutPreviewView` show for a `skipped` row navigated to directly (e.g. via a future deep link), given its CTA is Start-only for planned/moved?~~
   - What we know: D-11/discretion notes say `skipped` rows' "View workout" still targets `PlannedWorkoutPreviewView` (unchanged), and the CTA should show for planned/moved rows.
   - Resolution: Plans gate the Start CTA to `planned`/`moved` rows only, hiding it for `skipped` — matches `ScheduleStatus.isOpen` (which excludes `skipped`), consistent with `_SessionCard`'s existing gate (`if (ScheduleStatus.isOpen(row.status) && !row.isEmpty)`).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (bundled), `package:test` for pure-Dart unit tests |
| Config file | none — standard `flutter test` / `dart test` discovery of `test/**_test.dart` |
| Quick run command | `flutter test test/widgets/active_workout_keyboard_test.dart test/widgets/day_detail_sheet_test.dart` |
| Full suite command | `flutter test > /tmp/test_output.txt 2>&1; tr '\r' '\n' < /tmp/test_output.txt \| tail -50` (per CLAUDE.md — never pipe directly to `tail`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|--------------------|-------------|
| FLOW-01 | `KeyboardObstructionScope` hides/ignores/excludes-semantics nav bar + action bar in sync | widget | `flutter test test/widgets/active_workout_keyboard_test.dart` | ✅ (extend in place, assertions should still pass post-extraction) |
| FLOW-02 | `PlannedWorkoutPreviewView` renders plan without writing to DB | widget | `flutter test test/widgets/planned_workout_preview_view_test.dart` | ❌ Wave 0 — new file |
| FLOW-03 (calendar occurrence) | Tapping a specific session opens `DayDetailSheet` scrolled/highlighted to that row | widget | `flutter test test/widgets/month_calendar_test.dart` (or extend `day_detail_sheet_test.dart`) | ❌ Wave 0 — no existing `month_calendar` widget test found |
| FLOW-03 (status routing) | done/in-progress → `WorkoutHistoryView(sessionId: completedSessionId)`; planned/moved → `PlannedWorkoutPreviewView` | widget | `flutter test test/widgets/day_detail_sheet_test.dart` | ✅ but the existing "View workout" test needs rewriting for the new routing + `GoRouter` harness (see Pitfall 2) |

### Sampling Rate
- **Per task commit:** targeted `flutter test test/widgets/<changed>_test.dart`
- **Per wave merge:** `flutter test` full suite (per CLAUDE.md, ~2min, 1308 pass / 4 skipped baseline — expect this count to shift once new tests land)
- **Phase gate:** full suite green, `flutter analyze` at 0 errors, before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/widgets/planned_workout_preview_view_test.dart` — covers FLOW-02, including the "no session created on render" assertion (mirror `day_detail_sheet_test.dart`'s existing `fakeService.startCalls == 0` pattern)
- [ ] A minimal `GoRouter` test harness (helper in `test/support/` or inline per-test) — needed by both the FLOW-02 view test and the rewritten FLOW-03 status-routing tests in `day_detail_sheet_test.dart`
- [ ] `month_calendar.dart` currently has **no** dedicated widget test — if the planner wants automated coverage of `_SelectedDayList`'s `onOpenSession(row.id)` wiring specifically (as opposed to only testing the downstream `DayDetailSheet` behavior), a new `test/widgets/month_calendar_test.dart` is needed
- [ ] No framework install needed — `flutter_test` already configured

## Security Domain

This phase is local-only UI/navigation wiring with no new network, auth, or persisted-data surface (no schema change, no new external package). ASVS categories are largely not applicable; documented for completeness per the "security_enforcement absent = enabled" default.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | Single-local-user app, no auth boundary touched by this phase |
| V3 Session Management | No | N/A — "session" here means `WorkoutSessionData`, not an auth session |
| V4 Access Control | No | No multi-user/permission boundary in this app |
| V5 Input Validation | Yes | Route `:id` params validated via existing `_intParam`/`_badParam` helpers (`router.dart`) — reuse, don't bypass, for the new `plannedWorkoutPreview` route |
| V6 Cryptography | No | N/A |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|-----------------------|
| Malformed/negative/non-numeric route id (`/planned-workout-preview/abc`) crashing the app | Denial of Service (local) | `_intParam` returning `null` → `_badParam` error screen, same as every existing parameterized route |
| Stale `scheduleId` (row deleted between calendar list load and tap) reaching the preview route | Tampering (data integrity, not security-adversarial) | `previewScheduledWorkout` already returns `null` for a missing schedule — `PlannedWorkoutPreviewView` must render an empty/error state, not throw, exactly as `_viewWorkout`'s current null-guard does (`day_detail_sheet.dart:433-439`) |

## Sources

### Primary (HIGH confidence — direct codebase inspection)
- `lib/features/shell/main_scaffold.dart` (lines ~180-330) — nav bar keyboard-obstruction implementation
- `lib/features/workouts/presentation/views/active_workout_view.dart` (lines ~100-420) — action bar keyboard-obstruction implementation
- `test/widgets/active_workout_keyboard_test.dart` — full file read, confirms exact widget-tree assertions extraction must preserve
- `lib/features/programs/presentation/widgets/month_calendar.dart` — full file read, confirms `_SelectedDayList.SessionTile.onTap` bug and current structure
- `lib/features/programs/presentation/widgets/week_board.dart` — confirms `onOpenSession(ScheduledWorkoutRow)` signature (the second, previously un-named instance of the same bug)
- `lib/features/programs/presentation/views/training_blocks_view.dart` (lines 1-84) — confirms both `MonthCalendar` and `WeekBoard` route through the same `_openDay`
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart` — full file read, confirms `_start`/`_viewWorkout`/`_WorkoutPlanPreviewSheet` exact current shape
- `lib/features/programs/domain/scheduled_workout_row.dart` — full file read, confirms no `completedSessionId` getter exists yet
- `lib/features/programs/domain/schedule_status.dart` — full file read, confirms status vocabulary and `isOpen`
- `lib/features/workouts/data/scheduled_workout_service.dart` (lines 1-210) — confirms `previewScheduledWorkout`/`startScheduledWorkoutById` exact behavior, including the "already completed" `StateError` guard
- `lib/data/local/tables.dart` (lines 1057-1078) — confirms `completedSessionId` FK definition (nullable, `onDelete: setNull`, references `WorkoutSessions`)
- `lib/features/workouts/presentation/views/workout_history_view.dart` (lines 1-60) — confirms the route/constructor pattern to mirror
- `lib/app/router/router.dart` (lines 100-145) and `lib/app/router/routes.dart` (full file) — confirms `AppRoutes`/`AppPaths`/`GoRoute` registration pattern
- `lib/design_system/components/hx_sheet.dart` — full file read, confirms shell-primitive style precedent
- `test/widgets/day_detail_sheet_test.dart` — full file read, confirms existing test coverage and its incompatibility with the upcoming `context.push`-based routing
- `test/scheduled_workout_service_test.dart` (partial) — confirms existing service-level test patterns
- `pubspec.yaml` / `pubspec.lock` — confirms `go_router: ^14.6.2` [VERIFIED: pubspec.yaml]
- `.planning/config.json` — confirms `nyquist_validation: true`, no `security_enforcement` key (defaults enabled)
- `.planning/phases/20-.../20-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/ROADMAP.md` — phase scope and requirement traceability

### Secondary (MEDIUM confidence)
- None — all findings in this research were verified directly against the current codebase; no WebSearch was needed since this phase's scope is entirely internal wiring, not new library adoption.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; existing versions confirmed via `pubspec.yaml`/`pubspec.lock`
- Architecture: HIGH — every pattern verified by reading the actual source files, not inferred from CONTEXT.md descriptions alone
- Pitfalls: HIGH — the `go_router` test-gap and the `WeekBoard` second-instance findings are both confirmed via direct grep/read, not speculation

**Research date:** 2026-09-16
**Valid until:** Until Phase 20 code lands (this is an internal-refactor phase on a single branch; line numbers will drift as soon as any of D-01–D-11's target files are edited — re-verify exact line numbers at plan/execute time rather than trusting this document's line citations after the first task lands)
