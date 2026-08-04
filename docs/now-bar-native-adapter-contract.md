# Now Bar Native Adapter Contract

Last updated: August 3, 2026

## Purpose

Herculex should treat Samsung Now Bar / Android Live Updates as an ongoing
workout surface adapter, not as a separate workout system.

The app already has a Flutter notification fallback for:

- Collapsed status: active exercise, current set, weight, reps, elapsed time.
- Expanded actions: reps up, load up, complete set, reps down, load down.
- Background queueing for non-UI notification actions.

When Samsung exposes a richer Now Bar developer API, or when the project targets
the Android API level required for full Live Updates support, the native adapter
should consume the same state and command contract.

## Adapter Boundary

The adapter should only know two things:

1. How to render the current workout surface.
2. Which command ID to send back when the user taps a control.

It should not decide workout progression, mutate set rows directly, or duplicate
exercise selection logic.

```text
Flutter/Riverpod active workout state
  -> active workout notification target selector
  -> ongoing workout surface snapshot
  -> Android notification / Samsung Now Bar adapter

Android/Samsung action
  -> shared action ID
  -> queue or foreground callback
  -> workout notification command helper
  -> WorkoutsRepository.updateSet
```

## Snapshot Shape

The native adapter should receive a compact snapshot like this. The Dart
`OngoingWorkoutSurfaceSnapshot.toJson()` method is tested against this shape.

```json
{
  "surfaceId": "active_workout",
  "category": "workout",
  "sessionId": 42,
  "targetSetId": 1001,
  "startedAtEpochMillis": 1785748991000,
  "collapsed": {
    "title": "Bench Press",
    "subtitle": "Set 3/5",
    "value": "82.5 kg x 8",
    "elapsedLabel": "24:16"
  },
  "expanded": {
    "title": "Bench Press",
    "rows": [
      {"id": "weight", "label": "Load", "value": "82.5 kg"},
      {"id": "reps", "label": "Reps", "value": "8"}
    ],
    "controls": [
      {
        "id": "weight",
        "type": "stepper",
        "label": "Load",
        "value": 82.5,
        "valueUnit": "kg",
        "displayValue": "82.5 kg",
        "minValue": 0.0,
        "maxValue": 9999.0,
        "step": 2.5,
        "stepLabel": "2.5 kg",
        "incrementActionId": "workout.weight.up",
        "decrementActionId": "workout.weight.down",
        "requiresUnlock": false,
        "risk": "low"
      },
      {
        "id": "reps",
        "type": "stepper",
        "label": "Reps",
        "value": 8,
        "valueUnit": "reps",
        "displayValue": "8",
        "minValue": 0,
        "maxValue": 999,
        "step": 1,
        "stepLabel": "1 rep",
        "incrementActionId": "workout.reps.up",
        "decrementActionId": "workout.reps.down",
        "requiresUnlock": false,
        "risk": "low"
      }
    ],
    "actions": [
      {"id": "workout.reps.up", "label": "+ Rep", "requiresUnlock": false, "risk": "low"},
      {"id": "workout.weight.up", "label": "+ 2.5 kg", "requiresUnlock": false, "risk": "low"},
      {"id": "workout.set.complete", "label": "Done", "requiresUnlock": false, "risk": "low"},
      {"id": "workout.reps.down", "label": "- Rep", "requiresUnlock": false, "risk": "low"},
      {"id": "workout.weight.down", "label": "- 2.5 kg", "requiresUnlock": false, "risk": "low"}
    ]
  },
  "privacy": {
    "lockScreenVisibility": "private",
    "requiresUnlock": [],
    "allowedWhileLocked": [
      "workout.reps.up",
      "workout.weight.up",
      "workout.set.complete",
      "workout.reps.down",
      "workout.weight.down"
    ]
  }
}
```

## Shared Action IDs

These IDs are already used by the Flutter notification fallback and should be
reused by any native Now Bar adapter:

- `workout.reps.up`
- `workout.weight.up`
- `workout.set.complete`
- `workout.reps.down`
- `workout.weight.down`

In Dart, `WorkoutNotificationActionIds.lowRiskSurfaceActionsInPriorityOrder` is
the source list for the rendered action order and `privacy.allowedWhileLocked`.
The native receiver's supported action list must stay aligned with this set so
an action shown in the expanded surface is always accepted by the Android
receiver.

The Dart command helper owns the math:

- Reps clamp between `0` and `999`.
- Load clamps between `0 kg` and `9999 kg`.
- Load step comes from `quickLoadStepProvider`.

The action order is intentional. Put the most common in-workout taps first
(`+ Rep`, `+ Load`, `Done`) so constrained notification, Live Updates, or
Samsung Now Bar renderers still expose the core workflow before correction
actions.

`expanded.controls` is the future Now Bar stepper contract. The current Android
notification renderer still uses `expanded.actions`, while a richer Samsung
renderer can use these control descriptors to bind visible reps/load steppers to
the same shared command IDs. The controls include internal units and min/max
bounds that match the Dart command clamps: reps `0..999` and load
`0..9999 kg`.
The low-risk reps/load/set-complete commands explicitly declare
`requiresUnlock: false` and are listed under `privacy.allowedWhileLocked`;
destructive or broad edit commands should be added later with
`requiresUnlock: true`.

`targetSetId` binds rendered controls to the set the user saw when the surface
was posted. Action handlers should drop stale commands if the active workout has
advanced to a different target set before the tap is delivered.
Surface diagnostics should report this value from the in-memory snapshot or the
persisted surface state, so a device test can still verify the displayed target
after process/engine rehydration.

## Flutter to Android Bridge

Flutter now publishes the same snapshot through this MethodChannel:

- Channel: `com.ams.herculex/ongoing_workout_surface`
- Method: `update`
- Arguments: the snapshot map shown above
- Method: `clear`
- Arguments: none
- Method: `drainPendingActions`
- Returns: queued native action IDs, then clears the native queue
- Method: `getCapabilities`
- Returns: `androidSdkInt`, `android16Plus`, `notificationsEnabled`, and
  `canPostPromotedNotifications`
- Method: `getSurfaceDiagnostics`
- Returns: posted state, requested promoted ongoing state, Android promotable
  characteristics, system promoted ongoing state, base notification permission
  state, channel importance, ongoing flag and chronometer metadata, action/row
  and control counts, current target labels, pending native action count, dropped stale
  action count, last native action metadata, and whether immediate native
  feedback was posted for the last native action. It also reports native
  receiver rejections, including the last rejected action and reason, so stale
  session/set protection is visible in the app diagnostics sheet.
- Method: `sendDiagnosticAction`
- Arguments: `actionId`, optional `sessionId`, optional `setId`
- Debug builds only. Sends the same native `PendingIntent` that a Samsung Now
  Bar / Live Updates control would attach, so testers can validate the native
  receiver, queue, drain, and Dart command path before the OEM surface appears.
- Method: `openPromotedNotificationSettings`
- Opens Android's promoted notification settings when available, falling back to
  the normal app notification settings screen.

The current Kotlin adapter lives at
`android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceAdapter.kt`.
It validates that `update` receives a map, parses it into a typed
`OngoingWorkoutSurfaceSnapshot`, stores the latest snapshot in memory, and logs
update/clear events. This means native code already knows the collapsed status,
expanded rows, and available action IDs before any Samsung-specific rendering API
is introduced. It also prebuilds session-scoped `PendingIntent`s for supported
expanded action IDs, so a future renderer can attach them directly to Now Bar /
Live Updates controls.
When an action receiver accepts a command, it queues the command before trying
to post immediate feedback. Feedback post failures are diagnostic only and must
not drop the reps/weight command.
When an action receiver rejects a stale session or stale target set, it records
that rejection in diagnostics without queueing the command.

Rendering is behind `OngoingWorkoutSurfaceRenderer`:

- `show(snapshot, actionPendingIntents)` receives the typed collapsed/expanded
  surface and ready-to-attach action intents.
- `clear()` removes the rendered surface.
- `AndroidOngoingWorkoutSurfaceRenderer` is the current implementation. It posts
  an Android workout notification with collapsed status, expanded row text,
  session-scoped actions, chronometer metadata, ongoing-event flags, and a
  reflective promoted-ongoing request when the platform exposes it.
- A future Samsung-specific implementation should replace or extend only this
  renderer, not the Flutter channel, snapshot parser, action receiver, queue, or
  Dart command logic.

Future native Now Bar / Live Updates controls can reuse
`OngoingWorkoutActionReceiver.pendingIntentFor(context, actionId, sessionId, setId)`.
The receiver rejects stale session IDs and queues supported action IDs in native
SharedPreferences without opening the app. Native queued actions include
`actionId`, `sessionId`, and `setId`. Flutter drains that queue through
`drainPendingActions` during its existing foreground/pending-action flow and
applies commands through the shared Dart `workoutNotificationPatchForAction`
helper only if the active target set still matches.

Flutter should only drain the native queue after `activeSessionProvider` has a
known session ID. If the app is still hydrating active workout state, native
actions must remain in native storage so their session identity is not flattened
into a sessionless fallback action. Once drained, every action is still applied
with the active session ID as a guard. The native adapter also enforces this
invariant internally: `drainPendingActions` returns no actions and leaves native
storage untouched when no persisted active session is available.
The Flutter lifecycle sync follows the same rule for clearing rendered workout
surfaces: it only calls native `clear` after the active-session provider has
resolved to `null`. Loading or transient error states must not clear the native
surface state or queued reps/weight taps.

## Android API Gating

Current Android Gradle config uses Flutter-provided SDK values:

- `compileSdk = flutter.compileSdkVersion`
- `targetSdk = flutter.targetSdkVersion`
- `minSdk = 26`

Because full Android Live Updates / progress-centric notification APIs are
Android-version dependent, the native adapter should be guarded by compile-time
and runtime checks:

- Compile-time: only call Android 16+ APIs when the project is compiling against
  the required SDK.
- Runtime: only enable enhanced Live Updates / Now Bar behavior when the device
  exposes the required platform behavior.
- Permission: request `android.permission.POST_PROMOTED_NOTIFICATIONS` in the
  manifest for Android Live Updates promotion eligibility.
- Capability: `LiveUpdatesCapability` currently gates Android 16+ support and
  reports whether base app notifications are enabled. It reflectively checks
  `NotificationManager.canPostPromotedNotifications()` when present. Flutter can
  read the same state through the bridge's `getCapabilities` method.
- Notification fallback: the ongoing workout notification sets `when` to the
  workout start time, enables chronometer mode for elapsed workout time, and
  explicitly includes the ongoing event flag on both paths.
- Single publisher per device tier: exactly one publisher writes notification id
  `1` on channel `workout_live`. On Android 16+ that is the native renderer,
  which builds a promotable Live Update with the platform `Notification.Builder`
  (`setRequestPromotedOngoing`, `ProgressStyle`, `setShortCriticalText`); the
  Flutter `flutter_local_notifications` post is skipped there, because the
  installed plugin cannot express those setters and its non-promotable
  notification would immediately overwrite the promoted one. Below Android 16
  the `flutter_local_notifications` path is the only publisher and the native
  renderer falls back to `NotificationCompat` + `BigTextStyle`. In both cases
  the Dart side still pushes the snapshot to the native surface after posting.
- The native feedback notification (`OngoingWorkoutSurfaceFeedback`) uses its own
  notification id so it can never overwrite the Live Update.

## Lock-Screen Policy

Allowed without opening the full app:

- `workout.reps.up`
- `workout.weight.up`
- `workout.set.complete`
- `workout.reps.down`
- `workout.weight.down`

Not part of the current low-risk action set:

- Delete set.
- Finish workout.
- Change exercise.
- Edit previous sets.
- Change template or program.

## Implementation Notes

The native adapter now has a dedicated package:

```text
android/app/src/main/kotlin/com/ams/herculex/nowbar/
```

Current/future classes:

- `OngoingWorkoutSurfaceAdapter`: current MethodChannel receiver and safe
  fallback holder.
- `OngoingWorkoutSurfaceSnapshot`: current typed parser for collapsed status,
  expanded rows/actions, and privacy metadata.
- `OngoingWorkoutActionReceiver`: current native action receiver for future
  Samsung/Live Updates action PendingIntents.
- `OngoingWorkoutActionQueue`: current native queue drained by Flutter through
  the surface bridge.
- `OngoingWorkoutSurfaceRenderer`: renderer boundary for Samsung Now Bar / Live
  Updates APIs.
- `AndroidOngoingWorkoutSurfaceRenderer`: current Android notification renderer
  that requests promoted ongoing behavior when the platform supports it.
- `LiveUpdatesCapability`: current runtime gate for Android Live Updates /
  promoted ongoing notification support.

The adapter should use the same receiver/queue strategy as the current
notification fallback until native immediate writes are implemented. Once native
DB access or a background-safe command bridge exists, action receivers can apply
commands immediately and then ask Flutter to refresh when it wakes.
