# Herculex Wear Sync Smoke Test

Last updated: August 8, 2026

## Sync Contract

Durable state uses DataClient. MessageClient is only a fast path for the same latest snapshot or a FIFO command path.

Versioned state payloads use:

- `schemaVersion`
- `entity`
- `entityId`
- `revision`
- `origin`
- `updatedAtEpochMs`
- `payload`

Workout payloads must preserve:

- exercise identity: `catalogExerciseId`, `slug`, `name`, `equipmentVariant`
- planned sets: `wireId`, `setIndex`, `setType`, `isWarmup`, target reps/weight, `setTypeMetaJson`
- actual sets: weight, reps, half-point `rpe`, `setType`, `isWarmup`, `setTypeMetaJson`, `bodyweightKg`, `chainsKg`, `completedAtEpochMs`
- cursor: `currentExerciseIndex`, `currentSetIndex`
- `startedAtEpochMs`

Fasting payloads must preserve:

- `hasActiveFast`
- `startedAtEpochMs`
- `targetSeconds`
- `phoneSessionId`
- `endedAtEpochMs`
- `completed`

## Test Setup

1. Build both APKs from the same source state.
2. Install the phone APK on the phone and the wear APK on the watch.
3. Pair devices and open Herculex once on both sides.
4. Keep logcat open with the `WearSync` and `PhoneWearListener` tags.
5. Confirm duplicate message/data deliveries log `apply=ignored` for the second copy.

## Workout Tests

### Phone -> Watch Active Workout

1. Start a workout on the phone from a template with four sets.
2. Include mixed target reps/weights, a warmup set, a non-standard set type, and metadata where available.
3. Log one set on the phone.

Expected:

- Watch receives one accepted snapshot.
- Template and active exercise identity match the phone.
- Planned and actual sets appear at the same positions.
- RPE half-points and metadata are preserved.
- Ongoing notification appears once and does not alert again on updates.

### Watch Planned Set Logging

1. Start the synced template on the watch.
2. Open the set logger.
3. Confirm kg/reps/type initialize from the first unfinished planned set.
4. Log that set.

Expected:

- The first planned unfinished set becomes completed.
- A new set is not appended unless no unfinished planned set exists.
- Phone Drift receives the update at the same set position.

### Watch -> Phone Start/Update/End

1. Start a workout on the watch.
2. Log two sets with different types, warmup state, and RPE.
3. Open the phone notification.
4. Finish, then repeat with discard.

Expected:

- Phone creates/adopts one active session.
- "Workout Started on Watch" alerts only on the idle -> active transition.
- Durable updates do not re-alert.
- Finish/discard clears pending state and notifications.

## Reconnect Tests

1. Start active workout while connected.
2. Disconnect Bluetooth/Wi-Fi.
3. Make edits on one side.
4. Reconnect.

Expected:

- Latest durable snapshot wins.
- Stale snapshots with lower revision are ignored.
- MessageClient misses do not lose state.
- Command queues flush once after reconnect.

## Fasting Tests

### Phone-Started Fast

1. Start a fast on the phone.
2. Open Fasting on watch.

Expected:

- Watch shows active fast.
- Elapsed time increments locally from `startedAtEpochMs`.
- No per-second DataClient sync is required.

### Watch Start/Stop

1. Tap Start on watch Fasting.
2. Confirm phone creates an active Drift fasting session.
3. Disconnect devices, tap Stop on watch, then reconnect.

Expected:

- Watch sends a command with `commandId`.
- Phone applies it once, ACKs it, and sends authoritative snapshot back.
- Active fast is not reset by manual macro sync.

## Rotary Matrix

Run on:

- Galaxy Watch Classic physical rotating bezel
- Galaxy Watch without physical bezel
- Touch bezel or emulator rotary input

Cases:

- Logger page 0: tap kg, rotate clockwise/counter-clockwise.
- Logger page 0: tap reps, rotate clockwise/counter-clockwise.
- Page 1 set-type list scroll.
- Page 2 accessory list scroll.
- RPE dialog scroll.

Expected:

- Exactly one active target exists on logger page 0: `WEIGHT` or `REPS`.
- Clockwise increases the selected value; counter-clockwise decreases it.
- Horizontal/vertical pagers do not steal rotary input while editing kg/reps.
- Bounds hold at 0 kg, max kg, 1 rep, and max reps.

## Notification Expectations

- START creates one ongoing workout surface.
- UPDATE is silent and updates the existing surface.
- RESTORE recreates state without a new alert.
- END removes foreground service and notification.
- Twenty sequential workout updates should produce no repeated alerts.
