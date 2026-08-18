---
phase: 11-gym-buddy-live-workout
plan: 02
subsystem: domain
tags: [dart, drift, supabase-realtime, structural-gate, tdd]

# Dependency graph
requires: []
provides:
  - "lib/features/buddy/domain/buddy_event.dart — BuddyEventKind, BuddyExerciseRef, BuddyEvent, and the five payload codecs (the wire contract, no scope field)"
  - "lib/features/buddy/domain/buddy_scope.dart — BuddyScope, BuddyActionKind, BuddyScopeDefaults, deliberately outside the transport module"
  - "lib/features/buddy/data/buddy_event_publisher.dart — abstract BuddyEventPublisher seam, no scope parameter"
  - "test/buddy/fake_buddy_publisher.dart — recording FakeBuddyPublisher for every later buddy plan to drive"
  - "test/support/two_device.dart — reusable two-independent-Drift-database harness"
  - "test/buddy/rls_frozen_test.dart — BUD-05 frozen-RLS structural gate"
  - "test/buddy/buddy_scope_boundary_test.dart — BUD-03 scope-boundary structural gate"
affects: [11-03, 11-04, 11-05, 11-06, 11-07, 11-08]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Transport module = lib/features/buddy/data/ + the single file lib/features/buddy/domain/buddy_event.dart; scope stays out of it by construction and by a structural gate"
    - "Structural source-scan gate over a directory (comment-stripped, non-vacuity-guarded) — same shape as test/rep_tracker_write_boundary_test.dart, reused for BUD-03"
    - "Byte-level frozen-file pin via LF-normalised sha256 with existence+length guards before hashing — BUD-05"

key-files:
  created:
    - lib/features/buddy/domain/buddy_event.dart
    - lib/features/buddy/domain/buddy_scope.dart
    - lib/features/buddy/data/buddy_event_publisher.dart
    - test/buddy/buddy_event_test.dart
    - test/buddy/fake_buddy_publisher.dart
    - test/support/two_device.dart
    - test/buddy/rls_frozen_test.dart
    - test/buddy/buddy_scope_boundary_test.dart
    - .planning/phases/11-gym-buddy-live-workout/deferred-items.md
  modified: []

key-decisions:
  - "BuddyEvent.fromBroadcast defaults buddySessionId to '' when absent from the payload — a Supabase realtime broadcast is scoped to the session's own channel, so the channel context (not the payload) is expected to carry the session id; behavior tests only assert seq/kind/actor/payload per the plan's interface comment"
  - "package:crypto used transitively (already resolved in pubspec.lock, not added as a direct dependency) per the plan's explicit preference; flutter analyze reports one info-level depend_on_referenced_packages lint, zero errors"
  - "Comments in buddy_event.dart mentioning 'BuddyScope'/'mine' are safe per the plan's own gate design (comment-stripped before matching), but oldIndex/newIndex was avoided even in comments since that specific acceptance-criteria grep has no comment-stripping step"

patterns-established:
  - "Pattern: structural boundary gates live beside the code they constrain, are written before or alongside the guarded code, and are proven red on a deliberate violation before being trusted"

requirements-completed: [BUD-03, BUD-05]

# Metrics
duration: 25min
completed: 2026-08-18
---

# Phase 11 Plan 02: Buddy Wire Contract and Structural Gates Summary

**Pure-Dart buddy event wire contract (BuddyEventKind/BuddyExerciseRef/BuddyEvent + 5 payload codecs), a scope enum kept structurally outside the transport module, a publisher seam with recording fake, a reusable two-device test harness, and two structural gates (BUD-03 scope boundary, BUD-05 frozen RLS) each proven to fail on a deliberate violation.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-18T15:00:00+02:00 (approx.)
- **Completed:** 2026-08-18T15:14:00+02:00
- **Tasks:** 3
- **Files modified:** 8 created (plus 1 deferred-items log)

## Accomplishments

- The buddy wire contract exists as pure Dart with no drift/supabase/flutter imports, structurally incapable of carrying a scope field (enforced both by construction and by the BUD-03 gate written in the same plan).
- `BuddyScope`/`BuddyScopeDefaults` live in a sibling file that `buddy_event.dart` and everything under `lib/features/buddy/data/` never import.
- Every later buddy plan (11-06 through 11-08) has a `BuddyEventPublisher` seam to implement, a `FakeBuddyPublisher` to fake it in tests (with a `failWith` hook for 11-08's optimistic-rollback tests), and a `TwoDevices` harness so two-device tests never have to copy-paste the pattern from `test/sync/sync_payload_test.dart` again.
- Two of the phase's three non-negotiable gates (BUD-03, BUD-05) exist and were each observed red on an introduced violation, then green again after reverting — not just written and trusted.

## Task Commits

Each task was committed atomically:

1. **Task 1: Buddy wire contract and the scope enum, on opposite sides of the boundary** - `a8bcf62` (feat)
2. **Task 2: The publisher seam, the recording fake, and the two-device harness** - `f5c4498` (feat)
3. **Task 3: The two structural gates, each proven to fail on an introduced violation** - `8384972` (test)

**Plan metadata:** committed by the orchestrator after this worktree merges (STATE.md/ROADMAP.md are not touched here).

## Files Created/Modified

- `lib/features/buddy/domain/buddy_event.dart` (224 lines) - `BuddyEventKind` (with `wireName`/`fromWire`), `BuddyExerciseRef` (exactly-one-of `uuid`/`slug`, throws `ArgumentError` otherwise), `BuddyEvent` (`fromBroadcast`/`fromLogRow`), and the five payload classes (`BuddyAddPayload`, `BuddyRemovePayload`, `BuddyReorderPayload`, `BuddyReplacePayload`, `BuddySessionEndedPayload`)
- `lib/features/buddy/domain/buddy_scope.dart` (43 lines) - `BuddyScope`, `BuddyActionKind`, `BuddyScopeDefaults.forAction` (remove → mine, everything else → both)
- `lib/features/buddy/data/buddy_event_publisher.dart` (21 lines) - abstract `BuddyEventPublisher` seam, imports only `buddy_event.dart`
- `test/buddy/buddy_event_test.dart` (152 lines) - 15 tests covering every `<behavior>` bullet in the plan
- `test/buddy/fake_buddy_publisher.dart` (39 lines) - `FakeBuddyPublisher` recording `appends`/`appendCount` with a `failWith` throw hook
- `test/support/two_device.dart` (34 lines) - `TwoDevices`/`openTwoDevices()`, extracted from `test/sync/sync_payload_test.dart`'s idiom (that file itself is untouched — `git diff --stat` empty)
- `test/buddy/rls_frozen_test.dart` (49 lines) - BUD-05 gate
- `test/buddy/buddy_scope_boundary_test.dart` (141 lines) - BUD-03 gate
- `.planning/phases/11-gym-buddy-live-workout/deferred-items.md` (new) - logs an out-of-scope pre-existing test-suite issue found during the full regression run (see Issues Encountered)

## Decisions Made

- `BuddyEvent.fromBroadcast`'s `buddySessionId` defaults to `''` when the broadcast payload doesn't carry it, since the plan's interface comment scopes the factory to `seq/kind/actor/payload` only and a realtime broadcast is already scoped to its session's own channel.
- Kept `package:crypto` as a transitive dependency (already resolved via `pubspec.lock`) rather than adding it directly, per the plan's explicit preference — accepted the resulting single `depend_on_referenced_packages` info-level lint since the acceptance criteria only requires zero *errors*.

## Deviations from Plan

None — plan executed as written. One correction made during self-verification, not a deviation from the plan's intent: the plan's own acceptance criteria (`grep -c "oldIndex\|newIndex" lib/features/buddy/domain/buddy_event.dart` returns 0, with no comment-stripping step) is stricter than the note about comments being safe for the `BuddyScope`/`'mine'` check — a doc comment for `BuddyReorderPayload` originally used the words `oldIndex`/`newIndex` to explain what the full-order payload replaces, which would have failed that specific grep. Reworded to "a from/to index pair" before Task 1's commit; no logic changed.

## Gate Proof Log (Task 3, plan-mandated)

**BUD-05 (`rls_frozen_test.dart`):**
- Violation: appended a single newline to `supabase/migrations/0003_sync_rls.sql`.
- Observed failure:
  ```
  Expected: 'f50be2f89c775245e2700c2e532065c7d89ea240da0ef5ed77ff14bb25697530'
    Actual: 'f3650da4b9f98afb798bdc385fc0b37947d298ff9bc8bc8c6eb654520b302020'
  ```
- Reverted with `git checkout -- supabase/migrations/0003_sync_rls.sql`; `git status --porcelain supabase/migrations/0003_sync_rls.sql` confirmed empty; re-ran green.

**BUD-03 (`buddy_scope_boundary_test.dart`):**
- Violation: added `const _scopeProbe = 'mine';` to `lib/features/buddy/data/buddy_event_publisher.dart`.
- Observed failure:
  ```
  Expected: empty
    Actual: [lib/features/buddy/data\buddy_event_publisher.dart:3: contains a "mine" string literal]
  ```
- Removed the probe line; `git status --porcelain lib/features/buddy/data/buddy_event_publisher.dart` confirmed no leftover diff against the committed version; re-ran green.

## Issues Encountered

`flutter test` (full offline suite) surfaced 25 pre-existing failures, all sharing one root cause (`SqliteException(1): ... no such table: exercise_catalog`) in migration/schema fixture tests (`test/migration_test.dart`, `test/schema_v21_test.dart`, `test/schema_v24_test.dart`, and ~21 more) — none of which this plan's files touch or reference. Confirmed out of scope per the executor's scope-boundary rule and logged to `.planning/phases/11-gym-buddy-live-workout/deferred-items.md` rather than fixed. `flutter test test/buddy/` (18 tests) and `flutter analyze lib/features/buddy/ test/buddy/ test/support/` are both clean (the analyzer reports one info-level `depend_on_referenced_packages` lint, zero errors — see Decisions Made).

## User Setup Required

None - no external service configuration required. This plan is pure-Dart domain/test-seam code with no live Supabase connection.

## Next Phase Readiness

- 11-06/11-07/11-08 (and any other wave building the publisher, applier, or scope UI) have a stable `BuddyEventPublisher` interface, `FakeBuddyPublisher`, and `TwoDevices` harness to build against — the `<interfaces>` block in this plan is the contract, exactly as declared.
- BUD-03 and BUD-05 are enforced from this point forward; any future plan that violates either will fail `flutter test test/buddy/` immediately.
- BUD-06 (the remove gate) remains open, as planned — it ships with the applier in 11-07.
- The 25 pre-existing migration-fixture failures logged in `deferred-items.md` are worth a dedicated look before a phase that touches migrations, but do not block 11-02 or subsequent buddy-feature plans.

---
*Phase: 11-gym-buddy-live-workout*
*Completed: 2026-08-18*
