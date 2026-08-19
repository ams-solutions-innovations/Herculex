#!/usr/bin/env python3
"""Hand corrections to the exercise catalog.

`build_exercises.py` derives equipment, modality and muscles from the exercise
*name*, which is right most of the time and confidently wrong the rest. "Hammer
Curl" matched the Hammer Strength machine vocabulary and became a plate-loaded
machine; twenty rows whose names carry no equipment word at all fell through to
`other`. Those wrong modalities are not cosmetic — the movement layer unions its
members' modalities into `allowedEquipment`, so one bad row puts a nonsense
button in the equipment prompt for every variant of that movement.

Rather than patch the heuristics (the xlsx source is not in the repo, so a
rebuild is not reproducible here), corrections live in this file as data. Each
table below is idempotent, so the script can be re-run after any future rebuild
to re-apply the same decisions.

Run this before `derive_movements.py --write`: merges and renames change which
rows cluster together.

Usage:
    python tool/catalog_cleanup.py            # report only
    python tool/catalog_cleanup.py --write    # rewrite exercises.json
"""

import ast
import collections
import json
import sys
from collections import OrderedDict

CATALOG = "assets/data/exercises.json"


def _assert_no_duplicate_keys():
    """Fails loudly if a correction table lists the same slug twice.

    Python keeps only the last binding for a repeated dict key, so a second
    entry for a slug silently discards the first one's overrides. That is
    invisible in the run report — the row still looks corrected, because the
    surviving entry reports its own change — and only surfaces after a rebuild
    from the xlsx, when the dropped fix no longer re-applies.
    """
    tree = ast.parse(open(__file__, encoding="utf-8").read())
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        name = getattr(node.targets[0], "id", "")
        if name not in ("FIELD_FIXES", "RENAMES"):
            continue
        keys = [k.value for k in node.value.keys]
        dupes = [k for k, n in collections.Counter(keys).items() if n > 1]
        if dupes:
            raise SystemExit(
                f"{name} lists these slugs more than once, so the earlier "
                f"overrides are being dropped: {', '.join(sorted(dupes))}"
            )


# ── Equipment fixes ─────────────────────────────────────────────────────────
# slug -> field overrides. Only rows where the derived value is wrong, not
# merely coarse.
#
# `_bw` is the shape a bodyweight row takes throughout the catalog: reps rather
# than weight × reps, with added load carried by the weighted-bodyweight field.
# Rows that flip to bodyweight need it, or the logger keeps asking for a kg
# figure on a movement that has no weight stack.
def _bw(equipment="Bodyweight"):
    return {
        "modality": "bodyweight",
        "equipment": equipment,
        "loggingMetric": "reps",
        "supportsWeightedBodyweight": True,
    }


FIELD_FIXES = {
    # "hammer" matched the Hammer Strength machine vocabulary. A hammer curl is
    # a dumbbell held neutral, and this row was the only thing putting a
    # plate-loaded machine in the curl movement's equipment list.
    "hammer-curl": {"equipment": "Dumbbell", "modality": "dumbbell"},
    # Loaded by a band, not a cable stack; the "pushdown" keyword won.
    "band-triceps-pushdown": {"equipment": "Band", "modality": "band"},
    # You are holding a dumbbell. Bodyweight would hide the load field — and so
    # did the `time` metric, which is why the load also had to change here.
    "dumbbell-glute-bridge": {
        "equipment": "Dumbbell",
        "modality": "dumbbell",
        "loggingMetric": "weight_reps",
    },

    # ── names with no equipment word: derived as "other", actually bodyweight
    "curtsy-lunge": _bw(),
    "lateral-lunge": _bw(),
    "patrick-step-up": _bw(),
    "single-leg-hip-thrust": _bw(),
    "bodyweight-hip-thrust": _bw(),
    "b-stance-hip-thrust": _bw(),
    "standing-calf-raise": _bw(),
    "single-leg-standing-calf-raise": _bw(),
    "donkey-calf-raise": _bw(),
    "tibialis-raise": _bw(),
    "reverse-crunch": _bw(),
    "decline-crunch": _bw(),
    "ghd-russian-twist": _bw(),
    "hefesto": _bw(),

    # ── same, but free weights
    "behind-the-neck-ohp": {"equipment": "Barbell", "modality": "barbell"},
    "skullcrusher": {"equipment": "Barbell", "modality": "barbell"},
    "lying-lateral-raise": {"equipment": "Dumbbell", "modality": "dumbbell"},
    "lu-raise": {"equipment": "Dumbbell", "modality": "dumbbell"},
    "ytwli-raises": {"equipment": "Dumbbell", "modality": "dumbbell"},
    # Carries are scored over a set distance, not a duration — see the carry
    # block below for the rest of the family.
    "suitcase-carry": {
        "equipment": "Dumbbell",
        "modality": "dumbbell",
        "loggingMetric": "weight_distance",
    },
    "waiter-s-carry": {
        "equipment": "Kettlebell",
        "modality": "kettlebell",
        "loggingMetric": "weight_distance",
    },
    "face-pull": {"equipment": "Cable", "modality": "cable"},
    # A seated calf raise is its own plate-loaded machine.
    "seated-calf-raise": {"equipment": "Machine", "modality": "machine_plate"},

    # ── the other end of the same heuristic: no keyword matched at all, so the
    #    builder fell back to `barbell`
    "concentration-curl": {"equipment": "Dumbbell", "modality": "dumbbell"},
    "zottman-curl": {"equipment": "Dumbbell", "modality": "dumbbell"},
    "scarecrow": {"equipment": "Dumbbell", "modality": "dumbbell"},
    # A bayesian curl is the behind-the-body cable curl — the cable is the
    # whole point of it.
    "bayesian-curl": {"equipment": "Cable", "modality": "cable"},
    "cossack-squat": _bw(),
    "pelican-curl": _bw("Rings"),
    "suspended-squat": _bw("TRX"),

    # ── benches misread as weight stacks. A crunch bench has no stack; load is
    #    a plate held on the chest.
    # Held for time already, so only the equipment is wrong here.
    "copenhagen-adductor-plank": {
        "equipment": "Bodyweight", "modality": "bodyweight",
    },
    "roman-chair-reverse-crunch": _bw(),
    "ab-crunch-bench-angled": _bw(),
    "semi-recumbent-ab-bench-crunch": _bw(),

    # ── Movement pattern drift ──────────────────────────────────────────────
    # The two trap bar handle heights were derived as different patterns, so
    # the low-handle row clustered with squats while the high-handle row sat
    # with the deadlifts. Handle height changes the hip/knee balance, not the
    # movement: both are a deadlift.
    "trap-bar-deadlift-low-handles": {"movementPattern": "hinge"},

    # ── Logging metric corrections ──────────────────────────────────────────
    # Carries are scored over a set distance ("20 m farmer's walk"), not a
    # duration. `weight_time` also loses the number the lifter actually cares
    # about, and left Sled Push as the only `weight_distance` row in the
    # catalog while Sled Drag — the same apparatus — was timed.
    # (Suitcase Carry and Waiter's Carry are corrected in the equipment block
    # above, where they already had an entry.)
    "farmers-walk": {"loggingMetric": "weight_distance"},
    "dumbbell-farmers-walk": {"loggingMetric": "weight_distance"},
    "yoke-walk": {"loggingMetric": "weight_distance"},
    "trap-bar-carry": {"loggingMetric": "weight_distance"},
    "sled-drag": {"loggingMetric": "weight_distance"},

    # A glute bridge is a rep exercise, not a hold.
    "glute-bridge": {"loggingMetric": "reps"},

    # Walking lunges are counted in steps. Barbell Walking Lunge was already
    # `weight_reps`; these two were the outliers.
    "safety-bar-walking-lunge": {"loggingMetric": "weight_reps"},
    "dumbbell-walking-lunge": {"loggingMetric": "weight_reps"},
    # A death march is walking with a dumbbell in each hand, hinging between
    # steps — its own alias is "Walking KB March". It was derived as bodyweight
    # because the name carries no equipment word, which then forced the metric
    # to a timed hold and left the load nowhere to go.
    "death-march": {
        "equipment": "Dumbbell",
        "modality": "dumbbell",
        "loggingMetric": "weight_reps",
    },

    # It is a push-up. The hold variant is a separate movement.
    "pseudo-planche-push-up": {"loggingMetric": "reps"},

    # Skipping is timed, but double-unders are counted — both matter.
    "jump-rope": {"loggingMetric": "reps_time"},
}

# Deliberately left as `other`: sled/yoke work, neck harnesses, plate raises and
# the wrist roller. Each is a real piece of equipment with no modality of its
# own, and "Farmers Walk" means the dedicated handles — the dumbbell version is
# a separate row on purpose.


# ── Renames ─────────────────────────────────────────────────────────────────
# slug -> (name, extra aliases). Naming drift splits movements: the picker
# clusters on the equipment-stripped name, so "Chest Dips" and "Ring Dips" were
# two movements, and the plain dip could not be reached by searching "dip".
RENAMES = {
    "chest-dips": ("Dip", ["Chest Dip", "Chest Dips"]),
    "swiss-bar-skull-crusher": ("Swiss Bar Skullcrusher", []),
    # "(DB)" is the only place the catalog abbreviates the equipment.
    "front-raise-db": ("Dumbbell Front Raise", ["Front Raise"]),
    # Name unchanged; these only add aliases. A "Prowler Push" is a sled push —
    # Prowler is a brand of sled — so it earns an alias, not the second row it
    # would otherwise have become when CrossFit coverage was added.
    "sled-push": ("Sled Push", ["Prowler Push", "Prowler Sprint"]),
    "push-press": ("Push Press", ["Barbell Push Press"]),
    "toes-to-bar": ("Toes to Bar", ["T2B", "Toes-to-Bar"]),
    "ghd-sit-up": ("GHD Sit-Up", ["GHD Situp"]),
    "kipping-muscle-up": ("Kipping Muscle-Up", ["Ring Kipping Muscle-Up"]),
    "handstand-push-up": ("Handstand Push-Up", ["HSPU", "Strict HSPU"]),
    "burpee": ("Burpee", ["Burpees"]),
}


# ── Merges ──────────────────────────────────────────────────────────────────
# (loser, winner). The loser row leaves the catalog; its name and aliases move
# to the winner so search and program import still resolve them.
#
# This list is mirrored in lib/data/local/exercise_merges.dart, which repoints
# logged history on existing installs. Keep the two in step.
MERGES = [
    # Same exercise, two spellings of the same name.
    ("lateral-raise-db", "dumbbell-lateral-raise"),
    ("l-sit-ring-pull-up", "ring-l-sit-pull-up"),
    # "Feet on floor" is what a ring push-up already is; the elevated and knee
    # versions are the ones that need qualifying.
    ("ring-push-up-feet-on-floor", "ring-push-up"),
    ("seated-rotary-torso-machine", "rotary-torso-machine"),
    # "Weighted" is a loading choice, not a different exercise — added weight
    # belongs in the weighted-bodyweight field.
    ("russian-twist-weighted", "dumbbell-russian-twist"),
    ("weighted-side-bend", "dumbbell-side-bend"),
    ("weighted-dip", "chest-dips"),
]


# ── Coverage additions ──────────────────────────────────────────────────────
# Exercises the source spreadsheet skipped. Every one is a variant of a movement
# already in the catalog — the plain pull-up and plain lat pulldown were missing
# while five grip variations of each were present.
def _row(**kw):
    """Fills the fields every catalog row carries, so additions match shape."""
    row = {
        "slug": kw["slug"],
        "name": kw["name"],
        "aka": kw.get("aka", []),
        "bodyPart": kw["bodyPart"],
        "category": kw.get("category", "strength"),
        "movementPattern": kw["movementPattern"],
        "movementPatternRaw": kw["movementPatternRaw"],
        "modality": kw["modality"],
        "equipment": kw["equipment"],
        "primaryMuscle": kw["primaryMuscle"],
        "primaryMuscles": kw["primaryMuscles"],
        "secondaryMuscles": kw.get("secondaryMuscles", []),
        "stabilizers": kw.get("stabilizers", []),
        "cnsScore": kw["cnsScore"],
        "recoveryImpact": kw["recoveryImpact"],
        "loggingMetric": kw.get("loggingMetric", "weight_reps"),
        "supportsWeightedBodyweight": kw.get("supportsWeightedBodyweight", False),
        "defaultRestSeconds": kw["defaultRestSeconds"],
        "similar": kw.get("similar", []),
        # Hand-authored, so the app does not flag these for review.
        "derived": False,
    }
    return row


ADDITIONS = [
    _row(
        slug="pull-up", name="Pull-Up", aka=["Overhand Pull-Up"],
        bodyPart="Back", movementPattern="vertical_pull",
        movementPatternRaw="Vertical Pull", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Back", primaryMuscles=["Lats"],
        secondaryMuscles=["Biceps", "Rhomboids", "Rear Delts"],
        stabilizers=["Forearms", "Core"], cnsScore=4, recoveryImpact=2,
        loggingMetric="reps", supportsWeightedBodyweight=True,
        defaultRestSeconds=120,
        similar=["Pull-Up (Wide Grip)", "Pull-Up (Neutral Grip)",
                 "Chin-Up (Supinated)", "Lat Pulldown"],
    ),
    _row(
        slug="lat-pulldown", name="Lat Pulldown", aka=["Pulldown"],
        bodyPart="Back", movementPattern="vertical_pull",
        movementPatternRaw="Vertical Pull", modality="cable", equipment="Cable",
        primaryMuscle="Back", primaryMuscles=["Lats"],
        secondaryMuscles=["Biceps", "Rhomboids", "Rear Delts"],
        stabilizers=["Forearms", "Core"], cnsScore=4, recoveryImpact=2,
        defaultRestSeconds=120,
        similar=["Lat Pulldown (Wide Grip)", "Lat Pulldown (V-Bar)", "Pull-Up"],
    ),
    _row(
        slug="goblet-squat", name="Goblet Squat", aka=["Front-Loaded Squat"],
        bodyPart="Lower Body", movementPattern="squat",
        movementPatternRaw="Knee Dominant (Squat)", modality="kettlebell",
        equipment="Kettlebell", primaryMuscle="Quads", primaryMuscles=["Quads"],
        secondaryMuscles=["Glutes", "Adductors"], stabilizers=["Erectors", "Abs"],
        cnsScore=4, recoveryImpact=2, defaultRestSeconds=120,
        similar=["Dumbbell Squat", "Front Squat", "Barbell Back Squat"],
    ),
    _row(
        slug="ez-bar-preacher-curl", name="EZ Bar Preacher Curl",
        aka=["Barbell Preacher Curl"], bodyPart="Arms", category="hypertrophy",
        movementPattern="isolation",
        movementPatternRaw="Elbow Flexion (supported)", modality="barbell",
        equipment="EZ Bar", primaryMuscle="Biceps", primaryMuscles=["Biceps"],
        secondaryMuscles=["Brachialis", "Forearms"], cnsScore=2,
        recoveryImpact=1, defaultRestSeconds=75,
        similar=["Dumbbell Preacher Curl", "Machine Preacher Curl (Seated)",
                 "EZ Bar Curl"],
    ),
    _row(
        slug="spider-curl", name="Spider Curl", aka=["Prone Incline Curl"],
        bodyPart="Arms", category="hypertrophy", movementPattern="isolation",
        movementPatternRaw="Elbow Flexion (supported)", modality="dumbbell",
        equipment="Dumbbell", primaryMuscle="Biceps", primaryMuscles=["Biceps"],
        secondaryMuscles=["Brachialis"], cnsScore=2, recoveryImpact=1,
        defaultRestSeconds=75,
        similar=["Dumbbell Preacher Curl", "Concentration Curl", "Bayesian Curl"],
    ),
    _row(
        slug="cable-hammer-curl", name="Cable Hammer Curl",
        aka=["Rope Hammer Curl"], bodyPart="Arms", category="hypertrophy",
        movementPattern="isolation",
        movementPatternRaw="Elbow Flexion (brachialis/brachioradialis)",
        modality="cable", equipment="Cable", primaryMuscle="Biceps",
        primaryMuscles=["Biceps", "Forearms"], secondaryMuscles=["Brachialis"],
        cnsScore=2, recoveryImpact=1, defaultRestSeconds=75,
        similar=["Hammer Curl", "Zottman Curl", "Cable Bicep Curl"],
    ),
    _row(
        slug="landmine-press", name="Landmine Press",
        aka=["Half-Kneeling Landmine Press"], bodyPart="Shoulders",
        movementPattern="vertical_push",
        movementPatternRaw="Vertical Push (Angled)", modality="barbell",
        equipment="Landmine", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts"], secondaryMuscles=["Triceps", "Chest"],
        stabilizers=["Core", "Serratus"], cnsScore=4, recoveryImpact=2,
        defaultRestSeconds=120,
        similar=["Overhead Press", "Dumbbell Overhead Press",
                 "Machine Shoulder Press"],
    ),
    _row(
        slug="landmine-row", name="Landmine Row", aka=["T-Bar Row"],
        bodyPart="Back", movementPattern="horizontal_pull",
        movementPatternRaw="Horizontal Pull", modality="barbell",
        equipment="Landmine", primaryMuscle="Back",
        primaryMuscles=["Lats", "Rhomboids"],
        secondaryMuscles=["Biceps", "Rear Delts"],
        stabilizers=["Erectors", "Forearms"], cnsScore=5, recoveryImpact=3,
        defaultRestSeconds=120,
        similar=["Barbell Row", "T-Bar Row Machine", "Meadows Row"],
    ),
    _row(
        slug="barbell-reverse-lunge", name="Barbell Reverse Lunge",
        aka=["Back Lunge"], bodyPart="Lower Body", movementPattern="lunge",
        movementPatternRaw="Knee Dominant (Unilateral)", modality="barbell",
        equipment="Barbell", primaryMuscle="Quads",
        primaryMuscles=["Quads", "Glutes"], secondaryMuscles=["Hamstrings"],
        stabilizers=["Adductors", "Abs", "Erectors"], cnsScore=6,
        recoveryImpact=3, defaultRestSeconds=150,
        similar=["Dumbbell Reverse Lunge", "Barbell Walking Lunge",
                 "Bulgarian Split Squat"],
    ),
    _row(
        slug="barbell-walking-lunge", name="Barbell Walking Lunge",
        aka=[], bodyPart="Lower Body", movementPattern="lunge",
        movementPatternRaw="Knee Dominant (Unilateral)", modality="barbell",
        equipment="Barbell", primaryMuscle="Quads",
        primaryMuscles=["Quads", "Glutes"], secondaryMuscles=["Hamstrings"],
        stabilizers=["Adductors", "Abs", "Erectors"], cnsScore=6,
        recoveryImpact=4, defaultRestSeconds=150,
        similar=["Dumbbell Walking Lunge", "Safety Bar Walking Lunge",
                 "Barbell Reverse Lunge"],
    ),
    _row(
        slug="barbell-step-up", name="Barbell Step-Up", aka=[],
        bodyPart="Lower Body", movementPattern="lunge",
        movementPatternRaw="Knee Dominant (Unilateral)", modality="barbell",
        equipment="Barbell", primaryMuscle="Quads",
        primaryMuscles=["Quads", "Glutes"], secondaryMuscles=["Hamstrings"],
        stabilizers=["Adductors", "Abs", "Erectors"], cnsScore=5,
        recoveryImpact=3, defaultRestSeconds=150,
        similar=["Dumbbell Step-Up", "Patrick Step-Up", "Bulgarian Split Squat"],
    ),
    _row(
        slug="calf-press", name="Calf Press", aka=["Leg Press Calf Raise"],
        bodyPart="Lower Body", category="hypertrophy",
        movementPattern="isolation",
        movementPatternRaw="Isolation (Ankle plantarflexion)",
        modality="machine_plate", equipment="Machine", primaryMuscle="Calves",
        primaryMuscles=["Calves"], cnsScore=2, recoveryImpact=1,
        defaultRestSeconds=75,
        similar=["Standing Calf Raise", "Seated Calf Raise",
                 "Donkey Calf Raise"],
    ),
    _row(
        slug="cable-glute-kickback", name="Cable Glute Kickback",
        aka=["Cable Kickback"], bodyPart="Lower Body", category="hypertrophy",
        movementPattern="hinge",
        movementPatternRaw="Hip Hinge (Glute isolation)", modality="cable",
        equipment="Cable", primaryMuscle="Glutes", primaryMuscles=["Glutes"],
        secondaryMuscles=["Hamstrings"], stabilizers=["Erectors"], cnsScore=2,
        recoveryImpact=1, defaultRestSeconds=75,
        similar=["Machine Glute Kickback", "Barbell Hip Thrust", "Frog Pump"],
    ),
    _row(
        slug="burpee", name="Burpee", aka=["Squat Thrust"],
        bodyPart="Core & Abs", category="calisthenics", movementPattern="other",
        movementPatternRaw="Full Body (Explosive)", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Abs", primaryMuscles=["Abs"],
        secondaryMuscles=["Quads", "Chest"], stabilizers=["Obliques"],
        cnsScore=4, recoveryImpact=2, loggingMetric="reps",
        supportsWeightedBodyweight=True, defaultRestSeconds=60,
        similar=["TRX Burpee", "Jump Squat", "Box Jump"],
    ),
]


# ── Conditioning, Olympic and mobility coverage ─────────────────────────────
# The source spreadsheet was a hypertrophy/powerlifting document, so three of
# the catalog's seven declared categories were effectively empty: `cardio` held
# three rows (a jump rope and two treadmill speeds), `crossfit` held one (the
# sled push), and `mobility` held none at all despite being offered in the
# picker, the custom-exercise builder and the Supabase default.
#
# Category choice: the Olympic lifts are filed under `crossfit` rather than
# `strength`. The catalog already reserves `powerlifting` for the three
# competition lifts, so `crossfit` is the sibling bucket where a user of this
# app looks for a clean or a snatch — and leaving them under `strength` buried
# them among 245 rows. Aliases carry the alternative vocabulary either way.
def _cardio(slug, name, aka, primary, primaries, secondaries, equipment,
            metric, cns, recovery, rest=90):
    return _row(
        slug=slug, name=name, aka=aka, bodyPart="Full Body", category="cardio",
        movementPattern="other", movementPatternRaw="Cardio", modality="other",
        equipment=equipment, primaryMuscle=primary, primaryMuscles=primaries,
        secondaryMuscles=secondaries, stabilizers=["Core"], cnsScore=cns,
        recoveryImpact=recovery, loggingMetric=metric,
        defaultRestSeconds=rest,
    )


ADDITIONS += [
    # ── Cardio: machines ────────────────────────────────────────────────────
    _cardio(
        "rowing-erg", "Rowing Erg",
        ["Concept2 Rower", "Row Erg", "Indoor Rower", "Erg", "Rowing Machine"],
        "Back", ["Lats", "Quads"], ["Glutes", "Hamstrings", "Biceps"],
        "Rower", "time_distance", 5, 3,
    ),
    _cardio(
        "air-bike", "Air Bike",
        ["Assault Bike", "Echo Bike", "Fan Bike", "Airdyne"],
        "Quads", ["Quads", "Hamstrings"], ["Front Delts", "Lats", "Calves"],
        "Air Bike", "time_calories", 5, 3,
    ),
    _cardio(
        "ski-erg", "Ski Erg", ["SkiErg", "Concept2 SkiErg"],
        "Back", ["Lats", "Triceps"], ["Abs", "Rear Delts"],
        "Ski Erg", "time_distance", 4, 3,
    ),
    _cardio(
        "stationary-bike", "Stationary Bike",
        ["Exercise Bike", "Spin Bike", "Upright Bike", "Cycling Machine"],
        "Quads", ["Quads"], ["Glutes", "Hamstrings", "Calves"],
        "Stationary Bike", "time_distance", 3, 2,
    ),
    _cardio(
        "elliptical", "Elliptical", ["Cross Trainer", "Elliptical Trainer"],
        "Quads", ["Quads", "Glutes"], ["Hamstrings", "Calves"],
        "Elliptical", "time_distance", 3, 2,
    ),
    _cardio(
        "stair-climber", "Stair Climber",
        ["StairMaster", "Stepmill", "Stair Machine"],
        "Glutes", ["Glutes", "Quads"], ["Hamstrings", "Calves"],
        "Stair Climber", "time", 4, 3,
    ),
    _cardio(
        "incline-treadmill-walk", "Incline Treadmill Walk",
        ["Incline Walk", "12-3-30"],
        "Glutes", ["Glutes", "Calves"], ["Quads", "Hamstrings"],
        "Treadmill", "time_distance", 2, 1, rest=60,
    ),
    # ── Cardio: outdoor and field ───────────────────────────────────────────
    _cardio(
        "outdoor-run", "Outdoor Run", ["Running", "Road Run", "Trail Run"],
        "Quads", ["Quads", "Hamstrings"], ["Glutes", "Calves"],
        "Other", "time_distance", 5, 4,
    ),
    _cardio(
        "outdoor-cycling", "Outdoor Cycling",
        ["Road Cycling", "Bike Ride", "Cycling"],
        "Quads", ["Quads"], ["Glutes", "Hamstrings", "Calves"],
        "Other", "time_distance", 3, 2,
    ),
    _cardio(
        "swimming", "Swimming", ["Swim", "Lap Swimming"],
        "Back", ["Lats"], ["Front Delts", "Triceps", "Core"],
        "Other", "time_distance", 4, 3,
    ),
    _cardio(
        "sprint", "Sprint", ["Sprints", "Track Sprint", "Flat Sprint"],
        "Hamstrings", ["Hamstrings", "Glutes"], ["Quads", "Calves"],
        "Other", "distance", 8, 4, rest=180,
    ),
    _cardio(
        "hill-sprint", "Hill Sprint", ["Hill Sprints", "Incline Sprint"],
        "Glutes", ["Glutes", "Quads"], ["Hamstrings", "Calves"],
        "Other", "distance", 8, 4, rest=180,
    ),
    _cardio(
        "shuttle-run", "Shuttle Run", ["Suicides", "Beep Test", "Line Drill"],
        "Quads", ["Quads", "Hamstrings"], ["Glutes", "Calves", "Adductors"],
        "Other", "time", 6, 3, rest=120,
    ),
    _cardio(
        "battle-ropes", "Battle Ropes", ["Battle Rope Waves", "Rope Waves"],
        "Shoulders", ["Front Delts", "Side Delts"], ["Lats", "Abs", "Forearms"],
        "Battle Ropes", "time", 4, 2, rest=60,
    ),
    _cardio(
        "double-unders", "Double Unders", ["Double Under", "DU", "Skipping"],
        "Calves", ["Calves"], ["Quads", "Forearms"],
        "Jump Rope", "reps_time", 4, 2, rest=60,
    ),

    # ── Olympic lifts ───────────────────────────────────────────────────────
    _row(
        slug="power-clean", name="Power Clean", aka=["Clean (Power)"],
        bodyPart="Full Body", category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="barbell",
        equipment="Barbell", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Hamstrings"],
        secondaryMuscles=["Traps", "Quads", "Erectors"],
        stabilizers=["Forearms", "Abs"], cnsScore=9, recoveryImpact=5,
        defaultRestSeconds=180,
        similar=["Hang Power Clean", "Squat Clean", "Clean & Jerk",
                 "Power Snatch"],
    ),
    _row(
        slug="hang-power-clean", name="Hang Power Clean",
        aka=["Hang Clean"], bodyPart="Full Body", category="crossfit",
        movementPattern="hinge", movementPatternRaw="Explosive Hip Extension",
        modality="barbell", equipment="Barbell", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Hamstrings"],
        secondaryMuscles=["Traps", "Quads"], stabilizers=["Forearms", "Abs"],
        cnsScore=8, recoveryImpact=4, defaultRestSeconds=180,
        similar=["Power Clean", "Squat Clean"],
    ),
    _row(
        slug="squat-clean", name="Squat Clean", aka=["Full Clean", "Clean"],
        bodyPart="Full Body", category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="barbell",
        equipment="Barbell", primaryMuscle="Quads",
        primaryMuscles=["Quads", "Glutes"],
        secondaryMuscles=["Hamstrings", "Traps", "Erectors"],
        stabilizers=["Forearms", "Abs"], cnsScore=9, recoveryImpact=5,
        defaultRestSeconds=240,
        similar=["Power Clean", "Clean & Jerk", "Front Squat"],
    ),
    _row(
        slug="clean-and-jerk", name="Clean & Jerk", aka=["C&J", "Clean Jerk"],
        bodyPart="Full Body", category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension + Overhead",
        modality="barbell", equipment="Barbell", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Quads"],
        secondaryMuscles=["Front Delts", "Traps", "Triceps"],
        stabilizers=["Abs", "Erectors"], cnsScore=10, recoveryImpact=5,
        defaultRestSeconds=300,
        similar=["Squat Clean", "Push Jerk", "Split Jerk"],
    ),
    _row(
        slug="power-snatch", name="Power Snatch", aka=["Snatch (Power)"],
        bodyPart="Full Body", category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="barbell",
        equipment="Barbell", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Hamstrings"],
        secondaryMuscles=["Traps", "Side Delts", "Quads"],
        stabilizers=["Abs", "Forearms"], cnsScore=9, recoveryImpact=5,
        defaultRestSeconds=180,
        similar=["Squat Snatch", "Hang Snatch", "Power Clean"],
    ),
    _row(
        slug="hang-snatch", name="Hang Snatch", aka=["Hang Power Snatch"],
        bodyPart="Full Body", category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="barbell",
        equipment="Barbell", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Hamstrings"],
        secondaryMuscles=["Traps", "Side Delts"],
        stabilizers=["Abs", "Forearms"], cnsScore=8, recoveryImpact=4,
        defaultRestSeconds=180, similar=["Power Snatch", "Squat Snatch"],
    ),
    _row(
        slug="squat-snatch", name="Squat Snatch", aka=["Full Snatch", "Snatch"],
        bodyPart="Full Body", category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="barbell",
        equipment="Barbell", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Quads"],
        secondaryMuscles=["Traps", "Side Delts", "Hamstrings"],
        stabilizers=["Abs", "Forearms"], cnsScore=10, recoveryImpact=5,
        defaultRestSeconds=240,
        similar=["Power Snatch", "Overhead Squat", "Snatch Grip Deadlift"],
    ),
    _row(
        slug="muscle-snatch", name="Muscle Snatch", aka=[],
        bodyPart="Shoulders", category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="barbell",
        equipment="Barbell", primaryMuscle="Shoulders",
        primaryMuscles=["Side Delts", "Traps"],
        secondaryMuscles=["Glutes", "Hamstrings"], stabilizers=["Abs"],
        cnsScore=7, recoveryImpact=3, defaultRestSeconds=150,
        similar=["Power Snatch", "High Pull"],
    ),
    _row(
        slug="overhead-squat", name="Overhead Squat", aka=["OHS"],
        bodyPart="Lower Body", category="crossfit", movementPattern="squat",
        movementPatternRaw="Knee Dominant (Overhead)", modality="barbell",
        equipment="Barbell", primaryMuscle="Quads",
        primaryMuscles=["Quads", "Glutes"],
        secondaryMuscles=["Side Delts", "Traps", "Erectors"],
        stabilizers=["Abs", "Obliques"], cnsScore=8, recoveryImpact=4,
        defaultRestSeconds=180,
        similar=["Squat Snatch", "Front Squat", "Barbell Back Squat"],
    ),
    _row(
        slug="push-jerk", name="Push Jerk", aka=["Power Jerk"],
        bodyPart="Shoulders", category="crossfit",
        movementPattern="vertical_push",
        movementPatternRaw="Vertical Push (Explosive)", modality="barbell",
        equipment="Barbell", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts"],
        secondaryMuscles=["Triceps", "Traps", "Quads"], stabilizers=["Abs"],
        cnsScore=8, recoveryImpact=4, defaultRestSeconds=240,
        similar=["Push Press", "Split Jerk", "Overhead Press"],
    ),
    _row(
        slug="split-jerk", name="Split Jerk", aka=["Jerk"],
        bodyPart="Shoulders", category="crossfit",
        movementPattern="vertical_push",
        movementPatternRaw="Vertical Push (Explosive)", modality="barbell",
        equipment="Barbell", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts"],
        secondaryMuscles=["Triceps", "Traps", "Quads", "Glutes"],
        stabilizers=["Abs", "Adductors"], cnsScore=9, recoveryImpact=4,
        defaultRestSeconds=240, similar=["Push Jerk", "Clean & Jerk"],
    ),
    _row(
        slug="thruster", name="Thruster", aka=["Barbell Thruster"],
        bodyPart="Full Body", category="crossfit",
        movementPattern="vertical_push",
        movementPatternRaw="Front Squat to Overhead Press", modality="barbell",
        equipment="Barbell", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts", "Quads"],
        secondaryMuscles=["Glutes", "Triceps"], stabilizers=["Abs"],
        cnsScore=8, recoveryImpact=4, defaultRestSeconds=180,
        similar=["Front Squat", "Push Press", "Wall Ball"],
    ),

    # ── CrossFit gymnastics ─────────────────────────────────────────────────
    _row(
        slug="bar-muscle-up", name="Bar Muscle-Up", aka=["BMU"],
        bodyPart="Back", category="crossfit", movementPattern="vertical_pull",
        movementPatternRaw="Vertical Pull to Push", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Back",
        primaryMuscles=["Lats"], secondaryMuscles=["Chest", "Triceps", "Biceps"],
        stabilizers=["Abs", "Forearms"], cnsScore=7, recoveryImpact=3,
        loggingMetric="reps", supportsWeightedBodyweight=True,
        defaultRestSeconds=180,
        similar=["Kipping Muscle-Up", "Strict Muscle-Up", "Chest-to-Bar Pull-Up"],
    ),
    _row(
        slug="chest-to-bar-pull-up", name="Chest-to-Bar Pull-Up",
        aka=["C2B", "Chest to Bar"], bodyPart="Back", category="crossfit",
        movementPattern="vertical_pull", movementPatternRaw="Vertical Pull",
        modality="bodyweight", equipment="Bodyweight", primaryMuscle="Back",
        primaryMuscles=["Lats"], secondaryMuscles=["Biceps", "Rhomboids"],
        stabilizers=["Abs", "Forearms"], cnsScore=5, recoveryImpact=2,
        loggingMetric="reps", supportsWeightedBodyweight=True,
        defaultRestSeconds=150,
        similar=["Kipping Pull-Up", "Pull-Up", "Bar Muscle-Up"],
    ),
    _row(
        slug="kipping-pull-up", name="Kipping Pull-Up", aka=["Kip Pull-Up"],
        bodyPart="Back", category="crossfit", movementPattern="vertical_pull",
        movementPatternRaw="Vertical Pull (Kipping)", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Back", primaryMuscles=["Lats"],
        secondaryMuscles=["Biceps", "Abs"], stabilizers=["Forearms"],
        cnsScore=4, recoveryImpact=2, loggingMetric="reps",
        supportsWeightedBodyweight=True, defaultRestSeconds=120,
        similar=["Butterfly Pull-Up", "Pull-Up", "Chest-to-Bar Pull-Up"],
    ),
    _row(
        slug="butterfly-pull-up", name="Butterfly Pull-Up", aka=["Butterfly"],
        bodyPart="Back", category="crossfit", movementPattern="vertical_pull",
        movementPatternRaw="Vertical Pull (Kipping)", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Back", primaryMuscles=["Lats"],
        secondaryMuscles=["Biceps", "Abs"], stabilizers=["Forearms"],
        cnsScore=4, recoveryImpact=2, loggingMetric="reps",
        supportsWeightedBodyweight=True, defaultRestSeconds=120,
        similar=["Kipping Pull-Up", "Chest-to-Bar Pull-Up"],
    ),
    _row(
        slug="rope-climb", name="Rope Climb", aka=["Legless Rope Climb"],
        bodyPart="Back", category="crossfit", movementPattern="vertical_pull",
        movementPatternRaw="Vertical Pull (Climbing)", modality="other",
        equipment="Climbing Rope", primaryMuscle="Back",
        primaryMuscles=["Lats", "Forearms"],
        secondaryMuscles=["Biceps", "Abs"], stabilizers=["Hip Flexors"],
        cnsScore=6, recoveryImpact=3, loggingMetric="reps",
        defaultRestSeconds=180, similar=["Pull-Up", "Towel Pull-Up"],
    ),
    _row(
        slug="wall-walk", name="Wall Walk", aka=["Wall Climb"],
        bodyPart="Shoulders", category="crossfit",
        movementPattern="vertical_push",
        movementPatternRaw="Vertical Push (Inverted)", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts"], secondaryMuscles=["Triceps", "Abs"],
        stabilizers=["Serratus"], cnsScore=5, recoveryImpact=2,
        loggingMetric="reps", defaultRestSeconds=120,
        similar=["Handstand Push-Up", "Handstand Walk"],
    ),
    _row(
        slug="handstand-walk", name="Handstand Walk", aka=["HS Walk"],
        bodyPart="Shoulders", category="crossfit",
        movementPattern="vertical_push",
        movementPatternRaw="Vertical Push (Inverted)", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts", "Side Delts"],
        secondaryMuscles=["Triceps", "Traps"], stabilizers=["Abs", "Serratus"],
        cnsScore=6, recoveryImpact=2, loggingMetric="distance",
        defaultRestSeconds=120, similar=["Wall Walk", "Handstand Push-Up"],
    ),

    # ── CrossFit conditioning ───────────────────────────────────────────────
    _row(
        slug="wall-ball", name="Wall Ball", aka=["Wall Ball Shot", "WBS"],
        bodyPart="Full Body", category="crossfit", movementPattern="squat",
        movementPatternRaw="Squat to Throw", modality="other",
        equipment="Medicine Ball", primaryMuscle="Quads",
        primaryMuscles=["Quads", "Front Delts"],
        secondaryMuscles=["Glutes", "Triceps"], stabilizers=["Abs"],
        cnsScore=5, recoveryImpact=3, defaultRestSeconds=90,
        similar=["Thruster", "Front Squat", "Ball Slam"],
    ),
    _row(
        slug="ball-slam", name="Ball Slam", aka=["Medicine Ball Slam", "Slam Ball"],
        bodyPart="Core & Abs", category="crossfit", movementPattern="core",
        movementPatternRaw="Explosive Trunk Flexion", modality="other",
        equipment="Medicine Ball", primaryMuscle="Abs",
        primaryMuscles=["Abs"], secondaryMuscles=["Lats", "Front Delts"],
        stabilizers=["Obliques"], cnsScore=4, recoveryImpact=2,
        defaultRestSeconds=60, similar=["Wall Ball", "Cable Woodchopper"],
    ),
    _row(
        slug="box-jump-over", name="Box Jump Over", aka=["BJO"],
        bodyPart="Lower Body", category="crossfit", movementPattern="squat",
        movementPatternRaw="Explosive Knee Dominant", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Quads",
        primaryMuscles=["Quads"], secondaryMuscles=["Glutes", "Calves"],
        stabilizers=["Abs"], cnsScore=6, recoveryImpact=3,
        loggingMetric="reps", defaultRestSeconds=120,
        similar=["Box Jump", "Burpee Box Jump Over"],
    ),
    _row(
        slug="burpee-box-jump-over", name="Burpee Box Jump Over",
        aka=["BBJO"], bodyPart="Full Body", category="crossfit",
        movementPattern="other", movementPatternRaw="Full Body Conditioning",
        modality="bodyweight", equipment="Bodyweight", primaryMuscle="Quads",
        primaryMuscles=["Quads", "Chest"],
        secondaryMuscles=["Glutes", "Triceps", "Calves"],
        stabilizers=["Abs"], cnsScore=6, recoveryImpact=3,
        loggingMetric="reps", defaultRestSeconds=120,
        similar=["Burpee", "Box Jump Over"],
    ),
    _row(
        slug="devils-press", name="Devil's Press", aka=["Devil Press"],
        bodyPart="Full Body", category="crossfit", movementPattern="other",
        movementPatternRaw="Burpee to Overhead", modality="dumbbell",
        equipment="Dumbbell", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts", "Glutes"],
        secondaryMuscles=["Chest", "Hamstrings", "Triceps"],
        stabilizers=["Abs"], cnsScore=7, recoveryImpact=4,
        defaultRestSeconds=150, similar=["Man Maker", "Dumbbell Snatch",
                                         "Burpee"],
    ),
    _row(
        slug="dumbbell-snatch", name="Dumbbell Snatch",
        aka=["DB Snatch", "Single-Arm Dumbbell Snatch"], bodyPart="Full Body",
        category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="dumbbell",
        equipment="Dumbbell", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Hamstrings"],
        secondaryMuscles=["Side Delts", "Traps"], stabilizers=["Abs", "Obliques"],
        cnsScore=7, recoveryImpact=3, defaultRestSeconds=120,
        similar=["Power Snatch", "Devil's Press", "Kettlebell Swing"],
    ),
    _row(
        slug="man-maker", name="Man Maker", aka=["Manmaker"],
        bodyPart="Full Body", category="crossfit", movementPattern="other",
        movementPatternRaw="Full Body Complex", modality="dumbbell",
        equipment="Dumbbell", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts", "Chest"],
        secondaryMuscles=["Lats", "Quads", "Triceps"], stabilizers=["Abs"],
        cnsScore=7, recoveryImpact=4, defaultRestSeconds=180,
        similar=["Devil's Press", "Burpee"],
    ),
    _row(
        slug="sandbag-clean", name="Sandbag Clean",
        aka=["Sandbag Clean to Shoulder", "Bag Clean"], bodyPart="Full Body",
        category="crossfit", movementPattern="hinge",
        movementPatternRaw="Explosive Hip Extension", modality="other",
        equipment="Sandbag", primaryMuscle="Glutes",
        primaryMuscles=["Glutes", "Hamstrings"],
        secondaryMuscles=["Erectors", "Traps", "Biceps"],
        stabilizers=["Abs", "Forearms"], cnsScore=7, recoveryImpact=4,
        defaultRestSeconds=180, similar=["Power Clean", "Atlas Stone Lift"],
    ),
    _row(
        slug="sled-rope-pull", name="Sled Rope Pull",
        aka=["Sled Pull", "Rope Sled Pull", "Hand-Over-Hand Sled Pull"],
        bodyPart="Back", category="crossfit", movementPattern="carry",
        movementPatternRaw="Horizontal Pull (Loaded)", modality="other",
        equipment="Sled/Yoke", primaryMuscle="Back",
        primaryMuscles=["Lats", "Biceps"],
        secondaryMuscles=["Rhomboids", "Rear Delts", "Forearms"],
        stabilizers=["Abs", "Erectors"], cnsScore=5, recoveryImpact=3,
        loggingMetric="weight_distance", defaultRestSeconds=120,
        similar=["Sled Drag", "Sled Push", "Barbell Row"],
    ),

    # ── Mobility ────────────────────────────────────────────────────────────
    _row(
        slug="90-90-hip-switch", name="90-90 Hip Switch",
        aka=["90/90 Hip Switch", "90 90 Hip Rotation"], bodyPart="Lower Body",
        category="mobility", movementPattern="other",
        movementPatternRaw="Hip Rotation", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Glutes",
        primaryMuscles=["Glutes"], secondaryMuscles=["Adductors", "Hip Flexors"],
        stabilizers=["Abs"], cnsScore=1, recoveryImpact=1,
        loggingMetric="reps", defaultRestSeconds=45,
        similar=["Cossack Squat", "Couch Stretch"],
    ),
    _row(
        slug="couch-stretch", name="Couch Stretch",
        aka=["Quad and Hip Flexor Stretch"], bodyPart="Lower Body",
        category="mobility", movementPattern="other",
        movementPatternRaw="Hip Flexor Stretch", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Quads",
        primaryMuscles=["Hip Flexors", "Quads"], secondaryMuscles=[],
        stabilizers=["Abs"], cnsScore=1, recoveryImpact=1,
        loggingMetric="time", defaultRestSeconds=30,
        similar=["90-90 Hip Switch", "ATG Split Squat"],
    ),
    _row(
        slug="thoracic-extension", name="Thoracic Extension",
        aka=["Foam Roller Thoracic Opener", "T-Spine Extension"],
        bodyPart="Back", category="mobility", movementPattern="other",
        movementPatternRaw="Thoracic Mobility", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Back",
        primaryMuscles=["Erectors"], secondaryMuscles=["Rhomboids"],
        stabilizers=["Abs"], cnsScore=1, recoveryImpact=1,
        loggingMetric="time", defaultRestSeconds=30,
        similar=["Wall Slide", "Band Shoulder Dislocate"],
    ),
    _row(
        slug="atg-split-squat", name="ATG Split Squat",
        aka=["Ass-to-Grass Split Squat", "Deep Split Squat"],
        bodyPart="Lower Body", category="mobility", movementPattern="lunge",
        movementPatternRaw="Knee Dominant (Deep Range)", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Quads",
        primaryMuscles=["Quads"], secondaryMuscles=["Glutes", "Hip Flexors"],
        stabilizers=["Abs"], cnsScore=2, recoveryImpact=1,
        loggingMetric="reps", supportsWeightedBodyweight=True,
        defaultRestSeconds=60,
        similar=["Bulgarian Split Squat", "Couch Stretch"],
    ),
    _row(
        slug="jefferson-curl", name="Jefferson Curl", aka=["Jefferson Roll"],
        bodyPart="Back", category="mobility", movementPattern="hinge",
        movementPatternRaw="Spinal Flexion (Loaded)", modality="dumbbell",
        equipment="Dumbbell", primaryMuscle="Hamstrings",
        primaryMuscles=["Hamstrings", "Erectors"], secondaryMuscles=["Glutes"],
        stabilizers=["Abs"], cnsScore=2, recoveryImpact=2,
        defaultRestSeconds=60, similar=["Romanian Deadlift", "Good Morning"],
    ),
    _row(
        slug="deep-squat-hold", name="Deep Squat Hold",
        aka=["Third World Squat", "Malasana"], bodyPart="Lower Body",
        category="mobility", movementPattern="squat",
        movementPatternRaw="Knee Dominant (Isometric)", modality="bodyweight",
        equipment="Bodyweight", primaryMuscle="Adductors",
        primaryMuscles=["Adductors", "Glutes"], secondaryMuscles=["Quads"],
        stabilizers=["Abs", "Tibialis"], cnsScore=1, recoveryImpact=1,
        loggingMetric="time", defaultRestSeconds=45,
        similar=["Cossack Squat", "Couch Stretch"],
    ),
    _row(
        slug="band-shoulder-dislocate", name="Band Shoulder Dislocate",
        aka=["Shoulder Dislocates", "Band Pass-Through"], bodyPart="Shoulders",
        category="mobility", movementPattern="other",
        movementPatternRaw="Shoulder Mobility", modality="band",
        equipment="Band", primaryMuscle="Shoulders",
        primaryMuscles=["Front Delts", "Rear Delts"], secondaryMuscles=["Traps"],
        stabilizers=["Serratus"], cnsScore=1, recoveryImpact=1,
        loggingMetric="reps", defaultRestSeconds=30,
        similar=["Wall Slide", "Thoracic Extension"],
    ),
    _row(
        slug="wall-slide", name="Wall Slide", aka=["Wall Angel"],
        bodyPart="Shoulders", category="mobility",
        movementPattern="vertical_push", movementPatternRaw="Scapular Mobility",
        modality="bodyweight", equipment="Bodyweight",
        primaryMuscle="Shoulders", primaryMuscles=["Traps", "Rear Delts"],
        secondaryMuscles=["Serratus"], stabilizers=["Abs"], cnsScore=1,
        recoveryImpact=1, loggingMetric="reps", defaultRestSeconds=30,
        similar=["Band Shoulder Dislocate", "Thoracic Extension"],
    ),
]


def apply(catalog):
    """Returns (catalog, report). Idempotent."""
    by_slug = OrderedDict((r["slug"], r) for r in catalog)
    report = {"fixed": [], "renamed": [], "merged": [], "added": [],
              "already_clean": []}

    # 1. Equipment fixes.
    for slug, overrides in FIELD_FIXES.items():
        row = by_slug.get(slug)
        if row is None:
            report["already_clean"].append(f"fix: {slug} not in catalog")
            continue
        changed = {k: v for k, v in overrides.items() if row.get(k) != v}
        if not changed:
            continue
        was = "/".join(f"{row.get(k)}" for k in changed)
        now = "/".join(f"{v}" for v in changed.values())
        report["fixed"].append(f"{row['name']}: {was} -> {now}")
        row.update(overrides)

    # 2. Renames. The old name survives as an alias so search and program
    #    import keep resolving it.
    renamed_names = {}
    for slug, (new_name, extra_aka) in RENAMES.items():
        row = by_slug.get(slug)
        if row is None:
            report["already_clean"].append(f"rename: {slug} not in catalog")
            continue
        if row["name"] != new_name:
            report["renamed"].append(f"{row['name']} -> {new_name}")
            renamed_names[row["name"]] = new_name
            _add_aliases(row, [row["name"]])
            row["name"] = new_name
        _add_aliases(row, extra_aka)

    # 3. Merges.
    merged_names = {}
    for loser_slug, winner_slug in MERGES:
        loser = by_slug.get(loser_slug)
        winner = by_slug.get(winner_slug)
        if winner is None:
            raise SystemExit(
                f"merge target {winner_slug!r} is not in the catalog"
            )
        if loser is None:
            continue  # already applied
        report["merged"].append(f"{loser['name']} -> {winner['name']}")
        merged_names[loser["name"]] = winner["name"]
        _add_aliases(winner, [loser["name"], *loser.get("aka", [])])
        # A merged bodyweight row often carried the only "weighted" spelling of
        # the movement, so keep the winner able to log added load.
        if loser.get("supportsWeightedBodyweight"):
            winner["supportsWeightedBodyweight"] = True
        del by_slug[loser_slug]

    # 4. Additions.
    for row in ADDITIONS:
        if row["slug"] in by_slug:
            continue
        report["added"].append(row["name"])
        by_slug[row["slug"]] = json.loads(json.dumps(row))

    # 5. Repair cross-references. `similar` holds names, so a rename or merge
    #    leaves dangling strings behind.
    replacements = {**renamed_names, **merged_names}
    names = {r["name"] for r in by_slug.values()}
    for row in by_slug.values():
        similar = []
        for name in row.get("similar", []):
            name = replacements.get(name, name)
            if name == row["name"] or name in similar:
                continue
            similar.append(name)
        row["similar"] = similar
        # An alias that equals some *other* exercise's real name makes name
        # lookup ambiguous — the merge engine and program CSV import both
        # resolve by name. The real row wins; the alias goes.
        kept = []
        for alias in row.get("aka", []):
            if alias != row["name"] and alias in names:
                report["already_clean"].append(
                    f"dropped alias {alias!r} on {row['name']} "
                    f"(collides with a real exercise)"
                )
                continue
            kept.append(alias)
        row["aka"] = kept

    return list(by_slug.values()), report


def _add_aliases(row, aliases):
    existing = {a.lower() for a in row.get("aka", [])}
    if row["name"].lower() in existing:
        existing.discard(row["name"].lower())
    out = list(row.get("aka", []))
    for alias in aliases:
        alias = alias.strip()
        if not alias or alias.lower() == row["name"].lower():
            continue
        if alias.lower() in existing:
            continue
        existing.add(alias.lower())
        out.append(alias)
    row["aka"] = out


def main():
    _assert_no_duplicate_keys()
    write = "--write" in sys.argv
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)

    before = len(catalog)
    catalog, report = apply(catalog)

    for heading, key in (
        ("equipment fixes", "fixed"),
        ("renames", "renamed"),
        ("merges", "merged"),
        ("additions", "added"),
    ):
        rows = report[key]
        print(f"{heading} ({len(rows)}):")
        for line in rows:
            print(f"  {line}")
        print()
    for note in report["already_clean"]:
        print(f"note: {note}")

    print(f"catalog rows: {before} -> {len(catalog)}")

    if not write:
        print("\n(dry run — pass --write to apply)")
        return

    with open(CATALOG, "w", encoding="utf-8", newline="\n") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"\nwrote {CATALOG}")
    print("now run: python tool/derive_movements.py --write")


if __name__ == "__main__":
    main()
