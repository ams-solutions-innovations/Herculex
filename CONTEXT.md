# Herculex Watch Sync Context

Date: 2026-08-02

## Recent Focus

We debugged active workout synchronization between the Flutter phone app and the native Wear OS app.

The user observed:
- Adding an exercise on the watch synced successfully to the phone.
- Adding an exercise on the phone did not sync to the watch.
- Earlier behavior looked like sync worked once, then stopped.

## Relevant Architecture

- Phone Flutter/Dart sync facade:
  - `lib/features/workouts/data/wear_workout_sync_service.dart`
  - `lib/features/workouts/presentation/workouts_providers.dart`
  - `lib/features/nutrition/data/wear_sync_service.dart`
- Phone Android bridge/listener:
  - `android/app/src/main/kotlin/com/ams/herculex/MainActivity.kt`
  - `android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt`
  - `android/app/src/main/kotlin/com/ams/herculex/sync/MobileWearSyncManager.kt`
  - `android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt`
- Watch native app:
  - `android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`
  - `android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt`
  - `android/wear/src/main/java/com/ams/herculex/workout/WorkoutViewModel.kt`
  - `android/wear/src/main/java/com/ams/herculex/workout/WorkoutStore.kt`
  - `android/wear/src/main/java/com/ams/herculex/MainActivity.kt`

There is also an older separate `herculex-wear/` tree. The active Gradle project includes `:wear` from `android/wear`, so focus there unless proven otherwise.

## Fixes Already Applied

- Phone listener now persists the latest watch workout snapshot so Flutter can consume it later if the Dart callback was not alive.
- Phone `MainActivity.dispatchPendingWorkout()` now replays stored watch state to Dart on `checkPendingWatchWorkout`.
- Phone outbound sync now skips short echo windows while applying remote watch state.
- Phone active session content changes now push a full session snapshot to the watch.
- Phone no longer sends JSON `"rpe": null`; it omits `rpe` when absent.
- Watch parser tolerates missing or null `rpe`.
- Phone outbound `pushActiveSessionToWatch()` marks `_lastSyncedSessionId` immediately at function entry to prevent duplicate `START` sends from racing async listeners.
- Phone payload now includes `startedAtEpochMs`.
- Phone `activeSessionProvider` listener no longer sends active-session snapshots; it only notifies the watch when the phone session ends.
- Watch `WorkoutStore` reads `startedAtEpochMs` on start/update.
- Watch `WorkoutViewModel` accepts a remote start epoch and uses it to set `sessionStartEpochMs` and elapsed time.
- Watch `SyncService.persistSession()` preserves the phone-provided start epoch when saving durable state.
- Watch `MainActivity` navigates to `active_workout` when an active session exists.
- Phone estimates `currentExerciseIndex` and `currentSetIndex` from the first incomplete set so the watch does not always highlight exercise 0.

## Verification

Commands run successfully:

```powershell
dart analyze lib\features\workouts\data\wear_workout_sync_service.dart lib\features\workouts\presentation\workouts_providers.dart
```

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
.\gradlew.bat :app:compileDebugKotlin :wear:compileDebugKotlin
```

Important environment note:
- The system `java` is Java 26.
- Gradle/Kotlin fails before project compilation with `IllegalArgumentException: 26`.
- Use Android Studio JBR/JDK 21 for Android builds.

## Critical Testing Note

Both APKs must be updated for sync testing:
- Phone app (`:app` / Flutter Android app)
- Watch app (`:wear`)

`flutter run` may update only the phone app. If the watch APK remains old, phone-to-watch sync may still appear broken.

