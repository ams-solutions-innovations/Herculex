# Herculex Wear Sync Smoke Test

Last updated: July 31, 2026

## Current sync shape

The current app uses two layers at once:

1. Legacy Flutter -> native bridge on channel `com.example.herculex/wear`
2. Newer native Android/Wear data-layer sync managers

That means sync is functional in principle, but there is still overlap.

## What is actively synced today

### Mobile -> Wear

- Macro totals through `syncMacros`
- Workout templates through `syncWorkouts`
- Exercise catalog through `syncCatalog`
- Active workout session state through `syncActiveSession`
- Workout end through `endWorkoutOnWatch`

### Wear -> Mobile

- Watch-started workout session payloads
- Watch session updates
- Watch session end
- Explicit watch sync requests

## Important caveat

The Flutter app still primarily drives the older sync path:

- [wear_sync_service.dart](../lib/features/nutrition/data/wear_sync_service.dart)
- [wear_workout_sync_service.dart](../lib/features/workouts/data/wear_workout_sync_service.dart)
- [nutrition_providers.dart](../lib/features/nutrition/presentation/nutrition_providers.dart)
- [workouts_providers.dart](../lib/features/workouts/presentation/workouts_providers.dart)

The new native offline-first managers are present, but they are not yet the only source of truth.

## Test setup

Before testing:

1. Install the mobile app on the phone.
2. Install the wear app on the watch.
3. Pair the watch with the phone.
4. Open Herculex once on both devices.
5. Keep both devices awake during the first pass.

## Smoke test checklist

### 1. Macro sync to watch

On phone:

1. Open Nutrition.
2. Log a food item or otherwise change calories, protein, carbs, or fats.

Expected on watch:

- Nutrition/macros view updates.
- Macros tile updates.
- Macro complications reflect the new totals.

If it fails:

- Open the watch app manually.
- Then reopen the phone app.
- Then trigger a workout sync request path by entering the workouts area on both sides.

### 2. Template sync to watch

On phone:

1. Open workouts.
2. Ensure templates are visible.
3. Wait a few seconds after the screen loads.

Expected on watch:

- Workout list shows synced templates from phone.

If it fails:

- Reopen workouts on phone.
- Reopen workouts on watch.

### 3. Exercise catalog sync to watch

On phone:

1. Open the exercise catalog path used by workouts.
2. Let the app settle for a few seconds.

Expected on watch:

- Catalog-backed exercise names appear correctly when adding or viewing exercises.

### 4. Phone-started workout to watch

On phone:

1. Start a workout.
2. Add at least one exercise if needed.
3. Log one set.

Expected on watch:

- Active workout appears on watch.
- Exercise names and sets mirror over.
- Later phone edits continue updating the active session.

### 5. Watch-started workout to phone

On watch:

1. Start a workout from the watch.
2. Log at least one set.

Expected on phone:

- A workout notification appears.
- Opening the phone app brings you into the active workout state.
- Session data is written into the phone-side workout session.

### 6. Watch set update to phone

On watch:

1. Update reps or weight for a set.

Expected on phone:

- The active phone workout reflects the changed set values.

### 7. Finish workout on watch

On watch:

1. Finish the workout.

Expected on phone:

- The active session closes.
- The phone notification clears.

### 8. Finish workout on phone

On phone:

1. Finish the active workout.

Expected on watch:

- Active session is closed on watch.

## Reconnection test

### 9. Temporary disconnect

1. Start an active workout with both devices connected.
2. Turn off Bluetooth on one side or move devices temporarily out of range.
3. While disconnected, make one or two changes.
4. Reconnect the devices.

Expected:

- Persistent state should eventually resync.
- Queued transient events should flush after reconnection.

Reality check:

- Because the old bridge is still the dominant app path, reconnection behavior may be mixed depending on which action you triggered.

## What to log during testing

Record these for each failed case:

- Which direction failed: phone -> watch or watch -> phone
- Whether the failure was macros, templates, catalog, active workout, or finish event
- Whether reopening either app fixes it
- Whether reconnecting Bluetooth/Wi-Fi fixes it
- Whether only the UI failed or the underlying workout state was wrong too

## Current confidence by area

- Macros sync: medium
- Template/catalog sync: medium
- Active workout phone -> watch: medium
- Active workout watch -> phone: medium
- Offline-first reconnect behavior: low to medium

## Recommended next cleanup

After smoke testing, the best technical cleanup is:

1. Choose one sync path as authoritative.
2. Migrate Flutter callers from the legacy bridge methods onto the new native state/event model.
3. Remove duplicated state propagation once the new path passes device testing.
