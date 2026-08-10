---
status: diagnosed
phase: 08-samsung-now-bar-live-update
source: [08-01-SUMMARY.md, 08-02-SUMMARY.md]
started: 2026-08-04T00:00:00Z
updated: 2026-08-04T13:00:00Z
---

## Current Test

[testing paused — 8 items outstanding]

## Tests

### 1. Live Update Promotes Into the Now Bar
expected: On a Samsung Android 16 device, starting a workout and logging a set shows the ongoing notification promoted into the Now Bar (lock screen / status bar chip), not only in the shade. `adb logcat -s WorkoutSurfaceRenderer` shows `event=posted ... promotable=true`.
result: issue
reported: "Fail: promotable=false in systemPromoted=false v logcatu. Glavne ugotovitve iz loga: 1. WorkoutSurfaceRenderer še vedno izpisuje: requestedPromoted=true promotable=false systemPromoted=false 2. Kanal obvestil 'workout_live' ima nastavitev channelImportance=low (za promocijo v Now Bar sistem zahteva vsaj DEFAULT ali HIGH importance). Log izsek: D/WorkoutSurfaceRenderer( 5354): Posted Arch Hold (Band) with 5 actions; posted=true requestedPromoted=true promotable=false systemPromoted=false; android16Plus=true notificationsEnabled=true canPostPromoted=true / I/WorkoutSurfaceRenderer( 5354): diagnostics event=posted surface=active_workout session=70 ... channelImportance=low ... requestedPromoted=true promotable=false systemPromoted=false"
severity: blocker

### 2. Progress Style and Short Critical Text
expected: The expanded ongoing workout notification shows a segmented progress bar with one segment per set, filled up to the current set. The Now Bar chip shows a short counter like "3/5". Logcat shows `style=ProgressStyle` and a non-empty `shortCriticalText=`.
result: issue
reported: "Fail: Čip v Now Bar se ne prikaže (ker je promotable=false zaradi channelImportance=low), poleg tega pa je shortCriticalText ob nekaterih dogodkih prazen. Podrobnosti iz logcat-a: 1. style=ProgressStyle se v logu izpiše pravilno. 2. shortCriticalText=\"1/1\" se pojavi ob vajah, vendar se ob \"Workout in progress\" spremeni v prazen niz shortCriticalText=\"\". 3. Na zaslonu čipa \"1/1\" ni mogoče preveriti v Now Bar-u, ker obvestilo ni promovirano (systemPromoted=false). Log izsek: I/WorkoutSurfaceRenderer: diagnostics event=posted ... style=ProgressStyle shortCriticalText=\"1/1\" ... / I/WorkoutSurfaceRenderer: diagnostics event=posted ... style=ProgressStyle shortCriticalText=\"\" ..."
severity: major

### 3. Notification Is Not Overwritten (Repost Rate)
expected: With a workout active and nothing being changed, count `event=posted` lines over 30 idle seconds — roughly 1, not ~30. Between them you see `event=updateSkipped reason=unchanged`. The Now Bar chip stays put and does not flicker or drop out of promotion.
result: issue
reported: "Fail: notify(1, ...) se sproža večkrat v nekaj sekundah namesto enkrat na ~30 sekund neaktivnosti. event=updateSkipped reason=unchanged sicer deluje pravilno vmes, ampak se zdi da se stanje seje prepogosto osvežuje ali da se notify(1, ...) sproža iz več virov. Log izsek: I/NotificationManager: com.ams.herculex: notify(1, null, ...) / D/WorkoutSurfaceRenderer: Posted Arch Hold (Band)... / I/NotificationManager: com.ams.herculex: notify(1, null, ...) / D/WorkoutSurfaceRenderer: Posted Workout in progress..."
severity: major

### 4. Elapsed Timer Still Ticks
expected: Even though the notification is only reposted every ~5 seconds, the elapsed workout time in the notification counts up smoothly every second (drawn by the system chronometer).
result: [pending]

### 5. Rest Timer Alerts Audibly
expected: Finish a set so the rest timer starts and let it run out. The rest-timer notification arrives on the new `workout_rest` channel as a heads-up alert with sound/vibration — previously it was silent. (If the app was installed before this change, this needs a fresh install or app-data clear so the new channel is created.)
result: [pending]

### 6. Now Bar Actions Work
expected: Tap `+ Rep` (or another action) directly from the Now Bar / notification. The active set increments in the app, and the notification updates to match. Logcat shows the action accepted, not rejected.
result: [pending]

### 7. Stale Action Is Rejected
expected: Trigger an action from a notification snapshot for a set you have already moved past (e.g. advance to the next set, then tap a stale action from an old notification/lock-screen view). The tap is rejected rather than applied — logcat shows `event=rejected`, and the app state is unchanged.
result: [pending]

### 8. Diagnostics Show Rejection Detail
expected: In the workout settings sheet, the diagnostics list shows `Rejected Native` count plus two new rows: `Rejected Action` (the action id) and `Rejected Reason`. The old duplicate `Last Rejected` row at the bottom is gone.
result: [pending]

### 9. Teardown Leaves Nothing Behind
expected: End the workout (and separately: background the app, then force-close it). In every case no ongoing workout notification and no Now Bar chip remain — the surface is fully cleared.
result: [pending]

### 10. Feedback Notification Does Not Replace the Live Update
expected: When a feedback/confirmation notification fires (e.g. after a native action), it appears as its own separate notification. The ongoing workout Live Update stays present and stays promoted in the Now Bar — it is not replaced or demoted.
result: [pending]

### 11. Pre-Android-16 Path Unchanged
expected: On a device (or emulator) below API 36, starting a workout still shows the ongoing workout notification via the normal Flutter notification path, with the elapsed time and set info, and actions still work. No crash, no missing notification.
result: [pending]

## Summary

total: 11
passed: 0
issues: 3
pending: 8
skipped: 0
blocked: 0

## Gaps

- truth: "Ongoing workout notification is promotable and appears in the Samsung Now Bar; logcat shows promotable=true"
  status: fixed
  reason: "User reported: promotable=false and systemPromoted=false in logcat despite requestedPromoted=true. The 'workout_live' channel reports channelImportance=low; Now Bar promotion requires at least DEFAULT importance."
  severity: blocker
  test: 1
  root_cause: "AndroidOngoingWorkoutSurfaceRenderer.ensureChannel() created the 'workout_live' channel at IMPORTANCE_LOW, which Android 16 Now Bar promotion rejects (needs >= DEFAULT). Channel importance is fixed at creation, so on an existing install the channel stayed LOW forever regardless of code changes."
  artifacts:
    - path: "android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceRenderer.kt"
      issue: "ensureChannel() used NotificationManager.IMPORTANCE_LOW with no migration path for already-created channels"
  missing:
    - "Create the channel at IMPORTANCE_DEFAULT"
    - "Detect an existing channel below DEFAULT and delete+recreate it once so already-installed devices pick up the higher importance without requiring a fresh install"
  debug_session: ""

- truth: "Now Bar chip shows a short set counter and shortCriticalText is always non-empty while a workout is active"
  status: fixed
  reason: "User reported: style=ProgressStyle logs correctly, but shortCriticalText is \"1/1\" during exercises and becomes an empty string on the \"Workout in progress\" snapshot. The chip itself cannot be checked because the notification is not promoted (systemPromoted=false, gap from test 1)."
  severity: major
  test: 2
  root_cause: "Two contributing causes. (1) Native: shortCriticalTextFor() returned null whenever the snapshot had no parseable set counter and a blank collapsed.value — which is exactly the 'no target' snapshot shape. (2) Dart: buildOngoingWorkoutSurfaceSnapshot() falls back to exerciseName 'Workout in progress' with currentSet=null (empty subtitle/value) whenever WorkoutsRepository.activeNotificationTargetForSession() returns null. That method ran as unsynchronized sequential queries (exercises, catalog, then sets per exercise), so a concurrent write from another listener between those awaits could be observed as a transient 'exercise with no sets yet' state, tripping the null-target fallback mid-workout."
  artifacts:
    - path: "android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceRenderer.kt"
      issue: "shortCriticalTextFor() had no non-blank fallback"
    - path: "lib/features/workouts/data/workouts_repository.dart"
      issue: "activeNotificationTargetForSession() read exercises/catalog/sets as unsynchronized sequential queries, vulnerable to a concurrent write landing mid-read"
  missing:
    - "Native: fall back shortCriticalText to a short non-blank label ('Active') instead of null when no counter/value is available"
    - "Dart: wrap the exercises/catalog/sets reads in _db.transaction() for a consistent snapshot"
  debug_session: ""

- truth: "With a workout active and idle, `event=posted` fires roughly once, then repeated updates are skipped via `event=updateSkipped reason=unchanged` until something actually changes"
  status: fixed
  reason: "User reported: notify(1, ...) fires repeatedly within a few seconds instead of ~once per 30 idle seconds. event=updateSkipped reason=unchanged does appear between some posts, but session state appears to refresh too often or notify(1, ...) is triggered from more than one source."
  severity: major
  test: 3
  root_cause: "_HerculexAppState registers one ref.listen(sessionExercisesProvider) plus one ref.listen(setsForWorkoutExerciseProvider(...)) per exercise, and every one of them calls _syncNotification() directly. A single set update touches both the sets table and (via the exercises listener rebuild) the exercises stream, so multiple listeners fire within the same frame and each independently re-reads the DB and calls showOrUpdate()/OngoingWorkoutSurfaceBridge.update() — several real (non-deduped) notify() calls for what is conceptually one change, which also explains the title alternating with the 'Workout in progress' fallback from the gap-2 race."
  artifacts:
    - path: "lib/app/app.dart"
      issue: "_syncNotification() ran synchronously and was called directly from multiple independent ref.listen callbacks with no coalescing"
  missing:
    - "Debounce _syncNotification() (~200ms) so multiple listener firings for the same underlying write collapse into a single native update() call"
  debug_session: ""

## Fixes Applied

Diagnosed and fixed directly in this session (2026-08-04) rather than routed through
plan-phase/execute-phase — all three gaps were narrowly scoped to files already open in
context:

- `android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceRenderer.kt` —
  `ensureChannel()` now creates/migrates `workout_live` to `IMPORTANCE_DEFAULT`;
  `shortCriticalTextFor()` never returns blank/null.
- `lib/app/app.dart` — `_syncNotification()` debounces 200ms before calling the renamed
  `_syncNotificationNow()`.
- `lib/features/workouts/data/workouts_repository.dart` —
  `activeNotificationTargetForSession()` reads inside `_db.transaction()`.

Verified: `flutter analyze` clean on both changed Dart files; `gradlew :app:compileDebugKotlin`
clean. Not yet re-verified on a physical Samsung Android 16 device — re-run
`/gsd:verify-work 08` (or just retest 1–3 manually) after installing a fresh build.
Note: existing installs need the app reinstalled/data-cleared for the channel-importance fix
to take effect, same as the workout_rest channel caveat in test 5.
