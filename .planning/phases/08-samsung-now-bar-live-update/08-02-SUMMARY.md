---
phase: "08"
plan: "08-02"
subsystem: workout-notifications
tags: [now-bar, live-update, notifications, channels, lock-screen, flutter, kotlin]
requires:
  - 08-01 promotable Live Update renderer
  - OngoingWorkoutSurfaceBridge.getCapabilities
provides:
  - Single publisher for notification id 1 per device tier
  - workout_rest high-importance channel for the rest timer
  - requiresUnlock enforcement in the native action receiver
  - Native surface teardown on widget dispose
affects:
  - lib/services/workout_notification_service.dart
  - lib/app/app.dart
  - android/app/src/main/kotlin/com/ams/herculex/nowbar/
  - docs/now-bar-native-adapter-contract.md
  - docs/now-bar-workout-proposal.md
tech-stack:
  patterns:
    - Capability-gated publisher selection, cached once per process
    - Snapshot equality ignoring the ticking elapsed label
key-files:
  created: []
  modified:
    - lib/services/workout_notification_service.dart
    - lib/app/app.dart
    - lib/features/workouts/presentation/workout_settings_sheet.dart
    - android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceAdapter.kt
    - android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutActionReceiver.kt
    - android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceSnapshot.kt
    - android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceStateStore.kt
    - docs/now-bar-native-adapter-contract.md
    - docs/now-bar-workout-proposal.md
key-decisions:
  - Rest channel uses Importance.high (IMPORTANCE_HIGH), not the deprecated max
  - requiresUnlock is persisted in the surface state store, because the receiver
    is a cold-start BroadcastReceiver with no in-memory snapshot
  - The unchanged-snapshot check compares whole snapshots with elapsedLabel blanked,
    rather than enumerating fields
requirements-completed:
  - NOWBAR-02
  - NOWBAR-03
duration: 34 min
completed: 2026-08-04
---

# Phase 08 Plan 02: Single-Publisher Ongoing Workout Surface Summary

Made the native renderer the sole owner of the ongoing workout notification on Android 16+,
so the promotable Live Update from 08-01 survives instead of being overwritten roughly once
per second, and closed the rest-timer, teardown and lock-screen-policy gaps around it.

**Tasks:** 8 | **Files modified:** 9 | **Commits:** 1 (`eff400a`)

## What Was Built

**Publisher split.** `WorkoutNotificationService` gained a cached
`_nativeOwnsOngoingSurfaceNotification()` backed by
`OngoingWorkoutSurfaceBridge.getCapabilities().android16Plus`. When true,
`showOrUpdate` skips its own `_post()` entirely — both on the initial call and on every
tick — while still invoking `afterPost`, so the native surface is published and the Flutter
plugin never writes id 1. Below API 36 (and on iOS, and whenever the platform channel is
unavailable — `getCapabilities` degrades to false) the `flutter_local_notifications` path
is unchanged and remains the only publisher. The capability is read once and cached because
it cannot change at runtime and the ticker would otherwise cross the platform channel every
tick.

**Repost rate.** The `Timer.periodic` in `showOrUpdate` went from 1 s to 5 s. Elapsed time
is drawn by the notification chronometer (`when` + `usesChronometer`), so 1 Hz reposting
bought nothing and Android rate-limits it.

**Adapter deduplication.** `OngoingWorkoutSurfaceAdapter.update` compares the incoming
snapshot against the cached one with `elapsedLabel` blanked (new
`OngoingWorkoutSurfaceSnapshot.withoutElapsedLabel()`), and skips `renderer.show()` when
they match, logging `event=updateSkipped reason=unchanged`. `stateStore.recordSurface` still
runs on every update, and the action `PendingIntent`s are rebuilt only when `sessionId` or
`targetSetId` changed.

**Rest timer channel.** New `_restChannelId = 'workout_rest'` with
`Importance.high`/`Priority.high` and its own description. It previously requested
`Importance.max` on `workout_live`, which the system had created at `IMPORTANCE_LOW` — and
channel importance is fixed at creation, so the alert was silently downgraded and never
made a sound.

**Teardown.** `dispose()` in `lib/app/app.dart` now calls
`OngoingWorkoutSurfaceBridge.instance.clear()` alongside the existing notification cancel
and drain-timer cancel, so the native surface cannot outlive the widget.

**Lock-screen policy.** `OngoingWorkoutSurfaceSnapshot.requiresUnlock(actionId)` resolves
the flag from either `privacy.requiresUnlock` or the action's own `requiresUnlock`. The
resolved id set is persisted by `OngoingWorkoutSurfaceStateStore.recordSurface` (and
surfaced on `OngoingWorkoutSurfaceDisplayState.requiresUnlockActionIds`), because
`OngoingWorkoutActionReceiver` is a cold-start `BroadcastReceiver` with no in-memory
snapshot to consult. The receiver checks the flag after its existing stale-session and
stale-set gates: a flagged action records a `requires_unlock` rejection, launches
`MainActivity` through the existing open-workout intent instead of queueing, and logs
`event=rejected reason=requires_unlock`. No action is flagged today, so the five current
low-risk ids are unaffected.

**Diagnostics.** The settings sheet now shows `Rejected Action` (the id) and
`Rejected Reason` directly beneath the existing `Rejected Native` count; the old
`Last Rejected` row, which duplicated the reason at the bottom of the list, was removed.

**Docs.** `now-bar-native-adapter-contract.md` no longer claims the
`flutter_local_notifications` ongoing path is always kept; it now states the actual
single-publisher-per-tier rule and notes the feedback notification's separate id.
`now-bar-workout-proposal.md` replaces "reflectively requests promoted ongoing behavior"
with the real `setRequestPromotedOngoing` / `ProgressStyle` / `setShortCriticalText`
description, and the Samsung checklist now expects `style=ProgressStyle`, a non-empty
`shortCriticalText`, `event=updateSkipped reason=unchanged` between posts, and the two new
diagnostics rows.

## Deviations from Plan

**[Rule 2 - missing prerequisite] `requiresUnlock` was not persisted anywhere**
Found during: Task 6.
Issue: the plan says to "read the flag for the incoming action from the persisted surface
state", but `OngoingWorkoutSurfaceStateStore` never persisted it — the parsed
`privacy.requiresUnlock` and `SurfaceAction.requiresUnlock` values were discarded at parse
time, exactly as the phase CONTEXT noted.
Fix: added a `requires_unlock_action_ids` string set to the store (written in
`recordSurface`, cleared in `clearSurface`, exposed on `OngoingWorkoutSurfaceDisplayState`)
plus a `requiresUnlock(actionId)` resolver on the snapshot. `OngoingWorkoutSurfaceSnapshot.kt`
and `OngoingWorkoutSurfaceStateStore.kt` are therefore touched beyond the plan's
`files_modified` list.
Verification: `:app:compileDebugKotlin` — BUILD SUCCESSFUL; the snapshot parse contract and
native action contract tests still pass.
Commit: `eff400a`.

**[Rule 1 - minor] Rest channel uses `Importance.high`, not `max`**
`Importance.max` maps to the deprecated `IMPORTANCE_MAX`. `IMPORTANCE_HIGH` is the correct
level for a heads-up alert with sound and is what the plan's intent ("high-importance
channel") calls for.

**Total deviations:** 2 auto-fixed (1× Rule 2, 1× Rule 1). **Impact:** no change to the
plan's success criteria; the unlock guard needed a storage field the plan assumed already
existed.

## Verification Results

| Check | Result |
|-------|--------|
| `flutter analyze` on the three changed Dart files | PASS — no issues |
| `flutter test` (6 files: bridge, snapshot, native action contract, command, action queue, service payload) | PASS — 29/29 |
| `.\gradlew.bat :app:compileDebugKotlin` (JBR JAVA_HOME) | PASS — BUILD SUCCESSFUL |

Not verifiable here — all require a Samsung Android 16 device:

- counting `event=posted` over 30 idle seconds (expect ~1, not ~30)
- the rest timer alerting audibly on `workout_rest`
- backgrounding / ending a workout / disposing leaving no notification behind
- a `+ Rep` tap still incrementing the active set, and a delayed tap from a previous target
  set still emitting `event=rejected`

These are the plan's headline runtime criteria and must be checked during UAT.

## Issues Encountered

Same pre-existing condition flagged in 08-01: much of the surrounding Now Bar work (the
Dart surface layer, several native files, and the tests) is still untracked in the working
tree, so `HEAD` does not build on its own. Not introduced by this phase; worth resolving
before shipping.

## Next Phase Readiness

Phase 08 code complete. Both requirements' measurable outcomes (`promotable=true`, and one
`event=posted` per snapshot change) are device-observable only — run
`/gsd:verify-work 8` against a Samsung Android 16 handset before marking the phase verified.
