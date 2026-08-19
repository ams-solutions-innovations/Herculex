# 12-05 Summary — Metric-driven set entry and tonnage exclusion

**Executed:** 2026-08-19. Closes **EXR-05**, the last open Phase 12 requirement.

12-03 built the `LoggingMetric` registry and 12-04 gave `set_entries` the three
nullable columns. Neither was read by anything: the logger rendered a fixed
weight/reps/RPE row for all 408 catalogue rows, and `updateSet` had no parameter
that could reach `durationSeconds`, `distanceM` or `calories`. A Plank recorded
kilos × reps. This plan connects the three.

## The set row now asks its exercise what it measures

`ActiveExerciseCard` resolves `LoggingMetric.fromId(exercise.loggingMetric)`
once and hands it to both `_HeaderRow` and `_SetRow`, which each iterate
`metric.fields`. Because the header labels and the inputs come from the same
list, they cannot disagree — that is the property the widget tests assert
against, since a header reading `TIME` proves the controller under it is the
duration one.

| exercise | row |
|---|---|
| Back Squat (`weight_reps`) | KG · REPS · RPE — unchanged |
| Plank (`time`) | TIME · RPE |
| Sled Push (`weight_distance`) | KG · M · RPE |
| Air Bike (`time_calories`) | TIME · KCAL · RPE |

Field-specific affordances stayed attached to their own field rather than to a
column position: the plate calculator long-press is on weight, the
`_repsEditedByUser` flag that protects a typed rep count from the rep tracker is
on reps, and the rep-tracker prefill path is additionally gated on
`metric.isRepBased` so a detection can never reach a hold or a carry.

Duration accepts `90`, `90s`, `1:30` and `1:02:30` and re-renders exactly what
it would re-parse — asserted as a round-trip, not as two independent string
tables.

## What "not measured this way" means in storage

`updateSet` gained the three columns using the existing `bodyweightKg`/`chainsKg`
absent-vs-null-vs-clear idiom. `_commit` sends `null` for any field the metric
does not declare, which `updateSet` reads as *leave alone* — so a Plank never
overwrites a weight, and re-classifying an exercise's metric never silently
blanks what was already logged. 0013 is nullable precisely so
`null` ("does not apply") stays distinguishable from `0` ("logged, and it was
zero"); a non-rep set still writes `weightKg = 0` / `reps = 0` because those
columns are and remain NOT NULL.

## The zeros are not what excludes the set from volume

`ResolvedSet.tonnageKg` returns 0 when `!metric.isRepBased`, and a new
`countedReps` does the same for rep totals. Both were deliberately gated on the
metric rather than on the stored numbers: the numbers are a NOT NULL placeholder
and the metric is the fact. `weeklyTonnage` gained an `exerciseCatalog` join
purely to read `loggingMetric`, and `topOneRms` skips any exercise whose metric
is not both rep-based *and* loaded.

The gate is `isRepBased`, **not** `isLoaded`. A bodyweight pull-up is rep work
whose effective load is the athlete's own mass; gating on load would have
silently deleted every bodyweight athlete's volume history. The test suite pins
this with a pull-up that must still produce 640 kg.

`session_summary.dart`, `weekly_muscle_volume.dart` and the recovery/CNS engines
needed no changes — they all read `rs.tonnageKg`, which is exactly why 09-02
consolidated them onto the shared snapshot.

## Display

`set_metric_format.dart` holds one `summariseSet`, now used by the last-time
hint, the per-set micro-label, the session log and the dynamic-workout big
readout. Its `weight_reps` branch emits the byte-identical string those four
sites hardcoded before, so existing history does not shift under existing users.

Two surfaces that could only lie about a non-rep exercise were made honest
rather than left alone:

- The estimated-1RM **trend card** on exercise details is absent for a non-rep
  metric instead of plotting a flat line through the placeholder zeros.
- The **per-variant performance line** drops to `N sets` instead of
  `0 kg × 0 reps · N sets`, and its e1RM figure is suppressed.

One pre-existing bug fell out of the rewrite: `dynamic_workout_view.dart` had a
private `_fmtWeight` that appended a hardcoded `kg` and never converted, so the
full-screen readout showed kilograms to imperial users. It is deleted;
`summariseSet` goes through `WeightFormat`.

## New unit

`DistanceFormat` in `core/units.dart`, bound to the same single
`MeasurementUnit` the profile already owns — no second unit preference. Storage
is metres for the same reason storage is kilograms. The input field is always in
the base unit (`m`/`yd`) so a 20 m sled push and a 5 km run are typed the same
way; only rendered summaries promote to `km`/`mi`.

## Tests

- `test/logging_metric_ui_test.dart` — 11 tests. Four render assertions across
  `weight_reps`/`time`/`weight_distance`/`time_calories` (the first is the
  regression gate that the ordinary case is untouched), two end-to-end
  round-trips through a real in-memory database proving `2:00` stores 120 and
  leaves `distanceM`/`calories` null, and five format/parse cases.
- `test/set_metric_tonnage_test.dart` — 6 tests: sled push contributes zero,
  a squat in the same session still contributes 500 kg (the exclusion is per
  set), a plank is a set but not volume, a bodyweight pull-up still counts, and
  both `weeklyTonnage` and `topOneRms` consult the metric. The `weeklyTonnage`
  case deliberately gives the sled a rep count so the numbers alone *would*
  produce tonnage — only the metric stops it.

Full suite: **873 passed, 4 skipped, 0 failed.** `flutter analyze lib/` reports
only the six pre-existing `deprecated_member_use` infos, none in a touched file.

## Deviations from the plan

- The plan said `exercise_details_view.dart` "stays as is". It could not: with
  non-rep metrics now loggable, its trend card and performance line render
  fabricated numbers for them. Both were gated instead.
- `SessionSummary.from` in the plan's Task 5 is really `fromSnapshot`.
