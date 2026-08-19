# Phase 12 — Context: what the catalogue audit found

**Audited:** 2026-08-18, against `assets/data/exercises.json` at 408 rows.

The catalogue was generated from a hypertrophy/powerlifting spreadsheet by
`tool/build_exercises.py`, which derives equipment, muscles, CNS cost and
logging metric from the exercise *name*. That is right most of the time and
confidently wrong the rest, and the source xlsx is not in the repo — so
corrections live as data in `tool/catalog_cleanup.py` and are re-applied after
any rebuild. **Nothing in this phase edits `exercises.json` by hand.**

## Finding 1 — equipment is baked into names, so one movement is many rows

There is no "Bench Press". There is `Barbell Bench Press`, `Dumbbell Bench
Press`, `Smith Machine Bench`, `Cambered Bar Bench Press`, `Swiss Bar Bench
Press` and `Duffalo Bar Bench Press`. Curl had 10 rows, Squat 7, Hip Thrust 7,
Overhead Press 6.

The fix already half-existed. `movementSlug` + `allowedEquipment` (from
`assets/data/movements.json`) drive a collapsed picker via
`equipmentVariantsFor()` and `_groupByFamily()` in `exercise_picker_sheet.dart`.
The equipment axis was in fact working for the large families — 173 of 408 rows
were grouped, and the ungrouped remainder was mostly genuine singletons.

What it did **not** cover was a second axis: **grip, attachment and start
position on the same machine.** Those never collapse through `allowedEquipment`
because every member shares one modality:

| Family | Rows | All on |
|---|---|---|
| Lat Pulldown (bare, Wide, Super Wide, V-Bar, Reverse, Rope) | 7 | Cable |
| Tricep Pushdown (Rope, Straight Bar, V-Bar, EZ Bar, Reverse) | 6 | Cable |
| Seated Cable Row (V-Bar, Wide, Rope, Neutral Single) | 4 | Cable |
| Rack Pull (Below Knee, Above Knee, Mid-Thigh) + Swiss Bar | 4 | Barbell |
| Pull-Up (bare, Wide, Super Wide, Neutral, assisted ×5) | 9 | Bodyweight |

31 rows sat outside their own family for this reason.

## Finding 2 — three declared categories were empty

`category` is offered as a filter chip in the picker, in the custom-exercise
builder and as the Supabase default. Three of its seven values were effectively
unreachable:

| category | rows before |
|---|---:|
| strength | 245 |
| hypertrophy | 93 |
| calisthenics | 57 |
| powerlifting | 9 |
| **cardio** | **3** — Jump Rope, Treadmill Run, Treadmill Walk |
| **crossfit** | **1** — Sled Push |
| **mobility** | **0** |

No rower, air bike, ski erg, stair climber or outdoor work. No Olympic lifts at
all. No CrossFit gymnastics or conditioning vocabulary.

## Finding 3 — `loggingMetric` was inert, and partly wrong

The column exists with six declared values and is read in exactly two places,
neither of them the logger. **`SetEntries` has only `weightKg` and `reps`, both
NOT NULL**, and so does the server (`0002_sync_schema_children.sql:209-226`).
A Plank, a Sled Push and a Treadmill Run were all stored as kilos × reps.

The vocabulary had also drifted across its three unlinked definitions — a table
comment, a const list in the custom-exercise builder, and the Python derivation:

- `weight_distance` shipped on Sled Push while never being declared.
- `distance` was declared and used by nothing.
- Every carry — Farmer's Walk, Yoke Walk, Suitcase Carry, Waiter's Carry, Trap
  Bar Carry — was `weight_time`, though carries are scored over a set distance.
  Sled Drag was timed while Sled Push, the same apparatus, was not.
- `Dumbbell Glute Bridge` was `time`, which hides the weight field, so the
  dumbbell had nowhere to go.
- Two of the three walking lunges were `weight_time` while the third was
  `weight_reps`.

Rounds-based work is **not** a gap: `SetType.amrap/emom/forTime` already exist
with `metaKeys` persisted in `set_type_meta_json`, which composes with whatever
metric the movement uses. It stays there.

## Two data bugs found while fixing the above

- `Trap Bar Deadlift (Low Handles)` carried `movementPattern: squat` while
  `(High Handles)` carried `hinge`, so the two handle heights of one exercise
  clustered into different movements.
- `Death March` was `modality: bodyweight` despite its own alias being "Walking
  KB March". The name carries no equipment word, so the derivation guessed
  bodyweight, which then forced a timed metric onto a loaded exercise.

## Decisions

- **Non-destructive.** No row deleted, no `set_entries.exercise_id` remapped.
  Variants remain rows; the picker collapses them. Chosen over a hard merge
  because a merge needs a history migration and `ExerciseMergeEngine` runs, but
  the risk is not worth a shorter list.
- **Olympic lifts are filed under `crossfit`,** not `strength`. The catalogue
  already reserves `powerlifting` for the three competition lifts, so `crossfit`
  is the sibling bucket where this app's users look for a clean or a snatch;
  under `strength` they were buried among 245 rows. Aliases carry the
  alternative vocabulary either way.
- **Existing rows were not recategorised.** `Burpee` stays calisthenics, `Push
  Press` stays strength. A single-valued `category` means moving them would
  remove them from a filter that legitimately contains them.
- **`Prowler Push` is not a new exercise.** Prowler is a brand of sled, so it
  became an alias on `sled-push` rather than the duplicate row the coverage work
  would otherwise have created.
