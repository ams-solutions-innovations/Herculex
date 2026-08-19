#!/usr/bin/env python3
"""Derive the assisted-rep-tracking capability profile for every catalog row.

A sensor can only measure the body segment it sits on. We have two realistic
sites — the watch on the wrist, and the phone in a front trouser pocket riding
the thigh — so an exercise is countable exactly when the segment carrying a
sensor describes a cyclic motion with enough amplitude. Everything else in
this file follows from that one sentence.

The three failure modes it encodes:

  1. **Hands anchored.** On a pull-up the hand grips a fixed bar and the body
     travels past it, so the wrist is nearly stationary in the world frame.
     The thigh is not. These need the phone in a pocket and the watch cannot
     substitute.
  2. **Neither segment moves.** On a seated leg curl the femur is strapped
     down and only the shin travels; the hands rest on the handles. No sensor
     site sees the rep. These are permanently manual and must never surface a
     tracking affordance.
  3. **Amplitude below the floor.** A shrug moves the hand ~10 cm with almost
     no forearm rotation. Countable, but never confidently enough to carry an
     RPE suggestion.

Classification runs over the *structured* fields — `movementPattern`,
`modality`, `movementPatternRaw`, `loggingMetric`, `primaryMuscle` — and never
over the display name. An earlier name-regex draft put `behind-neck-pulldown`
and `behind-the-neck-ohp` in the unsupported bucket purely because of the
substring "neck", which is exactly the class of mistake this ordering rules
out. `OVERRIDES` below is the escape hatch, and every entry in it carries the
reason it is there.

Usage:
    python tool/derive_rep_profiles.py            # report only
    python tool/derive_rep_profiles.py --write    # write the profiles asset
"""

import json
import sys
from collections import Counter, OrderedDict

CATALOG = "assets/data/exercises.json"
PROFILES = "assets/data/rep_tracking_profiles.json"

# Only these logging metrics describe something a rep counter could count.
# Gated on the metric rather than a slug list so a catalog row that changes
# metric changes eligibility with it — see LoggingMetric.isRepBased.
REP_BASED_METRICS = {"weight_reps", "reps", "reps_time"}

# ── Detection families ──────────────────────────────────────────────────────
#
# One row per RepMovement value. `site` is where the sensor has to be; `deg`
# and `ms2` are the per-channel amplitude floors (the `tilt` channel is in
# degrees of gravity-vector rotation, `dyn` in m/s² of linear acceleration).
#
# Note how far apart the `ms2` floors sit from the single global 2.5 m/s² the
# pull-up-only detector used. That constant is correct for a pull-up and
# catastrophic for a 3-second curl, whose wrist acceleration peaks near
# A*w^2 = 0.25 * (2*pi/3)^2 ~= 1.1 m/s². The curl is only countable at all
# because the `tilt` channel does not vanish with cadence.
FAMILIES = OrderedDict([
    ("verticalPull",     dict(site="pocket", channels=["dyn"],        deg=None, ms2=2.5, minP=800,  maxP=8000,  tier="pocketOnly")),
    ("bodyweightPush",   dict(site="pocket", channels=["dyn"],        deg=None, ms2=2.0, minP=600,  maxP=6000,  tier="pocketOnly")),
    ("bodyweightPull",   dict(site="pocket", channels=["dyn"],        deg=None, ms2=2.0, minP=700,  maxP=7000,  tier="pocketOnly")),
    ("horizontalPush",   dict(site="wrist",  channels=["tilt","dyn"], deg=25.0, ms2=1.5, minP=900,  maxP=9000,  tier="supported")),
    ("verticalPush",     dict(site="wrist",  channels=["tilt","dyn"], deg=35.0, ms2=1.5, minP=900,  maxP=9000,  tier="supported")),
    ("horizontalPull",   dict(site="wrist",  channels=["tilt","dyn"], deg=30.0, ms2=1.5, minP=800,  maxP=8000,  tier="supported")),
    ("verticalPullDown", dict(site="wrist",  channels=["tilt","dyn"], deg=35.0, ms2=1.5, minP=800,  maxP=8000,  tier="supported")),
    ("elbowFlexion",     dict(site="wrist",  channels=["tilt","rot"], deg=45.0, ms2=1.0, minP=900,  maxP=9000,  tier="supported")),
    ("elbowExtension",   dict(site="wrist",  channels=["tilt","rot"], deg=40.0, ms2=1.0, minP=800,  maxP=8000,  tier="supported")),
    ("shoulderRaise",    dict(site="wrist",  channels=["tilt","rot"], deg=50.0, ms2=1.0, minP=900,  maxP=9000,  tier="supported")),
    ("squat",            dict(site="wrist",  channels=["tilt","dyn"], deg=15.0, ms2=2.0, minP=1000, maxP=10000, tier="supported")),
    ("hinge",            dict(site="wrist",  channels=["tilt","dyn"], deg=30.0, ms2=2.0, minP=1000, maxP=10000, tier="supported")),
    ("lunge",            dict(site="wrist",  channels=["tilt","dyn"], deg=20.0, ms2=2.0, minP=900,  maxP=9000,  tier="supported")),
    ("coreFlexion",      dict(site="wrist",  channels=["tilt"],       deg=30.0, ms2=1.5, minP=800,  maxP=8000,  tier="supported")),
    ("smallRom",         dict(site="wrist",  channels=["tilt","rot"], deg=10.0, ms2=0.8, minP=600,  maxP=6000,  tier="countOnly")),
])

# ── Rule inputs ─────────────────────────────────────────────────────────────

# Hands grip something fixed while the body travels past it. Structural, not
# nominal: bodyweight/other modality crossed with a push or pull pattern is
# precisely the pull-up / dip / push-up / inverted-row shape.
ANCHORED_MODALITIES = {"bodyweight", "other"}
ANCHORED_PATTERNS = {"vertical_pull", "vertical_push", "horizontal_pull", "horizontal_push"}

# Hanging core work: hands on the bar, hips and legs swing. The thigh-mounted
# phone sees a ~90 deg femur rotation; the wrist sees the bar.
HANGING_CORE = {
    "hanging-leg-raise", "toes-to-bar", "toes-to-rings", "windshield-wiper",
    "ring-hanging-knee-raise", "trx-hanging-leg-raise", "front-lever",
    "back-lever", "l-sit", "skin-the-cat",
}

# Neither the wrist nor the thigh carries the moving segment. Each entry is a
# permanent, physical exclusion — not a "we haven't got round to it".
UNSUPPORTED = {
    # Femur strapped down, only the shin travels.
    "seated-leg-curl": "femur fixed, only the shin travels",
    "lying-leg-curl": "femur fixed, only the shin travels",
    "standing-single-leg-curl": "femur fixed, only the shin travels",
    "leg-extension": "femur fixed, only the shin travels",
    # Ankle-only travel, ~8-10 cm, no rotation of any sensor-bearing segment.
    "seated-calf-raise": "ankle-only travel with the femur horizontal",
    "calf-press": "ankle-only travel inside a fixed sled",
    "tibialis-raise": "ankle-only travel, hands unloaded",
    # Rotation about a vertical axis leaves the gravity vector unchanged, so
    # the tilt channel is blind and only a thigh-mounted gyro could see it.
    "machine-abductor": "hip rotation about a vertical axis; gravity unchanged",
    "machine-adductor": "hip rotation about a vertical axis; gravity unchanged",
    "lying-cable-hip-adduction": "hip rotation about a vertical axis; gravity unchanged",
    # The watch sits proximal to the wrist joint, so it barely moves.
    "wrist-curl-barbell": "watch sits proximal to the moving joint",
    "dumbbell-wrist-curl": "watch sits proximal to the moving joint",
    "reverse-wrist-curl": "watch sits proximal to the moving joint",
    "dumbbell-reverse-wrist-curl": "watch sits proximal to the moving joint",
    "behind-the-back-wrist-curl": "watch sits proximal to the moving joint",
    "wrist-roller": "watch sits proximal to the moving joint",
    # No concentric cycle to close.
    "pallof-press": "anti-rotation hold, no closed cycle",
    "dead-bug": "anti-extension hold, no closed cycle",
    "scapular-pull-up": "scapular travel only, no closed cycle",
    "negative-pull-up": "eccentric only, no concentric cycle",
    "oblique-extension-machine": "trunk lateral flexion, neither site travels",
    "jefferson-curl": "segmental spinal flexion, no discrete cycle",
    "90-90-hip-switch": "mobility drill, no repeatable cycle shape",
    "band-shoulder-dislocate": "mobility drill, no repeatable cycle shape",
}

# Where the structured rules land on the wrong family. Every entry states why.
OVERRIDES = {
    # Seated, hands travel a full arc — the anchored-hands rule would
    # otherwise catch these on the bodyweight/vertical_pull combination.
    "lat-pulldown": ("verticalPullDown", "seated; hands travel, body does not"),
    "behind-neck-pulldown": ("verticalPullDown", "seated; hands travel, body does not"),
    "straight-arm-pulldown": ("shoulderRaise", "shoulder extension arc at the wrist"),
    "assisted-chin-up-dip-combo-machine": ("verticalPull", "machine-assisted, still hands-anchored"),
    # Torso rotates 60-90 deg with the hands on the chest or behind the head,
    # so the watch rides the torso and the tilt channel is strong.
    "nordic-hamstring-curl": ("coreFlexion", "hands ride the rotating torso"),
    "ghd-sit-up": ("coreFlexion", "hands ride the rotating torso"),
    "ghd-russian-twist": ("coreFlexion", "hands ride the rotating torso"),
    "45-degree-hyperextension": ("hinge", "hands ride the rotating torso"),
    "reverse-hyperextension": ("hinge", "hips travel, hands ride the fixed pad"),
    "glute-ham-raise-ghr": ("hinge", "hands ride the rotating torso"),
    # Hands anchored, but the structural rule misses them: the catalogue files
    # these under `isolation` (by target muscle) or under a loaded modality
    # (`smith`), neither of which trips the bodyweight+push/pull test. The
    # physics is unchanged — the hands hold something that does not move and
    # the body travels past it — so the wrist is blind and the pocket is not.
    "bench-dip": ("bodyweightPush", "hands anchored on the bench, hips travel"),
    "close-grip-push-up": ("bodyweightPush", "hands anchored on the floor, body travels"),
    "smith-machine-inverted-row": ("bodyweightPull", "hands anchored on a fixed bar, body travels"),
    # Small-ROM work: countable, never confidently enough for an RPE.
    "barbell-shrug": ("smallRom", "~10 cm hand travel, no forearm rotation"),
    "dumbbell-shrug": ("smallRom", "~10 cm hand travel, no forearm rotation"),
    "behind-back-barbell-shrug": ("smallRom", "~10 cm hand travel, no forearm rotation"),
    "overhead-shrug": ("smallRom", "~10 cm hand travel, no forearm rotation"),
    "standing-calf-raise": ("smallRom", "~12 cm whole-body travel"),
    "single-leg-standing-calf-raise": ("smallRom", "~12 cm whole-body travel"),
    "donkey-calf-raise": ("smallRom", "~12 cm whole-body travel"),
    "safety-bar-calf-raise": ("smallRom", "~12 cm whole-body travel"),
    "rack-pull-below-knee": ("smallRom", "partial ROM off the pins"),
    "rack-pull-above-knee": ("smallRom", "partial ROM off the pins"),
    "rack-pull-mid-thigh": ("smallRom", "partial ROM off the pins"),
    "swiss-bar-rack-pull": ("smallRom", "partial ROM off the pins"),
    "block-pull": ("smallRom", "partial ROM off the blocks"),
    "svend-press": ("smallRom", "short horizontal press, plate pinched"),
    "frog-pump": ("smallRom", "short hip travel, hands unloaded"),
    "glute-bridge": ("smallRom", "short hip travel, hands unloaded"),
    "bodyweight-hip-thrust": ("smallRom", "short hip travel, hands unloaded"),
    "dumbbell-glute-bridge": ("smallRom", "short hip travel"),
    "machine-glute-kickback": ("smallRom", "single-leg hip extension, hands on the frame"),
    "cable-glute-kickback": ("smallRom", "single-leg hip extension, hands on the frame"),
    # Arms swing freely and travel far, so the wrist reads these fine even
    # though the whole body also translates.
    "burpee": ("squat", "arm swing gives the wrist a full-amplitude cycle"),
    "trx-burpee": ("squat", "arm swing gives the wrist a full-amplitude cycle"),
    "burpee-box-jump-over": ("squat", "arm swing gives the wrist a full-amplitude cycle"),
    "box-jump": ("squat", "arm swing gives the wrist a full-amplitude cycle"),
    "box-jump-over": ("squat", "arm swing gives the wrist a full-amplitude cycle"),
    "broad-jump": ("squat", "arm swing gives the wrist a full-amplitude cycle"),
    "depth-jump": ("squat", "arm swing gives the wrist a full-amplitude cycle"),
    "jump-rope": ("smallRom", "wrist rotation only, very fast cadence"),
    "double-unders": ("smallRom", "wrist rotation only, very fast cadence"),
    # Counterbalanced with the arms out in front — the wrist describes a large
    # arc, so these do not need the phone.
    "pistol-squat": ("lunge", "arms counterbalance forward, wrist travels"),
    "shrimp-squat": ("lunge", "arms counterbalance forward, wrist travels"),
    "sissy-squat": ("squat", "torso rotates with the hands on the frame"),
    "trx-assisted-pistol-squat": ("lunge", "hands on straps that travel with the body"),
}

# Pattern -> family for everything the special cases above do not claim.
PATTERN_FAMILY = {
    "horizontal_push": "horizontalPush",
    "vertical_push": "verticalPush",
    "horizontal_pull": "horizontalPull",
    "vertical_pull": "verticalPullDown",
    "squat": "squat",
    "hinge": "hinge",
    "lunge": "lunge",
    "core": "coreFlexion",
    "carry": None,
    "other": "squat",
    "isolation": None,  # resolved by muscle below
}

# Isolation splits by which joint is doing the work, which `primaryMuscle`
# already encodes well enough.
ISOLATION_FAMILY = {
    "Biceps": "elbowFlexion",
    "Triceps": "elbowExtension",
    "Shoulders": "shoulderRaise",
    "Chest": "shoulderRaise",
    "Back": "shoulderRaise",
    "Forearms": "elbowFlexion",
    "Calves": "smallRom",
    "Quads": "squat",
    "Hamstrings": "hinge",
    "Glutes": "hinge",
    "Abs": "coreFlexion",
    "Adductors": "lunge",
    "Abductors": "smallRom",
}


def classify(row):
    """Return (family|None, tier, reason) for one catalog row."""
    slug = row["slug"]
    metric = row["loggingMetric"]
    pattern = row["movementPattern"]
    modality = row["modality"]
    muscle = row["primaryMuscle"]
    raw = (row.get("movementPatternRaw") or "").lower()

    if metric not in REP_BASED_METRICS:
        return None, "unsupported", f"not rep-based (loggingMetric={metric})"

    # Structured, so "behind-neck-pulldown" is untouched by it.
    if muscle == "Neck":
        return None, "unsupported", "the head is the moving segment"

    if slug in UNSUPPORTED:
        return None, "unsupported", UNSUPPORTED[slug]

    if "isometric" in raw or "hold" in raw:
        return None, "unsupported", f"isometric ({row['movementPatternRaw']})"

    if slug in OVERRIDES:
        family, reason = OVERRIDES[slug]
        return family, FAMILIES[family]["tier"], reason

    if slug in HANGING_CORE:
        return "verticalPull", "pocketOnly", "hands on the bar, hips and legs swing"

    # Hands anchored: the body travels past a fixed grip, so the wrist is
    # blind and the thigh is not.
    if modality in ANCHORED_MODALITIES and pattern in ANCHORED_PATTERNS:
        # Three distinct families, not one: an inverted row, a push-up and a
        # pull-up put the body through visibly different acceleration shapes,
        # and the family is the calibration key — sharing one would train a
        # single profile on three movements.
        family = {
            "vertical_pull": "verticalPull",
            "horizontal_pull": "bodyweightPull",
        }.get(pattern, "bodyweightPush")
        return family, "pocketOnly", "hands anchored; the body travels, the wrist does not"

    family = PATTERN_FAMILY.get(pattern)
    if family is None and pattern == "isolation":
        family = ISOLATION_FAMILY.get(muscle)
    if family is None:
        return None, "unsupported", f"no family for pattern={pattern} muscle={muscle}"

    return family, FAMILIES[family]["tier"], f"derived from pattern={pattern}"


def build(row):
    family, tier, reason = classify(row)
    profile = OrderedDict()
    profile["slug"] = row["slug"]
    profile["tier"] = tier
    if family is None:
        # An unsupported row carries no thresholds at all. Anything that reads
        # this asset must fail loudly rather than silently borrowing a
        # neighbour's calibration.
        profile["site"] = None
        profile["family"] = None
        profile["channels"] = []
    else:
        spec = FAMILIES[family]
        profile["site"] = spec["site"]
        profile["family"] = family
        profile["channels"] = list(spec["channels"])
        # A floor is emitted only for a channel this family actually detects
        # on. A curl carries a `minCycleAmplitudeMs2` nowhere near high enough
        # to reject walking (~1.2 m/s²) — harmless while the curl never uses
        # the dynamic channel, and a loaded gun the moment somebody reads it
        # because it happened to be there.
        angular = bool({"tilt", "rot"} & set(spec["channels"]))
        profile["minCycleAmplitudeDeg"] = spec["deg"] if angular else None
        profile["minCycleAmplitudeMs2"] = spec["ms2"] if "dyn" in spec["channels"] else None
        profile["minPeriodMs"] = spec["minP"]
        profile["maxPeriodMs"] = spec["maxP"]
    profile["reason"] = reason
    return profile


def main():
    write = "--write" in sys.argv

    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)

    profiles = [build(row) for row in catalog]

    tiers = Counter(p["tier"] for p in profiles)
    families = Counter(p["family"] for p in profiles if p["family"])
    sites = Counter(p["site"] for p in profiles if p["site"])

    print(f"{len(profiles)} catalog rows\n")
    print("tier:")
    for tier, n in tiers.most_common():
        print(f"  {tier:<12} {n:>4}")
    print("\nsensor site:")
    for site, n in sites.most_common():
        print(f"  {site:<12} {n:>4}")
    print("\nfamily:")
    for family, n in families.most_common():
        spec = FAMILIES[family]
        print(f"  {family:<18} {n:>4}  {spec['site']:<7} {'+'.join(spec['channels'])}")

    print("\nunsupported, by reason:")
    reasons = Counter(p["reason"] for p in profiles if p["tier"] == "unsupported")
    for reason, n in reasons.most_common():
        print(f"  {n:>3}  {reason}")

    if not write:
        print("\n(dry run — pass --write to apply)")
        return

    with open(PROFILES, "w", encoding="utf-8", newline="\n") as f:
        json.dump(profiles, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"\nwrote {PROFILES}")


if __name__ == "__main__":
    main()
