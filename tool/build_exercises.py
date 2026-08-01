#!/usr/bin/env python
"""
Build-time enrichment: converts the user's `Exercise selection.xlsx`
(Body Part | Exercise | Alternate Name | Movement Pattern | Similar Exercises)
into a fully populated `assets/data/exercises.json` for the Flutter importer.

The xlsx only carries 5 columns, so muscle involvement, CNS score, equipment,
modality, logging metric and recovery impact are DERIVED here via sports-science
heuristics keyed off the name + body part + movement pattern. These are first-pass
estimates flagged with `"derived": true` so the app can mark un-reviewed rows.

Run:  python tool/build_exercises.py
Input : C:\\Users\\marti\\OneDrive\\Desktop\\Exercise selection.xlsx
Output: assets/data/exercises.json
"""
import json
import os
import re
import sys

import openpyxl

SRC = r"C:\Users\marti\OneDrive\Desktop\Exercise selection.xlsx"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "data", "exercises.json")


def low(s):
    return (s or "").lower()


def has(name, *kw):
    n = low(name)
    return any(k in n for k in kw)


# ── Equipment & modality ────────────────────────────────────────────────────
def derive_equipment_modality(name):
    """Return (equipment, modality). modality enum:
    barbell|dumbbell|machine_plate|machine_selectorized|cable|smith|kettlebell|
    band|bodyweight|other."""
    n = low(name)
    # Bodyweight-origin movements (assistance handled below)
    bw_kw = ["push-up", "pull-up", "chin-up", "muscle-up", "dip", "plank", "l-sit",
             "hold", "lever", "planche", "flag", "pistol", "shrimp", "sissy",
             "nordic", "hollow", "arch", "bridge", "sit-up", "leg raise",
             "toes to bar", "toes to rings", "dragon flag", "v-up", "dead bug",
             "burpee", "mountain climber", "jump", "broad jump", "depth jump",
             "hyperextension", "glute ham", "ghr", "inverted row", "windshield",
             "ab wheel", "rollout", "frog pump", "glute bridge"]
    if "band-assisted" in n or "assisted" in n and ("pull-up" in n or "chin-up" in n or "dip" in n):
        return ("Band/Assist", "bodyweight")
    if "ring" in n:
        return ("Rings", "bodyweight")
    if "trx" in n or "suspension" in n:
        return ("TRX", "bodyweight")
    if "smith" in n:
        return ("Smith Machine", "smith")
    if has(n, "cable", "pushdown", "pulldown", "pull-through", "crossover",
            "woodchopper", "pallof", "pull-through", "rope"):
        return ("Cable", "cable")
    if "band" in n or "banded" in n:
        return ("Band", "band")
    if "kettlebell" in n:
        return ("Kettlebell", "kettlebell")
    if "dumbbell" in n or "(db)" in n or " db" in n or "kroc" in n:
        return ("Dumbbell", "dumbbell")
    if any(k in n for k in ["ez bar", "ez-bar"]):
        return ("EZ Bar", "barbell")
    if "swiss bar" in n:
        return ("Swiss Bar", "barbell")
    if "axle bar" in n:
        return ("Axle Bar", "barbell")
    if "safety bar" in n:
        return ("Safety Bar", "barbell")
    if "cambered bar" in n:
        return ("Cambered Bar", "barbell")
    if "duffalo bar" in n:
        return ("Duffalo Bar", "barbell")
    if "trap bar" in n or "hex bar" in n:
        return ("Trap Bar", "barbell")
    if "landmine" in n or "meadows" in n:
        return ("Landmine", "barbell")
    # Machines (plate-loaded vs selectorized)
    machine_kw = ["machine", "pec deck", "hack squat", "pendulum", "v-squat",
                  "leg press", "leg extension", "leg curl", "iso-lateral",
                  "plate-loaded", "hammer", "rotary torso", "ab crunch machine",
                  "pullover machine", "t-bar row machine", "belt squat",
                  "reverse pec deck", "abductor", "adductor", "glute kickback",
                  "4-way neck", "neck extension", "neck curl", "neck side flexion",
                  "neck rotation", "reverse hyperextension", "45-degree leg press",
                  "oblique extension (machine)", "ab crunch bench", "total core trainer",
                  "roman chair", "semi-recumbent"]
    if any(k in n for k in machine_kw):
        if any(k in n for k in ["plate-loaded", "iso-lateral", "hammer", "hack squat",
                                 "pendulum", "v-squat", "45-degree leg press",
                                 "leg press", "belt squat", "neck (wrestling)"]):
            return ("Machine", "machine_plate")
        return ("Machine", "machine_selectorized")
    if any(k in n for k in bw_kw):
        return ("Bodyweight", "bodyweight")
    if "plate" in n:  # Plate Front Raise, Around the World (Plate)
        return ("Plate", "other")
    if "sled" in n or "yoke" in n or "death march" in n or "prowler" in n:
        return ("Sled/Yoke", "other")
    if "neck harness" in n:
        return ("Neck Harness", "other")
    if "self-resisted" in n or "wrestling" in n or "neck bridge" in n or "neck shrug" in n:
        return ("Bodyweight", "bodyweight")
    if "barbell" in n or "bar " in n or "deadlift" in n or "squat" in n or \
       "bench" in n or "press" in n or "row" in n or "good morning" in n or \
       "rack pull" in n or "block pull" in n or "shrug" in n or "curl" in n:
        return ("Barbell", "barbell")
    return ("Other", "other")


# ── Logging metric & weighted-bodyweight ────────────────────────────────────
ISO_HOLD = ["hold", "plank", "l-sit", "lever", "planche", "flag", "support hold",
            "bridge", "wall sit", "isometric", "copenhagen"]
CARRY = ["carry", "walk", "farmers", "yoke", "sled", "death march", "waiter"]


def derive_logging_metric(name, modality):
    n = low(name)
    if any(k in n for k in CARRY):
        return "weight_time"
    if any(k in n for k in ISO_HOLD):
        return "time"
    if modality == "bodyweight":
        return "reps"
    return "weight_reps"


def derive_weighted_bw(name, modality):
    n = low(name)
    if modality == "bodyweight":
        return True
    if any(k in n for k in ["pull-up", "chin-up", "dip", "push-up", "muscle-up",
                            "pistol", "nordic", "ghr", "glute ham", "inverted row",
                            "hyperextension", "sit-up", "leg raise", "l-sit",
                            "plank", "russian twist", "side bend"]):
        return True
    return False


# ── Muscles (primary / secondary / stabilizer) ──────────────────────────────
# Granular muscle vocabulary; coarse group map drives the legacy primaryMuscle col.
def derive_muscles(name, body_part, pattern):
    n = low(name)
    p = low(pattern)
    prim, sec, stab = [], [], []

    def setm(pr, se=None, st=None):
        return (list(pr), list(se or []), list(st or []))

    # ---- Lower Body ----
    if body_part == "Lower Body":
        if any(k in n for k in ["hip thrust", "glute bridge", "frog pump", "kickback",
                                "pull-through", "glute"]):
            prim, sec, stab = setm(["Glutes"], ["Hamstrings"], ["Erectors"])
        elif "calf raise" in n or "donkey" in n or "calf" in n:
            prim, sec, stab = setm(["Calves"])
        elif "tibialis" in n:
            prim, sec, stab = setm(["Tibialis"])
        elif "abductor" in n or "hip abduction" in n:
            prim, sec, stab = setm(["Abductors"], ["Glutes"])
        elif "adductor" in n or "hip adduction" in n or "copenhagen" in n or "cossack" in n:
            prim, sec, stab = setm(["Adductors"], ["Glutes", "Quads"])
        elif any(k in n for k in ["leg curl", "nordic", "glute ham", "ghr"]):
            prim, sec, stab = setm(["Hamstrings"], ["Glutes"], ["Calves"])
        elif "leg extension" in n or "sissy" in n:
            prim, sec, stab = setm(["Quads"])
        elif any(k in n for k in ["rdl", "romanian", "good morning", "deadlift",
                                  "rack pull", "block pull", "hyperextension",
                                  "death march", "swing", "jefferson", "suitcase deadlift"]):
            if "hip hinge" in p or any(k in n for k in ["rdl", "romanian", "good morning",
                                                        "hyperextension"]):
                prim, sec, stab = setm(["Hamstrings", "Glutes"],
                                       ["Erectors"], ["Forearms", "Abs"])
            else:  # full deadlifts
                prim, sec, stab = setm(["Glutes", "Hamstrings"],
                                       ["Erectors", "Quads", "Lats", "Traps"],
                                       ["Forearms", "Abs"])
        elif any(k in n for k in ["lunge", "split squat", "step-up", "pistol",
                                  "shrimp", "curtsy", "patrick"]):
            prim, sec, stab = setm(["Quads", "Glutes"], ["Hamstrings"],
                                   ["Adductors", "Abs"])
        elif "squat" in n or "leg press" in n or "hack" in n or "pendulum" in n or \
                "v-squat" in n or "belt squat" in n or "box jump" in n or \
                "depth jump" in n or "jump squat" in n:
            prim, sec, stab = setm(["Quads"], ["Glutes", "Adductors"],
                                   ["Erectors", "Abs"])
        elif "sled" in n:
            prim, sec, stab = setm(["Quads", "Glutes"], ["Calves"], ["Abs"])
        else:
            prim, sec, stab = setm(["Quads", "Glutes"], ["Hamstrings"], ["Abs"])

    # ---- Chest ----
    elif body_part == "Chest":
        if any(k in n for k in ["fly", "flye", "crossover", "pec deck", "svend"]):
            prim, sec, stab = setm(["Chest"], ["Front Delts"], ["Biceps"])
        elif "dip" in n:
            prim, sec, stab = setm(["Chest", "Triceps"], ["Front Delts"], ["Core"])
        else:
            prim, sec, stab = setm(["Chest"], ["Triceps", "Front Delts"],
                                   ["Serratus", "Core"])

    # ---- Back ----
    elif body_part == "Back":
        if "bicep curl" in n or "biceps curl" in n:
            prim, sec, stab = setm(["Biceps"], ["Brachialis"], ["Forearms"])
        elif "triceps extension" in n or "tricep extension" in n or "french press" in n:
            prim, sec, stab = setm(["Triceps"], [], ["Forearms", "Core"])
        elif "pullover" in n or "straight-arm" in n or "straight arm" in n:
            prim, sec, stab = setm(["Lats"], ["Chest", "Triceps"], ["Core"])
        elif "shrug" in n:
            prim, sec, stab = setm(["Traps"], [], ["Forearms"])
        elif "scapular" in n:
            prim, sec, stab = setm(["Traps", "Lats"])
        elif any(k in n for k in ["pull-up", "pulldown", "chin-up", "front lever",
                                  "back lever", "muscle-up", "typewriter", "commando",
                                  "behind the neck pull", "towel pull"]):
            prim, sec, stab = setm(["Lats"], ["Biceps", "Rhomboids", "Rear Delts"],
                                   ["Forearms", "Core"])
        else:  # rows
            prim, sec, stab = setm(["Lats", "Rhomboids", "Traps"],
                                   ["Biceps", "Rear Delts"], ["Erectors", "Forearms"])

    # ---- Shoulders ----
    elif body_part == "Shoulders":
        if "lateral raise" in n or "lu raise" in n:
            prim, sec, stab = setm(["Side Delts"])
        elif "front raise" in n or "around the world" in n:
            prim, sec, stab = setm(["Front Delts"], ["Side Delts"])
        elif any(k in n for k in ["rear delt", "reverse pec deck", "face pull",
                                  "scarecrow", "ytwli"]):
            prim, sec, stab = setm(["Rear Delts"], ["Rhomboids", "Traps"])
        elif "upright row" in n:
            prim, sec, stab = setm(["Side Delts", "Traps"], ["Biceps"])
        elif "shrug" in n:
            prim, sec, stab = setm(["Traps"], [], ["Forearms"])
        elif "carry" in n or "waiter" in n:
            prim, sec, stab = setm(["Side Delts"], ["Traps"], ["Core", "Forearms"])
        elif "cuban" in n:
            prim, sec, stab = setm(["Rear Delts", "Side Delts"], ["Traps"])
        else:  # presses / handstand push-up
            prim, sec, stab = setm(["Front Delts"],
                                   ["Side Delts", "Triceps", "Traps"], ["Core"])

    # ---- Arms ----
    elif body_part == "Arms":
        if "wrist" in n or "wrist roller" in n:
            prim, sec, stab = setm(["Forearms"])
        elif "curl" in n or "bayesian" in n or "pelican" in n:
            if any(k in n for k in ["reverse", "hammer", "zottman", "drag"]):
                prim, sec, stab = setm(["Biceps", "Forearms"], ["Brachialis"])
            else:
                prim, sec, stab = setm(["Biceps"], ["Brachialis", "Forearms"])
        else:  # triceps
            prim, sec, stab = setm(["Triceps"], [], ["Forearms"])

    # ---- Core & Abs ----
    elif body_part == "Core & Abs":
        if any(k in n for k in ["woodchopper", "russian twist", "side bend",
                                "oblique", "rotary torso", "windshield", "rotation"]):
            prim, sec, stab = setm(["Obliques"], ["Abs"], ["Hip Flexors"])
        elif any(k in n for k in ["plank", "pallof", "dead bug", "hollow",
                                  "ab wheel", "rollout", "dragon flag", "anti"]):
            prim, sec, stab = setm(["Abs"], ["Obliques"], ["Erectors", "Hip Flexors"])
        elif any(k in n for k in ["leg raise", "toes to", "reverse crunch", "v-up",
                                  "knee raise"]):
            prim, sec, stab = setm(["Abs", "Hip Flexors"], ["Obliques"], ["Forearms"])
        else:
            prim, sec, stab = setm(["Abs"], ["Obliques"])

    # ---- Neck ----
    elif body_part == "Neck":
        prim, sec, stab = setm(["Neck"], ["Traps"] if "shrug" in n else [])

    # ---- Full Body (carries) ----
    elif body_part == "Full Body":
        prim, sec, stab = setm(["Forearms", "Traps"], ["Core"], ["Glutes", "Quads"])

    # ---- Calisthenics ----
    else:
        if "planche" in n or "pseudo planche" in n:
            prim, sec, stab = setm(["Front Delts", "Chest"], ["Triceps"], ["Abs"])
        elif "front lever" in n or "muscle-up" in n or "hefesto" in n:
            prim, sec, stab = setm(["Lats"], ["Biceps", "Chest", "Triceps"], ["Abs"])
        elif "back lever" in n:
            prim, sec, stab = setm(["Lats", "Chest"], ["Biceps"], ["Erectors"])
        elif "flag" in n:
            prim, sec, stab = setm(["Obliques", "Lats"], ["Side Delts"], ["Abs"])
        elif "pike" in n or "dolphin" in n:
            prim, sec, stab = setm(["Front Delts"], ["Triceps"], ["Core"])
        elif "hold" in n or "hollow" in n:
            prim, sec, stab = setm(["Abs"], ["Hip Flexors"], ["Erectors"])
        elif "arch" in n:
            prim, sec, stab = setm(["Erectors"], ["Glutes"], ["Hamstrings"])
        elif "jump" in n:
            prim, sec, stab = setm(["Quads", "Glutes"], ["Calves"], ["Abs"])
        else:
            prim, sec, stab = setm(["Abs"], ["Core"])

    return prim, sec, stab


COARSE = {
    "Chest": "Chest", "Lats": "Back", "Rhomboids": "Back", "Traps": "Back",
    "Erectors": "Back", "Front Delts": "Shoulders", "Side Delts": "Shoulders",
    "Rear Delts": "Shoulders", "Biceps": "Biceps", "Brachialis": "Biceps",
    "Triceps": "Triceps", "Forearms": "Forearms", "Quads": "Quads",
    "Hamstrings": "Hamstrings", "Glutes": "Glutes", "Calves": "Calves",
    "Tibialis": "Calves", "Adductors": "Adductors", "Abductors": "Abductors",
    "Abs": "Abs", "Obliques": "Abs", "Hip Flexors": "Abs", "Core": "Abs",
    "Serratus": "Chest", "Neck": "Neck",
}


# ── CNS score (1-10) & recovery impact (1-5) ────────────────────────────────
def derive_cns_recovery(name, body_part, pattern, modality, prim):
    n = low(name)
    p = low(pattern)
    cns = 3
    # Big axial barbell compounds
    if any(k in n for k in ["deadlift", "rack pull", "block pull", "jefferson",
                            "snatch grip", "steinborn"]):
        cns = 9
    elif any(k in n for k in ["back squat", "front squat", "zercher", "safety bar squat",
                              "duffalo bar squat", "box squat", "hack squat"]):
        cns = 8
    elif "squat" in n and modality in ("barbell", "smith"):
        cns = 7
    elif any(k in n for k in ["bench press", "overhead press", "ohp", "push press",
                              "barbell row", "pendlay", "yates", "good morning",
                              "hip thrust", "bradford", "clean", "axle bar"]):
        cns = 6
    elif modality in ("machine_plate", "machine_selectorized", "smith") and \
            ("Quads" in prim or "Lats" in prim or "Chest" in prim):
        cns = 5
    elif body_part in ("Core & Abs", "Neck"):
        cns = 2
    elif any(k in n for k in ["raise", "fly", "flye", "curl", "pushdown", "extension",
                              "kickback", "calf", "crossover", "pec deck", "shrug",
                              "woodchopper", "side bend"]):
        cns = 2
    else:
        cns = 4
    # Skill / advanced calisthenics carry high neural demand
    if body_part == "Advanced Calisthenics" or any(k in n for k in
            ["planche", "front lever", "back lever", "human flag", "muscle-up",
             "hefesto"]):
        cns = max(cns, 7)
    # Explosive / plyometric / kipping modifiers
    if any(k in p for k in ["explosive"]) or any(k in n for k in
            ["jump", "depth", "broad", "clap", "kipping", "power", "snatch", "clean"]):
        cns = min(10, cns + 2)
    cns = max(1, min(10, cns))
    rec = max(1, min(5, round(cns / 2)))
    if any(k in n for k in ["deadlift", "squat", "rack pull"]):
        rec = min(5, rec + 1)
    return cns, rec


def derive_rest(cns, body_part, metric):
    if cns >= 8:
        return 240
    if cns >= 6:
        return 180
    if metric == "time" or body_part in ("Core & Abs", "Neck"):
        return 60
    if cns >= 4:
        return 120
    return 75


# ── Category & coarse movement pattern ──────────────────────────────────────
def derive_category(name, body_part, modality):
    n = low(name)
    if body_part in ("Advanced Calisthenics", "Calisthenics (Beginner/Int)") or \
            any(k in n for k in ["ring", "trx", "planche", "lever", "flag",
                                 "muscle-up", "pistol", "l-sit", "handstand"]):
        return "calisthenics"
    if any(k in n for k in ["conventional deadlift", "sumo deadlift", "barbell back squat",
                            "barbell bench press", "overhead press"]):
        return "powerlifting"
    if any(k in n for k in ["raise", "fly", "flye", "curl", "pushdown", "extension",
                            "kickback", "calf", "crossover", "pec deck", "shrug"]):
        return "hypertrophy"
    return "strength"


def derive_pattern(pattern, body_part):
    p = low(pattern)
    if "hip hinge" in p:
        return "hinge"
    if "carry" in p or "loaded carry" in p:
        return "carry"
    if "squat" in p or ("knee dominant" in p and "unilateral" not in p and "lateral" not in p):
        return "squat"
    if "knee dominant" in p and ("unilateral" in p or "lateral" in p):
        return "lunge"
    if "horizontal push" in p or "incline push" in p or "decline push" in p:
        return "horizontal_push"
    if "vertical push" in p or "downward push" in p or "isometric (vertical push)" in p:
        return "vertical_push"
    if "horizontal pull" in p:
        return "horizontal_pull"
    if "vertical pull" in p:
        return "vertical_pull"
    if any(k in p for k in ["elbow", "wrist", "abduction", "adduction", "isolation",
                            "flexion (isolation)", "scapular"]):
        return "isolation"
    if any(k in p for k in ["spinal flexion", "rotation", "anti-extension", "anti-rotation",
                            "hip flexion", "lateral flexion", "lateral stability",
                            "neck", "core", "circumduction"]):
        return "core"
    return "other"


def split_list(s):
    if not s:
        return []
    return [x.strip() for x in re.split(r"[;/]", str(s)) if x.strip()]


def main():
    wb = openpyxl.load_workbook(SRC, data_only=True)
    ws = wb["List1"]
    rows = [r for r in ws.iter_rows(min_col=1, max_col=5, values_only=True) if r[1]][1:]

    out = []
    seen = set()
    for body_part, name, alt, pattern, similar in rows:
        name = str(name).strip()
        if name in seen:
            continue
        seen.add(name)
        equipment, modality = derive_equipment_modality(name)
        metric = derive_logging_metric(name, modality)
        wbw = derive_weighted_bw(name, modality)
        prim, sec, stab = derive_muscles(name, body_part, pattern)
        cns, rec = derive_cns_recovery(name, body_part, pattern, modality, prim)
        rest = derive_rest(cns, body_part, metric)
        coarse_primary = COARSE.get(prim[0], prim[0]) if prim else body_part
        aliases = split_list(alt)
        out.append({
            "name": name,
            "aka": aliases,
            "bodyPart": body_part,
            "category": derive_category(name, body_part, modality),
            "movementPattern": derive_pattern(pattern, body_part),
            "movementPatternRaw": str(pattern).strip() if pattern else None,
            "modality": modality,
            "equipment": equipment,
            "primaryMuscle": coarse_primary,
            "primaryMuscles": prim,
            "secondaryMuscles": sec,
            "stabilizers": stab,
            "cnsScore": cns,
            "recoveryImpact": rec,
            "loggingMetric": metric,
            "supportsWeightedBodyweight": wbw,
            "defaultRestSeconds": rest,
            "similar": split_list(similar),
            "derived": True,
        })

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"Wrote {len(out)} exercises -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
