#!/usr/bin/env python3
"""Derive the movement layer from the exercise catalog.

A "movement" is what the user thinks they are picking ("Row", "Bench Press").
The catalog stores one row per real exercise, because a Barbell Row and a Ring
Row genuinely differ in logging metric, CNS cost and stabilisers. This script
clusters those rows into movements so the picker can collapse them, and unions
each cluster's modalities into the set of equipment that movement can actually
be performed with.

That union is what replaces the hardcoded eight-member equipment list that used
to offer a Smith Machine option on a seated hamstring curl.

Usage:
    python tool/derive_movements.py            # report only
    python tool/derive_movements.py --write    # write movements.json + slugs
"""

import json
import re
import sys
from collections import OrderedDict, defaultdict

CATALOG = "assets/data/exercises.json"
MOVEMENTS = "assets/data/movements.json"

# Equipment words stripped from a name to find its base movement. Mirrors
# ExerciseImporter._equipmentTokens; longest first so "swiss bar" is removed
# before "bar".
EQUIPMENT_TOKENS = [
    "smith machine", "cambered bar", "duffalo bar", "safety bar", "swiss bar",
    "neck harness", "plate-loaded", "iso-lateral", "band-assisted", "axle bar",
    "trap bar", "hex bar", "suspension trainer", "ez bar", "ez-bar",
    "landmine", "meadows", "kettlebell", "dumbbell", "barbell", "machine",
    "pendulum", "banded", "cable", "smith", "plate", "hammer", "sled", "yoke",
    "rings", "ring", "trx", "band", "db",
]

# Words that describe *how* a movement is loaded or assisted rather than which
# movement it is. Stripped so "Weighted Dip", "Band-Assisted Dip" and
# "Chest Dips" land in one movement.
LOAD_TOKENS = ["weighted", "assisted", "bodyweight"]

# Words that say "this is the plain version", which is the one thing a movement
# name never needs to say. Left in, they excluded the plain row from its own
# family: "Standard Push-Up" clustered as `standard push up` while every ring
# and TRX push-up clustered as `push up`, so the group's bare "Push Up" alias
# went to a Ring Push-Up and searching "push up" returned the rings first.
PLAINNESS_TOKENS = ["standard", "conventional", "regular", "classic"]

# Parenthetical qualifiers that pick a *grip, attachment or start position* on a
# movement the lifter is already doing on one machine. Six Lat Pulldown rows,
# five Tricep Pushdowns and four Seated Cable Rows are all Cable — they are not
# equipment variants, so `allowedEquipment` never collapsed them and the picker
# listed each grip as a top-level exercise.
#
# Matched as whole parenthetical content, not substrings, so a meaningful
# qualifier is never mistaken for a grip: "Hack Squat (Machine)" names the
# equipment, "L-Sit (floor)" names the apparatus, and "Chin-Up (Supinated)" is
# the only grip a chin-up has. Those keep their own rows.
VARIANT_QUALIFIERS = {
    # grip width
    "wide grip", "wide", "super wide", "narrow grip", "narrow", "close grip",
    "neutral grip", "neutral single", "underhand grip", "overhand grip",
    "reverse grip", "reverse",
    # cable / pulldown attachments
    "rope", "v-bar", "straight bar", "ez bar", "d-handle",
    # bar height / range
    "below knee", "above knee", "mid-thigh", "low handles", "high handles",
    "high to low", "low to high",
    # foot / body position
    "feet elevated", "feet on floor", "feet on floor, wide grip",
    "feet strapped", "knees",
}

# Synonyms collapsed so naming drift does not split a movement. "Bicep Curl"
# and "Curl" were separate families purely because of the extra word.
# Tie-break for equally plain names: which equipment a lifter pictures when they
# hear the bare movement name. "Cable Lateral Raise", "Dumbbell Lateral Raise"
# and "Machine Lateral Raise" are all three words, so without this the group's
# public face was decided alphabetically.
MODALITY_RANK = {
    "barbell": 0,
    "dumbbell": 1,
    "bodyweight": 2,
    "kettlebell": 3,
    "cable": 4,
    "machine_selectorized": 5,
    "machine_plate": 6,
    "smith": 7,
    "band": 8,
    "other": 9,
}

# Movements where the lexical rules below pick the wrong face for the group.
# "Barbell Back Squat" is three words and loses to "Dumbbell Squat" on the
# shorter-name rule, but it is unambiguously what "squat" means — and the
# canonical member is what a bare-name search lands on.
CANONICAL_OVERRIDES = {
    "squat-squat": "barbell-back-squat",
}

NAME_SYNONYMS = [
    (r"\bbench press\b", "press"),
    # A name *ending* in "bench" means the press ("Smith Machine Bench",
    # "Incline Barbell Bench"). Anchored to the end so "Bench Dip" and
    # "Ab Crunch Bench (Angled)" are left alone.
    (r"\bbench$", "press"),
    # An unqualified "Squat" means the back squat, so "Barbell Back Squat" was
    # clustering on its own while every bar variant of the same movement sat in
    # the generic "squat" group. Front and box squats keep their own qualifier
    # and stay separate.
    (r"\bback squat\b", "squat"),
    (r"\bbicep curl\b", "curl"),
    (r"\bbiceps curl\b", "curl"),
    (r"\btricep(s)? extension\b", "triceps extension"),
    (r"\btricep(s)? pushdown\b", "triceps pushdown"),
    (r"\bohp\b", "overhead press"),
    (r"\bflye?\b", "fly"),
    (r"\bdips\b", "dip"),
    (r"\brdl\b", "romanian deadlift"),
]


def strip_variant_qualifier(name):
    """Drops a parenthetical that only names a grip, attachment or position."""
    def repl(match):
        inner = match.group(1).strip().lower()
        return "" if inner in VARIANT_QUALIFIERS else match.group(0)

    return re.sub(r"\(([^)]*)\)", repl, name).strip()


def _spaced(name):
    """Lowercased, space-padded, punctuation-flattened name for token tests."""
    n = " " + strip_variant_qualifier(name).lower() + " "
    return n.replace("(", " ").replace(")", " ").replace("-", " ")


def names_equipment(name):
    """True when the name states the apparatus it is performed on."""
    n = _spaced(name)
    return any(
        " " + t.replace("-", " ") + " " in n for t in EQUIPMENT_TOKENS
    )


def normalize(name):
    n = _spaced(name)
    for token in EQUIPMENT_TOKENS:
        n = n.replace(" " + token.replace("-", " ") + " ", " ")
    for token in LOAD_TOKENS + PLAINNESS_TOKENS:
        n = n.replace(" " + token + " ", " ")
    n = re.sub(r"\s+", " ", n).strip()
    for pattern, replacement in NAME_SYNONYMS:
        n = re.sub(pattern, replacement, n)
    n = re.sub(r"\s+", " ", n).strip()
    # Trailing plural on the final word only.
    words = n.split()
    if words and words[-1].endswith("s") and not words[-1].endswith("ss"):
        words[-1] = words[-1][:-1]
    return " ".join(words)


def slugify(text):
    s = text.lower().replace("°", " degree ").replace("&", " and ")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def label_for(base):
    """Title-case display label, preserving common acronyms."""
    acronyms = {"rdl", "ghr", "ohp", "trx", "ghd", "jm", "l", "v", "t", "y"}
    words = []
    for w in base.split():
        words.append(w.upper() if w in acronyms else w.capitalize())
    return " ".join(words)


def main():
    write = "--write" in sys.argv
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)

    # Cluster on base name + movement pattern. The pattern keeps a "Neck Curl"
    # apart from a "Bicep Curl" even though both normalize to "curl".
    clusters = defaultdict(list)
    for row in catalog:
        base = normalize(row["name"])
        pattern = row.get("movementPattern") or "other"
        if not base:
            continue
        clusters[(base, pattern)].append(row)

    movements = []
    slug_by_exercise = {}
    for (base, pattern), members in sorted(clusters.items()):
        # A movement only earns a picker group if more than one exercise
        # shares it; singletons stay standalone rows.
        if len(members) < 2:
            continue
        slug = slugify(f"{base}-{pattern}")
        modalities = OrderedDict()
        for m in members:
            modalities[m["modality"]] = None
        # The canonical member is the plainest exercise in the cluster — it
        # receives the bare movement name as an alias, so searching "curl"
        # reaches the group rather than an arbitrary variant. Assisted and
        # weighted variants are ranked last: "Band-Assisted Dip" is a loading
        # choice, not the dip itself. Specialty bars likewise lose to plain
        # ones ("Barbell Row" over "Axle Bar Bent-Over Row").
        def canonical_rank(m):
            name = m["name"].lower()
            qualified = any(
                t in name for t in LOAD_TOKENS + ["band", "banded", "assisted"]
            )
            # A member whose name states its apparatus is a variant of the
            # movement; one whose name does not is the movement itself. Without
            # this, "Ring Push-Up" and "Standard Push-Up" tied on every other
            # component and the bare "push up" alias went to whichever sorted
            # first alphabetically — so searching "push up" returned the rings.
            equipped = names_equipment(m["name"])
            specialty = any(
                t in name
                for t in ("swiss", "axle", "safety", "cambered", "duffalo",
                          "trap", "landmine")
            )
            return (
                qualified,
                equipped,
                specialty,
                len(m["name"].split()),
                MODALITY_RANK.get(m["modality"], len(MODALITY_RANK)),
                m["name"],
            )

        override = CANONICAL_OVERRIDES.get(slug)
        canonical = next(
            (m for m in members if m["slug"] == override),
            None,
        ) or min(members, key=canonical_rank)
        movements.append(
            {
                "slug": slug,
                "label": label_for(base),
                "allowedEquipment": list(modalities.keys()),
                "canonicalExerciseSlug": canonical["slug"],
            }
        )
        for m in members:
            slug_by_exercise[m["slug"]] = slug

    grouped = sum(
        len(v) for k, v in clusters.items() if len(v) >= 2
    )
    print(f"catalog rows      : {len(catalog)}")
    print(f"movements (>=2)   : {len(movements)}")
    print(f"rows grouped      : {grouped}")
    print(f"picker rows after : {len(catalog) - grouped + len(movements)}")
    print()
    print("largest movements:")
    for mv in sorted(movements, key=lambda m: -len(m["allowedEquipment"]))[:15]:
        members = [
            r["name"] for r in catalog if slug_by_exercise.get(r["slug"]) == mv["slug"]
        ]
        print(
            f"  {mv['label']:<28} [{len(members)}] "
            f"{'/'.join(mv['allowedEquipment'])}"
        )

    if not write:
        print("\n(dry run — pass --write to apply)")
        return

    with open(MOVEMENTS, "w", encoding="utf-8", newline="\n") as f:
        json.dump(movements, f, ensure_ascii=False, indent=2)
        f.write("\n")

    for row in catalog:
        mv = slug_by_exercise.get(row["slug"])
        if mv:
            row["movementSlug"] = mv
        else:
            row.pop("movementSlug", None)
    with open(CATALOG, "w", encoding="utf-8", newline="\n") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"\nwrote {MOVEMENTS} and movementSlug on {len(slug_by_exercise)} rows")


if __name__ == "__main__":
    main()
