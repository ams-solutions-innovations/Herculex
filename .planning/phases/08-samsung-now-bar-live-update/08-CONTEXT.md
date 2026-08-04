# Phase 08: Samsung Now Bar Live Update - Context

**Gathered:** 2026-08-04
**Status:** Ready for execution
**Source:** Codebase audit of the existing Now Bar adapter layer (no discuss-phase; the prior work is already documented in `docs/now-bar-native-adapter-contract.md`)

<domain>
## Phase Boundary

Make the ongoing workout notification an actual Android 16 Live Update so Samsung One UI can promote it into the Now Bar, and reduce the ongoing-workout notification to a single publisher.

In scope: the native renderer, the native feedback notification, the Flutter/native publish split, the notification channels, surface teardown, and lock-screen policy enforcement in the native action receiver.

Out of scope: the surface snapshot shape, the MethodChannel contract, the native action queue, the stale session/set rejection logic, and the Dart command math. These are already built and tested and must not be redesigned. Also out of scope: rendering `expanded.controls` as real steppers — Samsung exposes no such API yet.
</domain>

<decisions>
## Implementation Decisions

### Renderer
- On API 36+ the renderer uses the **platform `Notification.Builder`**, not `NotificationCompat`. The current androidx version does not expose the promoted-ongoing setters, which is why the existing code fell back to a reflective extras write.
- `requestPromotedOngoing(true)`, `setShortCriticalText(...)` and `Notification.ProgressStyle` are called **directly**. `compileSdk` and `targetSdk` are already 36, so reflection is unnecessary and is removed.
- Below API 36 the existing `NotificationCompat` + `BigTextStyle` path is kept as-is, minus the extras hack.
- `setLocalOnly(true)` and `setSilent(true)` are dropped from the promoted path — both can disqualify a notification from promotion.
- The reflective helpers `requestPromotedOngoingIfAvailable()` and the `"android.requestPromotedOngoing"` string constant are deleted. `hasPromotableCharacteristics()` and `FLAG_PROMOTED_ONGOING` become direct calls under an `SDK_INT >= 36` guard, because they are now the primary success signal.

### Publish path
- The **native renderer is the sole owner of notification id 1 / channel `workout_live`** whenever the platform is API 36+. Flutter stops posting to that id on those devices. Below API 36 the `flutter_local_notifications` path remains the only publisher.
- The reason: today both publishers write id 1 roughly once per second, the native post always wins, and a promotable notification would be immediately overwritten by a non-promotable one.
- Elapsed time is drawn by the notification chronometer, not by reposting. The 1 s ticker drops to 5 s and the adapter skips `renderer.show()` when the snapshot is unchanged apart from `elapsedLabel`.
- The native feedback notification moves off id 1 and does not request promotion — it must not compete with the Live Update.

### Channels
- The rest timer gets its own `workout_rest` channel at `IMPORTANCE_HIGH`. It currently shares `workout_live`, which is created at `IMPORTANCE_LOW`, so its `Importance.max` request is silently downgraded by the system.

### Teardown and policy
- `OngoingWorkoutSurfaceBridge.clear()` is called from the app widget's `dispose()`, not only from the active-session listener.
- `privacy.requiresUnlock` is parsed today and then ignored. The native receiver must honour it: a flagged action routes through an unlock intent instead of executing silently. No action is flagged today, so this is a guard against future regression rather than a behaviour change.

### Claude's Discretion
- Exact `shortCriticalText` content (set counter vs. current load) and the segment/progress mapping onto `ProgressStyle`.
- Where the Kotlin API-36 branch lives (separate builder function vs. inline branch).
- The concrete notification id chosen for the feedback notification.
</decisions>

<canonical_refs>
## Canonical References

**Read these before implementing.**

### Contract
- `docs/now-bar-native-adapter-contract.md` — the snapshot shape, shared action IDs, and the renderer boundary rule ("a future Samsung-specific implementation should replace or extend only this renderer, not the Flutter channel, snapshot parser, action receiver, queue, or Dart command logic").
- `docs/now-bar-workout-proposal.md` — the Samsung device verification checklist and expected logcat output.

### Current implementation
- `android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceRenderer.kt` — the file being rewritten.
- `android/app/src/main/kotlin/com/ams/herculex/nowbar/LiveUpdatesCapability.kt` — the existing `SDK_INT >= 36` gate to branch on.
- `lib/services/workout_notification_service.dart` — the Flutter publisher and the 1 s ticker.
- `lib/app/app.dart` — where the snapshot is built, pushed via `afterPost`, and where the drain loop and `clear()` live.

### Known environment constraint
- `LESSONS.md` — system `java` is 26 and breaks Gradle; use `C:\Program Files\Android\Android Studio\jbr` as `JAVA_HOME`.
</canonical_refs>

<specifics>
## Specific Findings That Drove These Decisions

- `OngoingWorkoutSurfaceRenderer.kt:91-94` writes `extras.putBoolean("android.requestPromotedOngoing", true)` **after** `builder.build()`. This is not the API and does not make the notification promotable.
- No `ProgressStyle` and no `setShortCriticalText` call exists anywhere in the repo.
- `workout_notification_service.dart:53-54` and `OngoingWorkoutSurfaceRenderer.kt:267-269` both declare channel `workout_live` and notification id `1`.
- `workout_notification_service.dart:147-162` reposts and re-invokes `afterPost` every second, so the device receives two `notify()` calls per second on the same id.
- `AndroidOngoingWorkoutSurfaceRenderer.clear()` cancels id 1, which also cancels the Flutter fallback — the contract doc's claim that the fallback always survives is false.
- `scheduleRestTimer` (`workout_notification_service.dart:275-278`) requests `Importance.max` on the already-low `workout_live` channel.
- `app.dart:94-100` disposes without calling the bridge's `clear()`.
- `OngoingWorkoutSurfaceDiagnostics.lastRejectedNativeActionId` and its reason are populated but never rendered in the settings sheet.
</specifics>

<deferred>
## Deferred Ideas

- Rendering `expanded.controls` as real reps/load steppers — blocked until Samsung exposes a Now Bar control API.
- Moving action handling into a native foreground service so reps/load edits apply without a live Flutter engine. The queue currently covers this; the contract doc already flags the service as the production-grade follow-up.
- Enforcing the `Reduced` / `Hidden` privacy modes described in the proposal doc.
</deferred>

---

*Phase: 08-samsung-now-bar-live-update*
*Context gathered: 2026-08-04*
