---
phase: 10-assisted-rep-tracking
plan: 03a
subsystem: wear-rep-capture
tags: [wear-os, kotlin, data-layer, sensors, rep-tracking]
requires:
  - "WearSyncPaths.kt duplicate-copy invariant (LESSONS.md:85)"
  - "WorkoutOngoingService (existing foregroundServiceType=health)"
  - "WearDataLayerSyncManager MessageClient transport"
provides:
  - "WearSyncPaths.MESSAGE_REP_CAPTURE_START / MESSAGE_REP_SAMPLES / MESSAGE_REP_CAPTURE_END (both copies)"
  - "ProvisionalRepCounter — non-authoritative on-wrist count + haptic tick"
  - "RepCaptureController — sensor lifecycle, 300 s ring buffer, 1 s batching, battery gate, 5-min cap"
  - "RepSensorGateway / RepMessageSender seams for JVM-testable capture"
  - "WorkoutOngoingService.provisionalRepCount StateFlow for SetLoggerScreen"
  - "PhoneWearListenerService.onRepMessageListener with in-memory hold-and-deliver"
  - "WearDataLayerSyncManager.sendMessageToAllNodesReporting (delivery signal, no disk queue)"
affects:
  - "10-03b (Dart half) parses the three payloads and must treat provisionalCount as non-authoritative"
  - "10-04 wires SetLoggerScreen display and the phone-side review sheet"
tech-stack:
  added: []
  patterns:
    - "Narrow injected gateways (RepSensorGateway/RepMessageSender) instead of raw SensorManager/MessageClient, so register/unregister balance is provable in a JVM test"
    - "Framework ActivityLifecycleCallbacks for the app-background teardown path, avoiding a lifecycle-process dependency"
    - "In-memory-only native hold for motion payloads, distinct from the SharedPreferences-backed pending stores"
key-files:
  created:
    - android/wear/src/main/java/com/ams/herculex/reps/ProvisionalRepCounter.kt
    - android/wear/src/main/java/com/ams/herculex/reps/RepCaptureController.kt
    - android/wear/src/test/java/com/ams/herculex/reps/ProvisionalRepCounterTest.kt
    - android/wear/src/test/java/com/ams/herculex/reps/RepCaptureControllerTest.kt
  modified:
    - android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt
    - android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt
    - android/wear/src/main/java/com/ams/herculex/workout/WorkoutOngoingService.kt
    - android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt
    - android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt
decisions:
  - "Injected a narrow RepSensorGateway rather than SensorManager itself: SensorManager.registerListenerImpl is unimplemented in the unit-test android.jar, so a fake SensorManager cannot exist and the listener-balance assertion (T-10-08) would have been untestable."
  - "Used Application.ActivityLifecycleCallbacks for the app-background stop rather than ProcessLifecycleOwner, because lifecycle-process would have been a new Gradle dependency this plan is not allowed to add."
  - "Added WearDataLayerSyncManager.sendMessageToAllNodesReporting instead of reusing sendRealtimeEvent: the latter's retry queue is SharedPreferences-backed and would have written raw motion samples to disk, violating REP-04/T-10-11."
  - "The phone-side hold is a dedicated in-memory queue, not the existing SharedPreferences pending stores, for the same reason."
  - "SetLoggerScreen was not modified; the provisional count is published as a StateFlow for 10-04 to render, keeping this plan inside its declared file set."
metrics:
  duration: ~20 min
  tasks: 4
  files_created: 4
  files_modified: 5
  tests_added: 16
  completed: 2026-08-14
---

# Phase 10 Plan 03a: Wear Rep Capture (Kotlin half) Summary

Raw accelerometer samples now leave the wrist: three `/herculex/reps/*` Data Layer paths mirrored byte-identically across both `WearSyncPaths.kt` copies, a deliberately-dumb provisional on-wrist counter that stays silent on a walk, a capture controller with provably balanced sensor lifecycle across five teardown paths, and phone-side routing that holds batches in memory when Flutter is detached.

## What Was Built

**Task 1 — the three paths (`3985246`).** `MESSAGE_REP_CAPTURE_START`, `MESSAGE_REP_SAMPLES` and `MESSAGE_REP_CAPTURE_END` added under the mandatory `/herculex` prefix. The wear copy was edited and then `cp`'d verbatim onto the phone copy, so `diff` is empty. The watch manifest's `MESSAGE_RECEIVED` intent-filter already declares `pathPrefix="/herculex"`, which covers `/herculex/reps/*` — **the manifest is byte-unchanged**, as is the permission list. No second foreground service.

**Task 2 — `ProvisionalRepCounter` (`9a41af7`).** Adaptive-threshold counting over the low-passed acceleration magnitude, gated on a *closed* trough → peak → trough cycle. Exposes only `onSample`/`count`/`reset`; holds no persistence, no MessageClient reference, no feature extraction. The absolute amplitude floor (2.5 m/s²) — not the adaptive term — is what makes walking count zero; an adaptive threshold alone would happily rescale down to whatever noise floor it was handed.

**Task 3 — `RepCaptureController` (`b88c462`).** `TYPE_LINEAR_ACCELERATION` at `SENSOR_DELAY_GAME` with an `TYPE_ACCELEROMETER` fallback, reported in the start payload's `sensorType`. 300 s in-memory ring buffer, ~1 s batches carrying a monotonic `seq`, hold-and-retry on send failure with order preserved. `start()` returns `StartRefusal.LowBattery` below 15 % and registers nothing; a clock-driven 5-minute cap flushes and reports `stoppedReason = "cap"`. Hosted by the existing health foreground service, with `onServiceDestroyed()` and an `ActivityLifecycleCallbacks`-driven background stop wired in `WorkoutOngoingService`.

**Task 4 — phone routing (`356eb39`).** `onMessageReceived` dispatches all three paths verbatim through a single `onRepMessageListener`. When Flutter is detached the payload is held in a process-lifetime in-memory queue (capped at 320 ≈ the watch ring-buffer depth) and drained in arrival order the moment a listener attaches. Nothing is parsed, reordered, coalesced or recomputed; `provisionalCount` passes through untouched.

## Verification

| Check | Result |
|---|---|
| `:wear:testDebugUnitTest :app:compileDebugKotlin` | BUILD SUCCESSFUL |
| `ProvisionalRepCounterTest` | 4 tests, 0 failures |
| `RepCaptureControllerTest` | 12 tests, 0 failures |
| `diff` between the two `WearSyncPaths.kt` copies | empty |
| `/herculex/reps/` constants per copy | exactly 3 |
| Manifest `pathPrefix` | `/herculex` — covers the new paths, file unchanged |
| `grep -c "startForegroundService\|foregroundServiceType" RepCaptureController.kt` | 0 |
| New `SharedPreferences`/`openFileOutput` calls in `PhoneWearListenerService.kt` | 0 (one added line is a comment explaining the deliberate avoidance) |
| Full wear suite | green |

`RepCaptureControllerTest` covers all six mandated cases plus five more: normal stop, service destroy without a prior stop, app background mid-capture, the 14 % refusal (0 registrations), the 5-minute cap (flushed, `stoppedReason == "cap"`, one unregister), double-`stop()` idempotence, monotonic `seq`, ordered replay of held batches, absence of any authoritative-looking count key on the end payload, missing-sensor refusal, and double-`start()` refusal. Cases 4 and 5 are the automated stand-ins for UAT rows 6 and 9.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SensorManager` cannot be faked in a JVM unit test**
- **Found during:** Task 3
- **Issue:** The plan specifies a constructor-injected `SensorManager` and a "fake `SensorManager` that counts `registerListener`/`unregisterListener`". `SensorManager` is an abstract framework class whose `registerListenerImpl` is a throwing stub in the unit-test `android.jar`, so no such fake can exist. Written literally, the T-10-08 listener-balance assertion — the whole point of the test — would have been unwritable.
- **Fix:** Introduced a narrow `RepSensorGateway` interface (`registerListener`/`unregisterListener`) injected into the controller, with `AndroidRepSensorGateway(SensorManager)` as the production implementation. The test's `FakeSensorGateway` counts exactly the two calls the plan asks about.
- **Files modified:** `RepCaptureController.kt`, `RepCaptureControllerTest.kt`
- **Commit:** `b88c462`

**2. [Rule 3 - Blocking] No delivery signal for batch send, and the existing retry queue writes to disk**
- **Found during:** Task 3
- **Issue:** `WearDataLayerSyncManager.sendMessageToAllNodes` returns `Unit` and swallows failures, so hold-and-retry had nothing to branch on. The one existing Boolean-returning send, `sendRealtimeEvent`, enqueues through `WearRealtimeQueueStore` — SharedPreferences-backed — which would have persisted raw motion samples to disk, violating REP-04 and T-10-11.
- **Fix:** Added `sendMessageToAllNodesReporting(path, payload): Boolean` to `WearDataLayerSyncManager` — purely additive, reuses the same `MessageClient`/`NodeClient`, no second client, no disk. Existing callers and behaviour are untouched.
- **Files modified:** `WearDataLayerSyncManager.kt`, `WorkoutOngoingService.kt`
- **Commit:** `b88c462`

**3. [Rule 2 - Missing critical] Sample delivery moved off the main looper**
- **Found during:** Task 3
- **Issue:** The batch send is a blocking Data Layer call. Delivered on the default (main) looper it would have blocked the watch UI roughly once per second while the set logger is on screen.
- **Fix:** `AndroidRepSensorGateway` registers the listener against a dedicated `HandlerThread`, quit in `unregisterListener()` so the thread is torn down on every one of the five paths too.
- **Commit:** `b88c462`

**4. [Rule 3 - Blocking] `ProcessLifecycleOwner` would have been a new dependency**
- **Found during:** Task 3
- **Issue:** The plan suggests a `ProcessLifecycleOwner`/`DefaultLifecycleObserver` `onStop` observer "or the wear-equivalent lifecycle callback already used in `WorkoutOngoingService`". The service has no lifecycle callbacks, and `androidx.lifecycle:lifecycle-process` is not on the wear module's classpath — adding it would contradict the threat model's `T-10-SC: this plan adds no Gradle dependency`.
- **Fix:** Used the framework's own `Application.ActivityLifecycleCallbacks`, counting started activities and stopping capture when the count reaches zero. Registered lazily on first capture, unregistered in `onDestroy`.
- **Commit:** `b88c462`

### Intentional Scope Decisions

- **`SetLoggerScreen.kt` was not modified.** It is absent from the plan's `files_modified` list, and the phase's live-counter UI belongs to 10-04. The provisional count is published as `WorkoutOngoingService.provisionalRepCount: StateFlow<Int>` for that plan to render and label "provisional".
- **REP-02 was not marked complete.** It requires the user to choose the sensor source, with the phone accelerometer used only under an explicit placement — the phone half lands in 10-03b/10-04. Marking it now would be false. REP-04 was already checked off by 10-01 and this plan upholds it (no sample payload reaches disk on either device).

## Known Stubs

None. Every path implemented here is live and exercised by a test; the only unwired end is `onRepMessageListener`, whose Dart consumer is 10-03b's declared job.

## Threat Flags

None. No new network endpoint, auth path, file access pattern or schema change was introduced. The registered threats T-10-08 through T-10-11 are each mitigated and asserted:

| Threat | Mitigation | Evidence |
|---|---|---|
| T-10-08 (leaked listener) | balanced register/unregister on all five paths | `RepCaptureControllerTest` cases 1–3, 6 |
| T-10-09 (spoofed authority) | count travels only as `provisionalCount`, never recomputed on the phone | end-payload key assertion; `PhoneWearListenerService` forwards verbatim |
| T-10-10 (battery DoS) | 15 % refusal registering nothing, 5-minute clock cap | `RepCaptureControllerTest` cases 4–5 |
| T-10-11 (sample disclosure) | in-memory hold only, no disk write | added-line grep shows only a comment matching `SharedPreferences` |

## Notes for the Next Plan

- **10-03b must import, never redeclare, the payload keys.** `captureId`, `seq`, `sensorType`, `samples[{tMs,x,y,z}]`, `endedAtMs`, `batchCount`, `stoppedReason`, `provisionalCount` are emitted exactly as specified in the plan's `<interfaces>` block.
- **Attach by assigning `PhoneWearListenerService.onRepMessageListener`** — the setter drains the held queue itself, in order, before any live message. Set it to `null` on detach so batches are held rather than thrown at a dead engine.
- **`stoppedReason` values** are `"user" | "cap" | "battery" | "background" | "destroy"`. Anything other than `"user"` means the set's capture is incomplete and should degrade toward the `manual`/`countOnly` states rather than proposing confidently.
- Watch APK staleness still looks exactly like a sync bug — check `adb shell dumpsys package com.ams.herculex | grep lastUpdateTime` before debugging transport (LESSONS.md:83).

## Self-Check: PASSED

All four created files exist on disk; all five modified files carry the changes. All four task commits (`3985246`, `9a41af7`, `b88c462`, `356eb39`) are present in `git log`.
