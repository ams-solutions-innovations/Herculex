# Herculex Lessons

## Cloud Sync (RB-02) Lessons — 2026-08-13

- **A pulled row and a locally-edited row look identical to a SQLite
  trigger.** `_applyPulledRow` writes a pulled row with a plain
  `INSERT ... ON CONFLICT DO UPDATE`, which fires the same outbox trigger a
  real local edit would. This left a phantom `pending_sync_ops` entry after
  every first-time pull, which then made the tombstone logic's local-wins
  check treat a freshly-arrived row as having an unpushed edit — silently
  blocking deletes for it. Any "apply a remote write via the same code path
  as a local write" design needs to purge its own echo, symmetrically on
  *every* write direction (delete already did this; upsert didn't). Caught
  only by the live round trip, not by any unit test against the fake — the
  fake didn't reproduce the trigger's behavior faithfully enough. Lesson:
  when a fake backend exists specifically to keep tests fast, periodically
  run the real thing anyway, because faithfulness gaps in the fake are
  exactly where bugs hide.
- **`flutter_test` blocks all real HTTP by default.** `TestWidgetsFlutterBinding`
  installs a `_MockHttpOverrides` that fails every request with a fake 400,
  specifically to stop widget tests from accidentally hitting the network.
  A test that *needs* a real request (ours does — it's the whole point) must
  `HttpOverrides.global = null;` after `ensureInitialized()`. It's set once
  at binding init, not reset per test, so doing this once in `main()` is
  enough for the whole file.
- **Two devices seeded from the same bundled assets can legitimately produce
  the same local autoincrement id for their first custom row.** Don't assert
  id divergence as proof that FK resolution worked — assert the *resolved
  relationship* (child's FK column equals the parent's actual local id),
  which holds regardless of whether the raw numbers happen to match.
- **Supabase dashboard "Add user" → "Create new user" needs "Auto Confirm
  User" checked**, or the account exists with a password set but
  `signInWithPassword` still rejects it (unconfirmed email). Fixable after
  the fact without recreating the user: `update auth.users set
  email_confirmed_at = now() where email = ...` (note: `confirmed_at` itself
  is a generated column, can't be set directly). A wrong/mistyped password
  can similarly be forced via `pgcrypto`:
  `update auth.users set encrypted_password = extensions.crypt('pw',
  extensions.gen_salt('bf')) where email = ...` — any valid bcrypt hash
  works, GoTrue reads the cost from the hash itself.
- **Realtime's first channel subscription on a fresh client can take several
  seconds** (websocket handshake + Realtime's own RLS authorization round
  trip). A 2-second warm-up before asserting hint delivery was too tight;
  5 seconds with a 30-second overall timeout was reliable. Keep this kind of
  assertion in its own opt-in test, isolated from the rest of a suite — it's
  the one piece of sync verification that's inherently timing-dependent
  rather than logic-dependent.
- **Proving RLS needs two real, distinct authenticated accounts** — there is
  no way to fake "a different user" when `user_id` has a foreign key to
  `auth.users`. One account can prove push/pull/delete; it cannot prove
  isolation.
- **The Supabase dashboard's "Total: N users (estimated)" footer is not a
  live count.** It comes from a stale `pg_class.reltuples` estimate and can
  read wildly wrong (10) right after a table's first writes when the real
  count (verified via SQL) is 1. Don't trust it for anything; query
  `auth.users` directly when the actual number matters.
- **Real device/emulator testing still isn't avoidable for everything.**
  Three things — sign-in actually starting the sync service, the Profile
  badge rendering, and offline/reconnect behavior — are about the app's own
  wiring, not the sync engine, and nothing headless can reach them. Extensive
  automated coverage narrows what manual testing is *for*; it doesn't
  eliminate the need for it.

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

