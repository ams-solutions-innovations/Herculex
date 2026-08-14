# Phase 10: Assisted Rep Tracking - Context

**Gathered:** 2026-08-14
**Status:** Drafted, not scheduled — depends on Phase 9 landing first
**Source:** Codebase audit of the Wear Data Layer bridge, the set-logging write path, the exercise catalogue and the Drift migration chain

<domain>
## Phase Boundary

Add an opt-in, on-device rep counter for pull-ups and dips that **proposes** a rep count (and, once calibrated, an RPE) at the end of a set. The user reviews and confirms or edits every value. Nothing about the tracker may write to a set.

In scope: consent and per-exercise opt-in, accelerometer capture on Wear OS and on the phone, a single authoritative rep-cycle detector, a per-user/per-exercise/per-device calibration profile learned only from confirmed sets, the live counter and review UI, and the trace-fixture test infrastructure.

Out of scope: every other exercise (the eligibility list is closed and enumerated below); heart-rate or gyroscope input; form or ROM *scoring*; automatic set completion in any form; cloud sync of any motion-derived data; changes to the analytics engines in Phase 9.

**Depends on Phase 9** only for merge order — Phase 9 rewrites `analytics_providers.dart` and `insights_view.dart`, which this phase does not touch. There is no functional dependency, but landing 9 first avoids a schema-version race (Phase 9 adds no tables; this phase takes v26).
</domain>

<decisions>
## Implementation Decisions

### The non-negotiable: the tracker cannot write a set

`WorkoutsRepository.updateSet` (`lib/features/workouts/data/workouts_repository.dart:858`) is the single mutation path for `reps`, `rpeX10` and `isCompleted`. The rule for this phase:

- All tracker code lives under `lib/features/reps/`.
- **Nothing under `lib/features/reps/` may import `workouts_repository.dart` or reference `updateSet`.** The tracker's terminal output is an immutable `RepSuggestion` value object.
- Only the existing confirm handler in `active_workout_view.dart` calls `updateSet`, and only from a user tap.
- This is enforced by a static test (10-04) that greps the feature directory, not by convention.

The layering is the safety property. A guard flag inside a shared service would be one refactor away from failing open; an import boundary fails loudly at compile and test time.

### Where detection runs

Two constraints pull in opposite directions: the live on-wrist counter needs sub-second feedback *at the sensor*, while one authoritative algorithm with one test suite needs a single implementation. The resolution:

- **A provisional counter in Kotlin on the watch** drives the live count and haptics during the set. It is deliberately simple (adaptive-threshold peak count, no calibration), its output is labelled provisional in the UI, and it is **never persisted and never reaches the review sheet**.
- **The authoritative detector is Dart, on the phone**, and runs over the buffered raw sample stream. Its output is what the review sheet proposes.

The watch batches raw samples in ~1 s chunks over MessageClient. At 50 Hz × 3 axes × 4 B that is ~600 B/s — negligible for the Data Layer. Raw samples never leave the paired device pair.

If the two counts disagree by more than 1 rep, the review sheet shows the authoritative count and drops confidence one band. Do not average them.

### Watch–phone disconnect

The watch keeps a 300-second ring buffer of raw samples and flushes on reconnect. If the phone never receives the set's samples before the user confirms, the review sheet opens in **manual state** with the reason stated ("watch was not connected — count not verified"). It does not silently fall back to the provisional count. Because the tracker only ever proposes, a total capture failure degrades to today's manual entry, which is the correct floor.

### Sensor and sampling

- `TYPE_LINEAR_ACCELERATION` at `SENSOR_DELAY_GAME` (~50 Hz), resampled to a fixed 50 Hz grid before detection so fixtures and live data take identical code paths.
- Falls back to `TYPE_ACCELEROMETER` with a high-pass detrend where linear acceleration is unavailable; the profile records which was used, because the two are not interchangeable for calibration.
- **No new Android permission is required.** Accelerometer is not a `BODY_SENSORS` sensor (that covers heart rate, already declared), and `HIGH_SAMPLING_RATE_SENSORS` only applies above 200 Hz.
- Capture is hosted by the existing `WorkoutOngoingService` (`android/wear/src/main/java/com/ams/herculex/workout/WorkoutOngoingService.kt:23`), already declared `foregroundServiceType="health"`. **Do not add a second foreground service.**

### Eligible exercises

Keyed by `ExerciseCatalog.slug`, not name — the catalogue renames rows and matches on slug by design (`lib/data/local/tables.dart:38`). The v1 list is closed:

`pull-up`, `pull-up-wide-grip`, `pull-up-super-wide`, `pull-up-neutral-grip`, `chin-up-supinated`, `chest-dips`, `ring-dips`

Deliberately excluded: every assisted and band-assisted variant (the assistance changes the acceleration profile enough to need its own calibration), `trx-hanging-dip` and `bench-dip` (unstable and seated kinematics), `negative-pull-up` and `scapular-pull-up` (no countable concentric cycle), and `typewriter-pull-up`, `commando-pull-up`, `behind-the-neck-pull-up`, `towel-pull-up`, `ring-l-sit-pull-up` (asymmetric or low-volume; not enough real traces to validate).

### Persistence and sync

The three new tables are **local-only**: no `SyncColumns`, no `SyncTombstone`, not added to `syncedTableNames`, no outbox triggers. Calibration is specific to one user on one device in one placement, so it is not meaningful on another device, and motion-derived data is exactly what the privacy requirement says needs a separate opt-in before it leaves the phone. Keeping it out of the sync set also avoids touching the v25 trigger installation.

Retained per set: derived features and the confirmed outcome. **Raw sample arrays are held in memory for the duration of the set and discarded** — they are never written to the database.

### RPE suggestion gating

No universal "everyone slows down near failure" assumption. Instead, per (user, exercise, device, placement):

- Features per set: mean rep period, rep-period coefficient of variation, normalised amplitude (ROM proxy), final-rep period ratio, amplitude decay ratio.
- Label: the user's confirmed RPE.
- Model: ordinary least squares on standardised features, refit on every new confirmed set. With n ≤ 30 there is nothing to gain from anything heavier.
- **Gate: suggest an RPE only when n ≥ 10 confirmed sets across ≥ 3 distinct sessions AND leave-one-out MAE ≤ 1.0 RPE points.**

The LOO gate is what makes the "don't assume slowdown" requirement real rather than aspirational: for a user whose cadence carries no RPE signal, the coefficients collapse toward zero, LOO error stays high, and the app simply never offers an RPE. That is the correct outcome and it needs no special-casing.

### Confidence and fallback states

One enum, `TrackerState`, consumed by every surface:

| State | Trigger | Shown |
|---|---|---|
| `disabled` | no consent, or exercise not opted in | nothing |
| `ready` | eligible, consent given, sensor available | "Start tracking" |
| `tracking` | capture running | live count + confidence bar |
| `countOnly` | low confidence, placement changed, or calibration insufficient | count proposed, **no RPE** |
| `manual` | sensor unavailable, disconnected, battery gate, or capture aborted | today's manual entry + stated reason |

`countOnly` and `manual` are not error states and must not be styled as errors.

### Interruption and battery handling

- Capture refuses to start below 15 % battery on the capturing device, with the reason stated.
- A 5-minute hard cap per set stops capture, keeps what was collected, and says so.
- Sensor listeners unregister on set end, on service stop, and on app background — verified by a test asserting balanced register/unregister calls.
- Accidental motion (walking, re-gripping) is handled by the amplitude gate and refractory period in the detector, not by a separate classifier.

### Claude's Discretion

- Exact filter taps and threshold constants in the detector, provided the fixture tests pass at the stated accuracy bar.
- Widget composition of the review sheet, as long as rep count and RPE are both editable and neither is pre-confirmed.
- Whether the provisional Kotlin counter lives in `WorkoutOngoingService` or a collaborator class.
</decisions>

<requirements>
## Requirements to append to `.planning/REQUIREMENTS.md` when this phase is scheduled

- **REP-01**: Rep tracking is off until the user completes a dedicated consent screen, and then off per exercise until separately enabled. It is offered only for the enumerated eligible slugs.
- **REP-02**: The user chooses the sensor source. The phone accelerometer is used only when a placement is explicitly selected.
- **REP-03**: The tracker never completes, saves or alters a set. Every rep count and RPE reaches the database only through a user confirmation, and the tracker feature directory contains no reference to the set write path.
- **REP-04**: Raw accelerometer samples are processed on the user's devices and discarded at set end. Only derived features and confirmed outcomes persist, and none of it syncs.
- **REP-05**: An RPE suggestion appears only after ≥ 10 confirmed sets across ≥ 3 sessions for that exercise/device/placement, and only when leave-one-out error is within 1.0 RPE point. Low confidence, changed placement or unsupported movement yields a count-only state.
- **REP-06**: Recorded motion traces for pull-ups and dips verify counting accuracy, missed-rep handling, false-positive resistance, source and placement changes, and the never-auto-complete guarantee.
</requirements>

<plans>
## Plan Sequence

| Plan | Wave | Depends on | Scope |
|---|---|---|---|
| 10-01 | 1 | — | Schema v26, consent/eligibility state, repository |
| 10-02 | 1 | — | Pure-Dart detection engine + trace fixtures |
| 10-03 | 2 | 10-02 | Wear Kotlin capture, Data Layer transport, phone capture |
| 10-04 | 3 | 10-01, 10-02, 10-03 | Consent flow, live counter, review-and-confirm sheet |
| 10-05 | 4 | 10-01, 10-04 | Calibration learning and RPE gating |
| 10-06 | 6 | 10-02, 10-03b, 10-04 | In-app debug tool: fixture-recording checklist and capture flow, replacing the manual hardware procedure in 10-02 Task 5 |

10-01 and 10-02 are independent and can run in parallel: 10-02 is pure functions over a sample list and touches no database.

10-06 does not close REP-06 by itself — it produces app-local files the developer still exports and commits under `test/fixtures/motion/` by hand. 10-02 Task 5's automated fixture-count check remains the actual gate.
</plans>

<risks>
## Known Risks

- **Fixture recording is a human task.** 10-02's accuracy bar cannot be met with synthetic traces alone. Someone must record real pull-up and dip sets on both a watch and a pocketed phone, with a ground-truth count, before 10-02 can close. Budget this explicitly; it gates the phase.
- **`WearSyncPaths.kt` is duplicated** between `android/app/src/main/kotlin/com/ams/herculex/sync/` and `android/wear/src/main/java/com/ams/herculex/sync/` and must stay byte-identical (LESSONS.md:85). A new path added to one and not the other fails silently — no error, no log.
- **A stale watch APK looks exactly like a sync bug** (LESSONS.md:83). Check `adb shell dumpsys package com.ams.herculex | grep lastUpdateTime` before debugging transport.
- **Gradle needs Android Studio's JBR**, not the system JDK 26. Set `JAVA_HOME` before any `gradlew` call.
- Ring dips are on the eligible list but are meaningfully less stable than bar dips. If fixture accuracy for `ring-dips` misses the bar, drop it from the list rather than loosening the thresholds.
</risks>
