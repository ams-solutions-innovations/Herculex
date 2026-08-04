# Samsung Now Bar Workout Proposal

Last updated: August 3, 2026

## Goal

Samsung should open the Now Bar much more deeply for third-party developers in
One UI 8.5 or One UI 9.0. For Herculex and similar workout apps, the Now Bar
should not be only a passive live notification. It should become a small,
trusted workout control surface:

- Collapsed Now Bar: ongoing workout status at a glance.
- Expanded Now Bar: quick edits for reps, weight, set completion, rest, pause,
  and resume.
- Full app: detailed programming, history, exercise selection, analytics, and
  any destructive edits.

This fits Android Live Updates because a workout is user-initiated, ongoing,
time-sensitive, and benefits from glanceable state while the user is physically
busy.

## Product Problem

During a strength workout, opening the full app for every tiny set edit is
friction:

- Hands may be sweaty, chalky, gloved, or holding equipment.
- The phone is often locked, on the floor, on a bench, or in a pocket.
- The user needs fast actions like `+1 rep`, `-1 rep`, `+2.5 kg`, complete set,
  or start rest.
- A full-screen app interruption is too heavy for a two-second logging action.

The current best surfaces are notifications, lock-screen shortcuts, widgets, and
Wear OS. They help, but they are split across surfaces. The ideal Samsung
experience is one continuous Now Bar activity that follows the active workout.

## Desired User Experience

### Collapsed Now Bar

The collapsed Now Bar should show the current workout state without requiring
interaction:

```text
Bench Press  Set 3/5  80 kg x 8
Rest 01:12
```

Useful collapsed fields:

- Exercise name.
- Current set index and total sets.
- Planned or current weight.
- Planned or current reps.
- Rest countdown when resting.
- Workout duration when actively lifting.
- Optional heart rate when the user has granted health permissions.

Collapsed behavior:

- Tap opens the expanded Now Bar.
- Long press can open the full Herculex active workout screen.
- Sensitive fields should respect lock-screen privacy settings.

### Expanded Now Bar

The expanded Now Bar should become a compact set logger:

```text
Bench Press
Set 3 of 5

Weight       [-] 80 kg [+]
Reps         [-] 8     [+]

[Complete Set]  [Start Rest]  [Pause]
```

Expected actions:

- Increase/decrease reps.
- Increase/decrease weight using the app's configured increment.
- Complete the current set.
- Start or adjust rest timer.
- Pause/resume workout.
- Open the full app for advanced editing.

The expanded surface should be stateful. If the user changes `80 kg x 8` to
`82.5 kg x 9`, Herculex should receive the action immediately and update the
same active workout state that the phone app and Wear app use.

## Developer API Request

Samsung should expose a public Now Bar activity API layered on top of Android
Live Updates / progress-centric notifications. Android can continue to own the
base notification model, while One UI adds an explicit contract for Now Bar
presentation and actions.

Conceptual API shape:

```kotlin
NowBarActivity.Builder(context, "active_workout")
    .setCategory(NowBarCategory.WORKOUT)
    .setCollapsedContent(
        title = "Bench Press",
        subtitle = "Set 3/5",
        value = "80 kg x 8",
        timer = NowBarTimer.restCountdown(72_000),
    )
    .setExpandedContent(
        title = "Bench Press",
        rows = listOf(
            NowBarStepper("weight", label = "Weight", value = "80 kg"),
            NowBarStepper("reps", label = "Reps", value = "8"),
        ),
        actions = listOf(
            NowBarAction("complete_set", "Complete Set"),
            NowBarAction("start_rest", "Start Rest"),
            NowBarAction("pause", "Pause"),
        ),
    )
    .setPrivacyMode(NowBarPrivacy.RESPECT_LOCK_SCREEN_SETTINGS)
    .setUnlockPolicy(
        lowRiskActions = setOf("reps.increment", "reps.decrement", "complete_set"),
        requiresUnlock = setOf("delete_set", "finish_workout", "change_exercise"),
    )
    .build()
```

The exact API does not need to match this shape, but developers need these
capabilities:

- A stable way to declare a Now Bar activity type.
- Separate collapsed and expanded layouts.
- Bounded interactive controls such as buttons, steppers, toggles, and timers.
- Action callbacks delivered to the app or foreground service.
- A way to update state without recreating the activity.
- A way to check whether Now Bar enhanced rendering is available.
- Privacy and unlock policies for lock-screen behavior.

## Herculex Integration Shape

Herculex already has the right conceptual state:

- Active workout session.
- Active exercise.
- Set entries with weight and reps.
- Rest timer settings.
- Phone-to-Wear and Wear-to-phone active workout sync.
- Workout notification lifecycle.

The Now Bar integration should use the same active workout source of truth. The
Now Bar should be another projection of active workout state, not a separate
mini workout system.

Recommended internal model:

```text
WorkoutRepository / ActiveWorkoutState
        |
        +-- Flutter active workout UI
        +-- Wear OS active workout UI
        +-- Android notification / Live Update
        +-- Samsung Now Bar enhanced surface
```

Recommended command path:

```text
Now Bar action
  -> Android action receiver / foreground service
  -> active workout command
  -> repository update
  -> Flutter UI, Wear sync, notification, and Now Bar refresh
```

Example commands:

- `IncrementCurrentSetReps(delta = 1)`
- `IncrementCurrentSetWeight(deltaKg = 2.5)`
- `CompleteCurrentSet`
- `StartRestTimer`
- `PauseWorkout`
- `ResumeWorkout`

## Current Herculex Preparation

Herculex now has a first Android-side preparation layer for this idea through
the active workout notification:

- The ongoing workout notification shows the active exercise, current set,
  total sets, weight, reps, and elapsed time.
- The notification refreshes when the active session changes, when active
  session exercises change, and when active set rows change, so reps and weight
  stay current across phone UI, Wear sync, and notification actions.
- The current notification target is the first exercise, in workout order, with
  an uncompleted set. If every set is completed, it falls back to the last known
  set so the status remains meaningful.
- The target-selection rule lives in a pure Dart selector with unit coverage, so
  the future Now Bar adapter can reuse the same target choice as the current
  Android notification.
- The displayed set number is user-facing, so database `setIndex = 0` appears as
  `Set 1`.
- Android notification actions map to the same low-risk commands a future
  expanded Now Bar should expose:
  - `- Rep`
  - `+ Rep`
  - `- kg`
  - `+ kg`
  - `Done`
- These actions update the active set through `WorkoutsRepository.updateSet`,
  keeping the normal active workout state as the source of truth.
- The action-to-set-update math lives in a reusable command helper with unit
  coverage. Reps clamp between `0` and `999`; weight clamps between `0 kg` and
  `9999 kg`; the default weight step is `2.5 kg`.
- The visible status uses the app's weight formatter, so the collapsed surface
  can show the same unit system as the rest of Herculex.
- Workout settings include a Quick Load Step preference. Notification actions
  use the stored step for both command math and action labels, so the expanded
  surface can show `- 2.5 kg` / `+ 2.5 kg` or equivalent imperial steps.
- Expanded workout actions are ordered with the most likely in-gym taps first:
  `+ Rep`, `+ kg`, `Done`, then the correction actions `- Rep` and `- kg`.
  This keeps the essential controls visible even if a constrained Android or
  Samsung surface only renders the first few actions.
- The ongoing notification refreshes when the unit system or Quick Load Step
  changes, so collapsed status text and expanded action labels stay consistent
  during an active workout.
- The Android manifest registers the notification action receiver required by
  `flutter_local_notifications`, and the ongoing notification is categorized as
  a workout with private lock-screen visibility.
- The ongoing notification now uses Android's `when` + chronometer fields based
  on workout `startedAt`, so Android Live Updates / status chips have a native
  elapsed-time signal instead of only text in the notification title.
- The notification also explicitly carries the ongoing event flag in addition to
  `ongoing: true`.
- On Android 16+ the native renderer builds the notification with the platform
  `Notification.Builder` and calls the real Live Update setters directly:
  `setRequestPromotedOngoing(true)`, `setStyle(Notification.ProgressStyle())`
  with one segment per set, and `setShortCriticalText` carrying the set counter
  (for example `3/5`). `setLocalOnly` and `setSilent` are deliberately omitted
  there because either can disqualify the notification from promotion.
  `hasPromotableCharacteristics()` and `FLAG_PROMOTED_ONGOING` are read as
  direct platform calls and surfaced through the diagnostics channel.
- Background notification actions are queued in SharedPreferences and drained
  when the app returns with active workout state available. That keeps non-UI
  actions from being silently lost when Android delivers them to a background
  isolate.
- The future native Android/Samsung bridge is specified in
  [now-bar-native-adapter-contract.md](now-bar-native-adapter-contract.md), so
  Now Bar support can reuse the same collapsed status and expanded action
  contract instead of creating a parallel workout-control path.
- The ongoing workout surface snapshot is now represented in Dart and covered by
  unit tests. The current notification fallback consumes the same exercise/set
  labels and expanded action definitions that a future native Now Bar adapter
  should consume.
- The expanded snapshot also carries explicit stepper control descriptors for
  reps and load. These controls bind display values, numeric values, increments,
  internal units, min/max bounds, and increment/decrement action IDs into one
  contract so a future Samsung Now Bar renderer can draw real opened-state
  steppers without inventing another command model.
- The low-risk action policy is explicit in the same snapshot: reps up/down,
  load up/down, and complete set declare `requiresUnlock: false` and are listed
  in `allowedWhileLocked`. Destructive edits are intentionally absent from this
  lock-screen action set.
- Workout settings expose a `Now Bar / Live Updates` diagnostics sheet. It shows
  the active Android SDK, promoted notification permission state, posted status,
  base notification permission state, channel importance, requested promoted
  ongoing state, ongoing-event flag, chronometer metadata, promotable
  characteristics, whether the system marked the notification as promoted
  ongoing, action/control counts, pending native actions, the current collapsed
  reps/weight value, target set id, dropped stale native actions, rejected stale
  native actions, the last native action, whether immediate feedback for that
  native action was posted, and the last native rejection reason.
- The native Android adapter emits structured logcat diagnostics for surface
  posts, immediate queued-action feedback, and action drains. These logs let a
  Samsung device test prove whether the workout notification is eligible, whether
  One UI promoted it, and whether reps/weight actions round-trip back to the app.
- If Flutter asks native code to drain before the active session is known, the
  native adapter emits `event=drainSkipped reason=no_active_session` and leaves
  queued actions in native storage for the next drain.
- If the app foregrounds while active workout state is still hydrating, Flutter
  does not clear the native surface or pending native actions. The surface is
  cleared only after active workout state has resolved to no active session.
- Ending the workout clears the native action queue and persisted surface
  display state, so stale reps/weight actions cannot leak into the next workout.
- Native action intents carry the workout session id. If Android delivers an old
  action after the surface has been cleared or a new workout has started, the
  receiver rejects it instead of applying it to the current set.
- Surface snapshots, Flutter notification payloads, and native queued actions
  also carry the displayed target set id. If the workout advances before a
  delayed reps/weight tap is applied, Herculex treats the action as stale and
  does not mutate the newly active set.
- The native pending-action queue stores the same session id and filters during
  drain, so a queued action cannot be applied to a later workout even if the
  active session changes after the tap but before Flutter drains the queue.
- The Flutter fallback notification action queue follows the same session-aware
  rule. Background notification actions store the workout session id from the
  notification payload, then drain only for the matching active session.

This is not a full Now Bar integration because Samsung does not currently expose
the custom expanded Now Bar control API described above. It is a compatibility
step: once Samsung exposes richer Now Bar controls, Herculex can map the same
commands into that surface instead of inventing a second workout-control path.

Important limitation: Flutter notification actions that do not open the UI can
run in a background isolate. The queue prevents action loss, but a production-
grade Samsung Now Bar integration should still move these command handlers into
a native Android foreground-service adapter when Samsung exposes richer controls,
so reps and weight edits can be applied immediately even when Flutter UI state is
not alive.

## Samsung Device Verification Checklist

Use this checklist on a Samsung device running the target One UI build:

1. Install a debug build and grant notification permission.
2. Start a workout with at least one exercise and one open set.
3. Open workout settings, tap `Now Bar / Live Updates`, and refresh the
   diagnostics sheet.
   - On debug builds, the bug icon opens diagnostic `+ Rep`, `+ Load`, `Done`,
     `- Rep`, and `- Load` actions through the same native `PendingIntent` route
     that a future Now Bar control uses. Use it to validate receiver/queue/drain
     before testing the actual One UI surface.
4. Confirm the sheet reports:
   - `Android: SDK 36` or newer for Android Live Updates support.
   - `Notifications: Yes`.
   - `Promoted Allowed: Yes`, or open settings from the sheet and enable it.
   - `Notification Posted: Yes`.
   - `Requested Promoted: Yes`.
   - `Promotable: Yes`.
   - `Channel: low`.
   - `Ongoing Flag: Yes`.
   - `Chronometer: Yes`.
   - `Actions: 5 shown`.
   - `Controls: 2 steppers`.
   - `Action Contract: Yes`.
   - `Diagnostic Actions: Yes` on debug builds when using the bug-icon
     receiver/queue/drain pre-test.
   - `Target Set: #...` matching the currently displayed active set.
   - `Rejected Native: 0`, `Rejected Action: None`, and `Rejected Reason: None`
     before any stale-action test.
   - In logcat, the renderer's `event=posted` line reports `style=ProgressStyle`
     on Android 16+ (it reads `BigTextStyle` only on the pre-16 fallback path)
     and a non-empty `shortCriticalText` such as `3/5`.
5. Watch logcat while changing reps/weight or completing a set from the
   notification or Now Bar:
   - The queued log should include the active `session=<id>` and `set=<target set id>`.
   - The active set in the app should update, then the notification / Now Bar
     should refresh to the new reps or weight value.

```powershell
adb logcat -s WorkoutSurfaceRenderer OngoingWorkoutSurface OngoingWorkoutAction WorkoutSurfaceFeedback
```

Expected logs:

```text
WorkoutSurfaceRenderer: diagnostics event=posted ... posted=true notificationsEnabled=true channelImportance=low style=ProgressStyle shortCriticalText="3/5" ... promotable=true ...
OngoingWorkoutSurface: diagnostics event=updateSkipped reason=unchanged
WorkoutSurfaceFeedback: diagnostics event=feedback action=workout.reps.up posted=true ...
OngoingWorkoutAction: diagnostics event=queued action=workout.reps.up ... feedbackPosted=true
OngoingWorkoutSurface: diagnostics event=drained count=1 actions=workout.reps.up:set=10
OngoingWorkoutSurface: diagnostics event=drainSkipped reason=no_active_session
OngoingWorkoutSurface: diagnostics event=cleared
OngoingWorkoutAction: diagnostics event=rejected action=workout.reps.up session=123 active=null
OngoingWorkoutAction: diagnostics event=rejected action=workout.reps.up reason=stale_set session=123 set=10 activeSet=11
OngoingWorkoutSurface: diagnostics event=dropped session=456 count=1
```

Runtime pass criteria:

- Collapsed surface shows the active exercise, set, reps, weight, and timer.
- Expanded surface exposes reps up, weight up, done, reps down, and weight down
  actions, in that priority order.
- A `+ Rep` action increments the active set in Herculex.
- A `+ Weight` action increments by the configured Quick Load Step.
- `Done` completes the current set and advances the target to the next open set.
- Each accepted action is scoped to the active `sessionId` and `Target Set`;
  a delayed tap for an older set must be rejected instead of editing the newly
  active set.
- `Last Feedback: Yes` appears after a native surface action if Android accepted
  the immediate queued-action feedback notification. If feedback is `No`, the
  action should still drain and apply because queueing happens before feedback.
- Ending the workout emits `event=cleared`, dismisses the surface, and leaves the
  next diagnostics refresh without a stale target.
- A delayed action from an old workout or old target set emits
  `event=rejected`, increments `Rejected Native`, and fills in `Rejected Action`
  and `Rejected Reason` in the diagnostics sheet, without changing the current
  active workout.
- With a workout active and no user input, `event=posted` appears at most once
  per snapshot change — roughly once over 30 idle seconds, not thirty times.
  Intervening ticks emit `event=updateSkipped reason=unchanged`.
- An action flagged `requiresUnlock` emits
  `event=rejected reason=requires_unlock` and opens the app instead of being
  applied silently. None of the five current low-risk actions is flagged, so
  this path should not trigger during a normal run.
- A stale queued action emits `event=dropped` during drain and does not reach
  Flutter's workout command handler.
- The diagnostics sheet shows `System Promoted: Yes` if One UI actually promoted
  the notification into the Now Bar. If all other signals pass but this remains
  `No`, Herculex is prepared correctly and the remaining limitation is Samsung
  One UI policy/API exposure.

## Safety And Privacy Rules

The Now Bar should allow fast logging, but avoid accidental destructive edits.

Allowed while locked:

- Increment/decrement reps by one.
- Increment/decrement weight by the app's configured small step.
- Complete current set.
- Start rest timer.
- Pause workout.

Require unlock:

- Delete set.
- Finish workout.
- Change exercise.
- Edit previous sets.
- Change program/template.
- Add notes or private health details.

Privacy modes:

- Full: show exercise, weight, reps, timer.
- Reduced: show `Workout in progress` plus timer only.
- Hidden: show only the app name and a generic active indicator.

## Samsung Feedback Text

Short version:

```text
Samsung should open Now Bar much more for third-party developers in One UI 8.5
or One UI 9.0. For workout apps, the collapsed Now Bar should show ongoing
workout status, while the expanded Now Bar should allow quick edits like reps,
weight, set completion, rest timer, and pause/resume. This should be a proper
developer API integrated with Android Live Updates, not limited to static
notifications or Samsung-only apps.
```

Longer version:

```text
Now Bar would be especially powerful for strength workout apps. During a workout,
users constantly need tiny interactions: increase reps, adjust weight, complete
a set, start rest, or pause the workout. Opening the full app each time is
unnecessary friction, especially when the phone is locked or the user is holding
equipment.

Please expose a public Now Bar developer API with separate collapsed and expanded
states. The collapsed state could show "Bench Press, Set 3/5, 80 kg x 8". The
expanded state could show steppers for reps and weight plus buttons for Complete
Set, Start Rest, and Pause. Low-risk actions could be allowed on the lock screen,
while destructive actions like deleting sets or finishing the workout should
require unlock.

This would make Now Bar feel like a true system-level ongoing activity surface,
similar to Live Activities, while still respecting Android Live Updates and
Samsung lock-screen privacy controls.
```

## Open Questions

- Will Samsung expose custom expanded controls directly, or only map Android
  notification actions into Now Bar?
- Will One UI allow lock-screen action callbacks for third-party apps without
  unlocking?
- Can a promoted Android Live Update become a Now Bar item automatically, or
  does Samsung require a separate eligibility policy?
- Should Health Connect workout sessions be the shared system source, or should
  each app own its own active workout state?
- Can Wear OS actions and Now Bar actions share a single command protocol?

## References

- Android Live Updates documentation:
  https://developer.android.com/develop/ui/compose/notifications/live-update
- Android 16 progress-centric notifications:
  https://developer.android.com/about/versions/16/features/progress-centric-notifications
- Samsung Now Bar support overview:
  https://www.samsung.com/us/support/answer/ANS10004605/
- Reporting on One UI 8 third-party Live Updates / Now Bar support:
  https://www.androidauthority.com/one-ui-8-live-updates-support-3573794/
