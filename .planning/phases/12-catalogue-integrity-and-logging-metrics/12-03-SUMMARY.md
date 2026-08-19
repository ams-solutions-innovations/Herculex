# 12-03 Summary — LoggingMetric registry and metric corrections

**Executed:** 2026-08-18.

## The registry

`lib/features/workouts/domain/logging_metric.dart` — a `SetType`-style enum that
is now the only definition of the vocabulary. Each value declares the `SetField`s
the logger should render, which is what makes it more than a label:

| id | fields |
|---|---|
| `weight_reps` | weight, reps |
| `reps` | reps |
| `reps_time` | reps, duration |
| `time` | duration |
| `distance` | distance |
| `time_distance` | duration, distance |
| `weight_time` | weight, duration |
| `weight_distance` | weight, distance |
| `calories` | calories |
| `time_calories` | duration, calories |

`isRepBased` and `isLoaded` are derived from `fields`, so downstream code asks a
question about the metric rather than string-matching it. `fromId` falls back to
`weightReps` rather than throwing — a custom row written by an older build must
still open.

Rounds-based work is deliberately absent: `SetType.amrap/emom/forTime` already
carry it in `set_type_meta_json`, and keeping it there lets it compose with
whatever metric the underlying movement uses.

## Corrections applied (`catalog_cleanup.py`)

| slug(s) | was | now | why |
|---|---|---|---|
| all 7 carries + `sled-drag` | `weight_time` | `weight_distance` | carries are scored over a set distance; Sled Push was already `weight_distance` while Sled Drag, the same apparatus, was timed |
| `glute-bridge` | `time` | `reps` | it is a rep exercise |
| `dumbbell-glute-bridge` | `time` | `weight_reps` | `time` hides the weight field, so the dumbbell had nowhere to go |
| `safety-bar-walking-lunge`, `dumbbell-walking-lunge` | `weight_time` | `weight_reps` | counted in steps; `barbell-walking-lunge` was already correct |
| `death-march` | `weight_time`, bodyweight | `weight_reps`, Dumbbell | see below |
| `pseudo-planche-push-up` | `time` | `reps` | it is a push-up; the hold is a separate movement |
| `jump-rope` | `time` | `reps_time` | double-unders are counted, skipping is timed |
| `trap-bar-deadlift-low-handles` | pattern `squat` | pattern `hinge` | matched its high-handle twin, which had split the two into different movements |

`weight_time` now has no members, but stays in the registry — timed loaded
carries are a real thing the custom-exercise builder should be able to express.

## Two data bugs, not just metric labels

**Death March** was `modality: bodyweight` while its own alias is "Walking KB
March". The derivation guessed bodyweight because the name carries no equipment
word, which then forced a timed metric onto a loaded exercise. Fixing only the
metric broke `catalog_cleanup_test.dart`'s "a bodyweight row logs reps, not
weight × reps" invariant — correctly, because the row was lying about two things.
Equipment, modality and metric were fixed together.

**Duplicate `FIELD_FIXES` keys.** Adding metric entries for
`dumbbell-glute-bridge`, `suitcase-carry` and `waiter-s-carry` created a second
dict entry for slugs that already had one, and Python kept only the last — so the
earlier equipment/modality overrides were silently discarded. Not visible in the
run report. Merged into single entries, and `_assert_no_duplicate_keys()` now
makes it impossible to reintroduce quietly.

## Wiring

- `equipment_variants.dart` — the guard that returned a single equipment option
  for any non-rep metric now runs **after** the authored `allowedEquipment`
  check. An authored list is a fact about the movement regardless of scoring: a
  Farmer's Walk is genuinely carried on handles or dumbbells, and the old order
  suppressed that swap purely because carries are not measured in reps. The
  band-assist fallback is now correctly limited to rep-based bodyweight work —
  there is no band-assisted plank. Verified against all four affected movements;
  three are single-modality and unchanged.
- `custom_exercise_builder_view.dart` — `_metrics` is derived from
  `LoggingMetric.values` instead of restated. It had already drifted, so a custom
  sled variant could not be given the metric its seeded counterpart uses.

## Tests added (`exercise_catalog_validation_test.dart`)

- every `loggingMetric` in the asset resolves against `LoggingMetric.ids`
- every declared category has exercises in it, and no row has an undeclared one
- no movement spans more than one `movementPattern`

Full suite after this phase: **676 passed, 4 skipped, 26 failed** — the 26 are
pre-existing and unrelated, confirmed by stashing every change and re-running
(baseline: 673 passed, 26 failed).

## Left for 12-04 / 12-05

The registry describes fields the schema still cannot store. `SetEntries` needs
nullable `durationSeconds`, `distanceM` and `calories` (Drift v30 + Supabase
0012), and the set row must branch on `fieldsFor(exercise)`. Until then a Plank
still records kilos × reps — the vocabulary is correct, the storage is not.
