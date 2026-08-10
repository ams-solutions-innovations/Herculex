# Herculex Lessons

## Watch Sync Lessons

- Wear Data Layer sync must avoid bidirectional reuse of the same durable path. DataClient can notify the writer too, so phone-to-watch and watch-to-phone state paths must remain distinct.
- Use MessageClient for fast active workout updates and DataClient for durable fallback. The fast path gives immediate UI feedback; the durable path catches reconnects.
- Avoid multiple `fireImmediately` listeners pushing active workout snapshots at session creation. If two async pushes both compute `isStart`, duplicate start messages or empty-first snapshots can happen.
- Mark a session as synced before awaiting expensive snapshot construction or platform sends. This closes the `START` vs `UPDATE` race.
- Do not emit JSON keys with null values unless every parser handles `JSONObject.NULL`. The watch parser crashed on `rpe: null`, dropping the entire phone-to-watch update.
- Inbound remote snapshots should not be immediately echoed back. Use a short suppression window while applying remote state.
- Persist inbound watch session state on the Android phone side, not only in Dart callbacks. Wearable listener services can receive data while Flutter is not running.
- Start time is part of workout session state. Include `startedAtEpochMs` in sync payloads so the watch timer does not reset when adopting a phone-started workout.
- UI navigation and state sync are separate concerns. Watch updates can persist quietly, but an explicit/active session should navigate the user to the active workout screen when the app is open.
- Always install/update both phone and watch APKs when testing cross-device behavior.

## Local Build Lessons

- On this machine, default `java.exe` points to Java 26 and breaks Gradle/Kotlin script parsing.
- Use `C:\Program Files\Android\Android Studio\jbr` as `JAVA_HOME` for Android compile checks.
- The active Wear OS source is under `android/wear`, not the older separate `herculex-wear` tree.
- `flutter run` / `flutter build apk` does not build or install the Wear module on its own — `android/app/build.gradle.kts` hooks `:wear:assembleDebug`/`:wear:assembleRelease` onto the phone's own assemble tasks so the watch module can no longer go stale silently. (The obvious fix, `wearApp(project(":wear"))`, is deprecated in AGP and slated for removal in 9.0, and only ever supported the legacy Wear 1.x auto-push-install model anyway — it does nothing for a standalone Wear OS 3+ app like this one.) Installing the built APK onto the watch is still a separate `adb install` step.
- Two Gradle projects (`android/wear` and the now-retired `herculex-wear`) once declared the same `applicationId = "com.ams.herculex"`, so building/installing one from Android Studio silently overwrote the other on the watch. When phone→watch sync fails but food/macros still work, suspect a stale watch APK before suspecting the code — check `adb shell dumpsys package com.ams.herculex | grep lastUpdateTime` against when you last built the *correct* module.
- Phone→watch workout state travels on two channels that must both be implemented on the watch: DataClient `/herculex/state/active_workout` (durable) and MessageClient `/herculex_active_session_start|update|end` (fast path). A watch build missing `onMessageReceived` **or** the `MESSAGE_RECEIVED` intent-filter drops the fast path entirely and silently.
- MessageClient paths must start with the manifest's declared `pathPrefix` (`/herculex`) or they are silently undeliverable — no error, no log, the message just never arrives. `WearSyncPaths.kt` constants must stay byte-identical between `android/app` and `android/wear`.
- Gradle module `build/` directories get accidentally `git add`ed if nobody's watching (`herculex-wear/app/build/`, `android/wear/build/` both were, one containing a build from a previous app package name). `android/*/build/` and `android/build/` are now gitignored — if a build directory shows up in `git status`, gitignore it before committing, don't just move on.

