---
phase: 10-assisted-rep-tracking
plan: 03a
type: execute
wave: 1
depends_on: []
files_modified:
  - android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt
  - android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt
  - android/wear/src/main/java/com/ams/herculex/reps/ProvisionalRepCounter.kt
  - android/wear/src/main/java/com/ams/herculex/reps/RepCaptureController.kt
  - android/wear/src/main/java/com/ams/herculex/workout/WorkoutOngoingService.kt
  - android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt
  - android/wear/src/test/java/com/ams/herculex/reps/ProvisionalRepCounterTest.kt
  - android/wear/src/test/java/com/ams/herculex/reps/RepCaptureControllerTest.kt
autonomous: true
requirements: [REP-02, REP-04]
user_setup: []

must_haves:
  truths:
    - "Both WearSyncPaths.kt copies are byte-identical and every new path starts with /herculex, so the MESSAGE_RECEIVED intent-filter can deliver it"
    - "Sensor listener registrations and unregistrations balance across all five teardown paths: set end, service destroy, app background, battery refusal and the 5-minute cap"
    - "Capture refuses to start below 15 % battery and returns a typed reason rather than starting and failing silently"
    - "The provisional Kotlin count is transported only as an explicitly non-authoritative provisionalCount field and is never persisted"
    - "No second foreground service and no new manifest permission are introduced"
    - "A sample batch arriving while Flutter is not running is held natively and delivered on attach, never dropped"
  artifacts:
    - path: "android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt"
      provides: "the three new capture message paths on the watch side"
      contains: "MESSAGE_REP_CAPTURE_END"
    - path: "android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt"
      provides: "the byte-identical phone-side twin"
      contains: "MESSAGE_REP_CAPTURE_END"
    - path: "android/wear/src/main/java/com/ams/herculex/reps/RepCaptureController.kt"
      provides: "sensor lifecycle, 300 s ring buffer, 1 s batching, battery gate, 5-minute cap and balanced teardown"
      contains: "unregisterListener"
    - path: "android/wear/src/main/java/com/ams/herculex/reps/ProvisionalRepCounter.kt"
      provides: "the simple live on-wrist counter driving the display and haptics only"
      contains: "class ProvisionalRepCounter"
    - path: "android/wear/src/test/java/com/ams/herculex/reps/RepCaptureControllerTest.kt"
      provides: "balanced register/unregister across five paths, plus fake-clock cap and fake-battery gate coverage"
      contains: "registerListener"
    - path: "android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt"
      provides: "routing of the three new paths to Dart with native hold-and-deliver on attach"
      contains: "MESSAGE_REP_SAMPLES"
  key_links:
    - from: "android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt"
      to: "android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt"
      via: "byte-identical duplicate — a path added to one and not the other fails silently with no error and no log (LESSONS.md:85)"
      pattern: "MESSAGE_REP_(CAPTURE_START|SAMPLES|CAPTURE_END)"
    - from: "android/wear/src/main/java/com/ams/herculex/workout/WorkoutOngoingService.kt"
      to: "android/wear/src/main/java/com/ams/herculex/reps/RepCaptureController.kt"
      via: "the existing foregroundServiceType=health service hosts capture and calls stop() from onDestroy and from the lifecycle background callback"
      pattern: "RepCaptureController"
    - from: "android/wear/src/main/java/com/ams/herculex/reps/RepCaptureController.kt"
      to: "android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt"
      via: "MessageClient sends on the three MESSAGE_REP_* constants"
      pattern: "WearSyncPaths\\.MESSAGE_REP_"
---

<objective>
Get raw accelerometer samples off the wrist and onto the phone bridge: three new Data Layer paths mirrored across both `WearSyncPaths.kt` copies, a provisional on-wrist counter for live feedback and haptics, a capture controller with a ring buffer that survives disconnect, and phone-side routing that holds batches when Flutter is not attached.

Purpose: this is the Kotlin half of what was one over-large plan. It is verified entirely by Gradle and a byte-diff — no Dart, no `flutter test`, no pubspec change. The Dart half is 10-03b.
Output: three `/herculex/reps/*` paths present and identical in both copies, `RepCaptureController.kt` with provably balanced listener lifecycle, `ProvisionalRepCounter.kt` that does not buzz on a walk, and `PhoneWearListenerService.kt` routing the new paths through.

Split from the original 10-03 because that plan spanned two languages, three build systems and eight work items. This half depends on nothing: the Kotlin code never references the Dart detector.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/10-assisted-rep-tracking/10-CONTEXT.md
@LESSONS.md
</context>

<interfaces>
<!-- The three constants this plan publishes into BOTH copies of WearSyncPaths.kt -->
```kotlin
const val MESSAGE_REP_CAPTURE_START = "/herculex/reps/capture_start"
const val MESSAGE_REP_SAMPLES       = "/herculex/reps/samples"
const val MESSAGE_REP_CAPTURE_END   = "/herculex/reps/capture_end"
```

<!-- Wire payloads. 10-03b parses exactly these keys; changing one breaks the other plan. -->
```
MESSAGE_REP_CAPTURE_START : { captureId: String, exerciseSlug: String, sensorType: String,
                              startedAtMs: Long }
MESSAGE_REP_SAMPLES       : { captureId: String, seq: Int, sensorType: String,
                              samples: [ { tMs: Long, x: Float, y: Float, z: Float } ] }
MESSAGE_REP_CAPTURE_END   : { captureId: String, endedAtMs: Long, batchCount: Int,
                              stoppedReason: String,          // "user" | "cap" | "battery" | "background" | "destroy"
                              provisionalCount: Int }          // NON-AUTHORITATIVE, from ProvisionalRepCounter
```
`provisionalCount` exists solely so the phone can detect a >1-rep disagreement with the Dart detector and drop the confidence band one step (10-CONTEXT "Where detection runs"). It is never the proposed count and is never persisted.

<!-- Constraints from LESSONS.md:83-86 -->
- MessageClient paths MUST start with `/herculex`; the watch manifest matches on that `pathPrefix` and anything outside it is undeliverable with no error and no log.
- Both `WearSyncPaths.kt` copies must stay byte-identical or the fast path drops silently.
- A stale watch APK looks exactly like a sync bug — check `adb shell dumpsys package com.ams.herculex | grep lastUpdateTime` before debugging transport.
</interfaces>

<tasks>

<task type="auto">
  <name>Task 1: Add the three capture paths to both WearSyncPaths.kt copies</name>
  <read_first>
    android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt (the whole file — the existing constants and the comment explaining why phone-to-watch and watch-to-phone durable paths stay distinct)
    android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt (the byte-identical twin)
    LESSONS.md (lines 83-86 — the `/herculex` prefix rule and the silent-drop failure mode)
    android/wear/src/main/AndroidManifest.xml (the MESSAGE_RECEIVED intent-filter `pathPrefix`)
  </read_first>
  <files>android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt, android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt</files>
  <action>
Add `MESSAGE_REP_CAPTURE_START = "/herculex/reps/capture_start"`, `MESSAGE_REP_SAMPLES = "/herculex/reps/samples"` and `MESSAGE_REP_CAPTURE_END = "/herculex/reps/capture_end"` to **both** copies, in the same position and with identical formatting and comments, so `diff` between the two files stays empty. Apply the edit to one file and copy it verbatim to the other rather than hand-typing it twice.

The `/herculex` prefix is mandatory: the watch manifest's `MESSAGE_RECEIVED` intent-filter matches on it, and anything outside the prefix is undeliverable with no error and no log entry (LESSONS.md:85). Confirm the existing `pathPrefix` in `android/wear/src/main/AndroidManifest.xml` already covers `/herculex` and therefore covers `/herculex/reps/*` without a manifest change; if it declares a narrower prefix, widen it to `/herculex` rather than adding a second filter.

Add no other path constants and change no existing ones.
  </action>
  <verify>
    <automated>diff android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt &amp;&amp; grep -c '"/herculex/reps/' android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt | grep -qx 3</automated>
  </verify>
  <done>`diff` between the two copies is empty; each file contains exactly three `/herculex/reps/` constants; the manifest `pathPrefix` covers them.</done>
</task>

<task type="auto">
  <name>Task 2: Implement the provisional on-wrist rep counter</name>
  <read_first>
    android/wear/src/main/java/com/ams/herculex/workout/WorkoutOngoingService.kt (line 23 — the existing `foregroundServiceType="health"` service that will host capture; do NOT add a second foreground service)
    .planning/phases/10-assisted-rep-tracking/10-CONTEXT.md ("Where detection runs" — the provisional counter is deliberately simple and never authoritative; "Claude's Discretion" allows it to live in the service or a collaborator class)
    android/wear/src/test/java/com/ams/herculex/ (the existing wear unit-test layout and JUnit idiom to match)
  </read_first>
  <files>android/wear/src/main/java/com/ams/herculex/reps/ProvisionalRepCounter.kt, android/wear/src/test/java/com/ams/herculex/reps/ProvisionalRepCounterTest.kt</files>
  <action>
Create `ProvisionalRepCounter.kt` — the live on-wrist counter driving the displayed number and the haptic tick, and nothing else. Adaptive-threshold cycle counting over the incoming magnitude stream, same broad shape as 10-02's Dart detector but deliberately simpler: **no calibration, no feature extraction, no confidence model, no per-rep bookkeeping.** Expose `fun onSample(tMs: Long, x: Float, y: Float, z: Float): Boolean` returning true on the tick where a rep completed (so the caller fires the haptic), plus `val count: Int` and `fun reset()`.

Its output is **never sent to the phone as an authoritative count and never persisted.** It travels only as the `provisionalCount` field on `MESSAGE_REP_CAPTURE_END`, and 10-03b treats that field as non-authoritative by contract.

Keep a closed trough-peak-trough cycle requirement with an amplitude gate and a refractory floor, for the same reason as the Dart detector: counting bare peaks is what makes walking register as reps.

Create `ProvisionalRepCounterTest.kt` in `android/wear/src/test/`: a synthetic clean-cycle stream of 8 cycles yields a count within ±1 of 8; a synthetic walking-noise stream (low-amplitude, ~500 ms period) yields **exactly 0**, so the watch does not buzz on the walk to the water fountain; `reset()` returns `count` to 0.
  </action>
  <verify>
    <automated>JAVA_HOME="C:/Program Files/Android/Android Studio/jbr" ./gradlew.bat :wear:testDebugUnitTest --tests "*ProvisionalRepCounterTest*"</automated>
  </verify>
  <done>`ProvisionalRepCounterTest` passes; the walking-noise case counts exactly 0; the class exposes only `onSample`/`count`/`reset` and holds no persistence, no MessageClient reference and no feature extraction.</done>
</task>

<task type="auto">
  <name>Task 3: Implement RepCaptureController with balanced listener lifecycle, battery gate and hard cap</name>
  <read_first>
    android/wear/src/main/java/com/ams/herculex/workout/WorkoutOngoingService.kt (the whole file — its lifecycle callbacks, `onDestroy`, and how it is started/stopped; capture is hosted here)
    android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt (how the watch sends on MessageClient — reuse this, do not open a second client)
    android/wear/src/main/java/com/ams/herculex/reps/ProvisionalRepCounter.kt (Task 2 output — fed from the same sample callback)
    android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt (Task 1 output — the three constants and their payload shapes)
    .planning/phases/10-assisted-rep-tracking/10-CONTEXT.md ("Sensor and sampling" and "Interruption and battery handling" — the 15 % gate, the 5-minute cap, and the three mandated unregister paths)
  </read_first>
  <files>android/wear/src/main/java/com/ams/herculex/reps/RepCaptureController.kt, android/wear/src/main/java/com/ams/herculex/workout/WorkoutOngoingService.kt, android/wear/src/test/java/com/ams/herculex/reps/RepCaptureControllerTest.kt</files>
  <action>
Create `RepCaptureController.kt` taking `SensorManager`, a battery-level supplier and a clock as **constructor-injected collaborators** (not `System.currentTimeMillis()` or a static `BatteryManager` lookup) so the cap and the gate are fake-testable.

Sensor lifecycle: register `TYPE_LINEAR_ACCELERATION` at `SENSOR_DELAY_GAME`; fall back to `TYPE_ACCELEROMETER` when the linear sensor is absent, and report which was used in the `MESSAGE_REP_CAPTURE_START` payload's `sensorType`. No new manifest permission is required for either — accelerometer is not a `BODY_SENSORS` sensor and `HIGH_SAMPLING_RATE_SENSORS` only applies above 200 Hz.

Buffering and transport: maintain a 300-second in-memory ring buffer of raw samples; batch roughly 1 s of samples per `MESSAGE_REP_SAMPLES` message carrying `captureId`, a monotonic `seq`, `sensorType` and the sample array, so the phone can detect and report gaps rather than silently concatenating across a dropout. On send failure keep the batch in the ring buffer and retry on the next connectivity callback. On stop, emit `MESSAGE_REP_CAPTURE_END` with `endedAtMs`, `batchCount`, `stoppedReason` and `provisionalCount` (read from `ProvisionalRepCounter.count`), after flushing everything still buffered.

Gates and caps: `start()` returns a typed `StartRefusal.LowBattery` and registers **no** listener when the battery supplier reports below 15 %. A 5-minute hard cap driven by the injected clock stops capture, flushes what was collected, and emits `stoppedReason = "cap"`.

**Teardown — all five paths must unregister exactly once:** normal set end (`stop(reason = "user")`), the 5-minute cap (`stoppedReason = "cap"`), battery refusal (never registers, so the count trivially balances), service `onDestroy()`, and **app background**. For the background path, register a `ProcessLifecycleOwner`/`DefaultLifecycleObserver` `onStop` observer (or the wear-equivalent lifecycle callback already used in `WorkoutOngoingService`) that calls `stop(reason = "background")`. 10-CONTEXT:98 mandates all three of set end, service stop and app background; the cap and the refusal fall out of the same accounting. `stop()` must be idempotent — a second call unregisters nothing and does not double-send `MESSAGE_REP_CAPTURE_END`.

Hook the controller into `WorkoutOngoingService`: capture starts only on an explicit start command for a specific set — never on session start, never automatically. Expose the provisional count to `SetLoggerScreen` for display and label the watch string "provisional" there (10-04 owns the phone-side wording).

Create `RepCaptureControllerTest.kt` using a **fake `SensorManager`** that counts `registerListener` and `unregisterListener` invocations, a fake battery supplier and a fake clock. Assert: (1) after a normal `stop("user")`, register count == unregister count == 1; (2) same balance after `onDestroy()` without a prior `stop()`; (3) same balance after the app-background lifecycle callback fires mid-capture; (4) with battery at 14 %, `start()` returns `StartRefusal.LowBattery` and `registerListener` was never called, so both counts are 0; (5) advancing the fake clock past 5 minutes stops capture, unregisters exactly once, and emits `stoppedReason == "cap"` with the buffered batches flushed; (6) calling `stop()` twice still yields exactly one unregister and one `MESSAGE_REP_CAPTURE_END`. Cases 4 and 5 are the automated coverage for UAT rows 6 and 9, which are otherwise hardware-only.
  </action>
  <verify>
    <automated>JAVA_HOME="C:/Program Files/Android/Android Studio/jbr" ./gradlew.bat :wear:testDebugUnitTest --tests "*RepCaptureControllerTest*"</automated>
  </verify>
  <done>All six `RepCaptureControllerTest` cases pass; register and unregister counts balance across set end, service destroy, app background, battery refusal and the 5-minute cap; `stop()` is idempotent; `grep -c "startForegroundService\|foregroundServiceType" android/wear/src/main/java/com/ams/herculex/reps/RepCaptureController.kt` is 0 — no second foreground service.</done>
</task>

<task type="auto">
  <name>Task 4: Route the three paths through PhoneWearListenerService with native hold-and-deliver</name>
  <read_first>
    android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt (the whole file — where inbound watch messages land and how they reach the Flutter bridge)
    android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt (Task 1 output)
    LESSONS.md (line 72 — the persistence lesson: a message arriving while Flutter is not running must be held natively and delivered on attach, not dropped)
  </read_first>
  <files>android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt</files>
  <action>
Extend the inbound `onMessageReceived` dispatch with cases for `WearSyncPaths.MESSAGE_REP_CAPTURE_START`, `MESSAGE_REP_SAMPLES` and `MESSAGE_REP_CAPTURE_END`, forwarding each payload verbatim to Dart through the existing bridge channel — reuse the mechanism the current workout messages use rather than adding a second channel.

Follow the persistence lesson in LESSONS.md:72: a sample batch that arrives while Flutter is not running must be **held natively** in the same pending-message store the existing paths use and delivered on attach, not dropped. A dropped mid-set batch is indistinguishable at the Dart layer from a Bluetooth dropout, and both must surface as a `seq` gap rather than as silent concatenation — so preserve `seq` exactly as received and never reorder or coalesce held batches.

Forward `provisionalCount` on the capture-end payload untouched and unlabelled as anything but provisional. Do not compute, adjust or substitute a rep count anywhere in this file.

Do not persist any sample payload to disk, SharedPreferences or a database — the native hold is in-memory for the lifetime of the process only, matching how the existing pending workout messages are held.
  </action>
  <verify>
    <automated>JAVA_HOME="C:/Program Files/Android/Android Studio/jbr" ./gradlew.bat :app:compileDebugKotlin</automated>
  </verify>
  <done>`:app:compileDebugKotlin` succeeds; all three `MESSAGE_REP_*` constants are referenced in `PhoneWearListenerService.kt`; `grep -n "SharedPreferences\|getSharedPreferences\|openFileOutput" android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt` shows no new sample-writing call.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|--------------|
| Watch → phone Data Layer | Raw motion samples cross the BT pair here. They stay within the paired device pair and never reach a server. |
| Sensor subsystem → app | A leaked listener registration keeps the accelerometer running after the set, draining battery and capturing motion the user did not consent to. |
| Provisional count → phone | An unlabelled provisional count could be mistaken for the authoritative one. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|------------------|
| T-10-08 | Information Disclosure | `RepCaptureController.kt` listener lifecycle | mitigate | Balanced register/unregister across all five teardown paths, asserted by `RepCaptureControllerTest` with a fake `SensorManager` (Task 3); this is the automated counterpart to UAT row 7. |
| T-10-09 | Spoofing (of authority) | `MESSAGE_REP_CAPTURE_END` payload | mitigate | The watch count travels only as `provisionalCount`, documented non-authoritative in both `WearSyncPaths` payload contract and 10-03b's parser; the phone never uses it as the proposed count (Tasks 1, 3, 4). |
| T-10-10 | Denial of Service (battery) | capture start path | mitigate | Hard refusal below 15 % battery with no listener registered, and a 5-minute clock-driven cap, both fake-tested (Task 3). |
| T-10-11 | Information Disclosure | `PhoneWearListenerService.kt` | mitigate | Native hold is in-memory only for the process lifetime; no sample payload is written to disk, SharedPreferences or a database (Task 4). |
| T-10-SC | Tampering | package installs | accept | This plan adds no Gradle or package-manager dependency; `sensors_plus` belongs to 10-03b. |
</threat_model>

<verification>
- `JAVA_HOME="C:/Program Files/Android/Android Studio/jbr" ./gradlew.bat :wear:testDebugUnitTest :app:compileDebugKotlin` — Gradle needs Android Studio's JBR, not the system JDK 26 (10-CONTEXT risks).
- `diff android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt` — must be empty.
- `grep -n "herculex" android/wear/src/main/AndroidManifest.xml` — the `pathPrefix` filter covers the new `/herculex/reps/*` paths.
- `grep -rn "foregroundServiceType\|<uses-permission" android/wear/src/main/AndroidManifest.xml` — unchanged from before the phase; no second service, no new permission.
</verification>

<success_criteria>
- Both `WearSyncPaths.kt` copies are byte-identical and all three new paths start with `/herculex`.
- No new foreground service and no new manifest permission were added.
- The provisional watch counter's output crosses the bridge only as `provisionalCount` and is never persisted.
- Listener register/unregister counts balance across set end, service destroy, app background, battery refusal and the 5-minute cap, proven by `RepCaptureControllerTest`.
- Capture is refused below 15 % battery with no listener registered; the 5-minute cap flushes and reports `stoppedReason = "cap"`.
- A batch arriving while Flutter is detached is held natively with its `seq` intact and delivered on attach.
</success_criteria>

<output>
Create `.planning/phases/10-assisted-rep-tracking/10-03a-SUMMARY.md` when done
</output>
</content>
