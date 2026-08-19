# 12-02 Summary — Cardio, Olympic, CrossFit and mobility coverage

**Executed:** 2026-08-18. 51 rows added via `ADDITIONS` in
`tool/catalog_cleanup.py`. Catalogue 408 → 459.

| category | before | after |
|---|---:|---:|
| cardio | 3 | 18 |
| crossfit | 1 | 29 |
| mobility | 0 | 8 |

## What was added

**Cardio (15).** Machines: Rowing Erg, Air Bike, Ski Erg, Stationary Bike,
Elliptical, Stair Climber, Incline Treadmill Walk. Field: Outdoor Run, Outdoor
Cycling, Swimming, Sprint, Hill Sprint, Shuttle Run, Battle Ropes, Double Unders.

**Olympic (12).** Power Clean, Hang Power Clean, Squat Clean, Clean & Jerk,
Power Snatch, Hang Snatch, Squat Snatch, Muscle Snatch, Overhead Squat, Push
Jerk, Split Jerk, Thruster.

**CrossFit gymnastics and conditioning (16).** Bar Muscle-Up, Chest-to-Bar
Pull-Up, Kipping Pull-Up, Butterfly Pull-Up, Rope Climb, Wall Walk, Handstand
Walk, Wall Ball, Ball Slam, Box Jump Over, Burpee Box Jump Over, Devil's Press,
Dumbbell Snatch, Man Maker, Sandbag Clean, Sled Rope Pull.

**Mobility (8).** 90-90 Hip Switch, Couch Stretch, Thoracic Extension, ATG Split
Squat, Jefferson Curl, Deep Squat Hold, Band Shoulder Dislocate, Wall Slide.

All are `derived: false` — hand-authored, so the app does not flag them for
review. Nine new equipment labels (Rower, Air Bike, Ski Erg, Stationary Bike,
Elliptical, Stair Climber, Medicine Ball, Sandbag, Climbing Rope, Battle Ropes)
all map to modality `other`, preserving the one-equipment-one-modality invariant.
`equipment_icon.dart` switches on modality with a `default:` case, so no icon
work was needed.

## Dedup discipline held

`Prowler Push` was **not** added. Prowler is a brand of sled, so it became an
alias on `sled-push` — otherwise the coverage work would have created exactly
the kind of duplicate this phase exists to remove. Likewise `Sled Pull` is an
alias on the new `Sled Rope Pull` (hand-over-hand from standing), which is a
genuinely different movement from the existing `Sled Drag` (harness, walking).

The cleanup script's own alias-collision guard fired once and correctly dropped
`Bar Muscle-Up` as an alias of `Strict Muscle-Up`, now that it is a real row.

Every added row was checked against the movement clustering: none joined an
existing group accidentally.

## Guard added

`_assert_no_duplicate_keys()` now AST-parses `catalog_cleanup.py` at startup and
fails if `FIELD_FIXES` or `RENAMES` lists a slug twice. This was written after
three duplicate keys were introduced during 12-03 and silently discarded the
earlier entry's overrides — invisible in the run report, and only surfacing after
a rebuild from the xlsx when the dropped fix no longer re-applies.
