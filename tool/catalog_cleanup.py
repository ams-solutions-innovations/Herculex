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

import json
import sys
from collections import OrderedDict

CATALOG = "assets/data/exercises.json"


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
    # You are holding a dumbbell. Bodyweight would hide the load field.
    "dumbbell-glute-bridge": {"equipment": "Dumbbell", "modality": "dumbbell"},

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
    "suitcase-carry": {"equipment": "Dumbbell", "modality": "dumbbell"},
    "waiter-s-carry": {"equipment": "Kettlebell", "modality": "kettlebell"},
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
