# Phase 07: Workout Linked Sets - Research

**Date:** 2026-07-30

## Training Semantics

- Straight sets prioritize quality and recovery between repeated efforts of the same exercise.
- Supersets pair two exercises back-to-back with little or no transition rest, typically saving time and increasing training density.
- Agonist-antagonist supersets are usually the most recovery-friendly version because the second movement allows partial local recovery for the first muscle group.
- Same-muscle compound supersets, pre-exhaustion, drop sets, rest-pause, and giant sets create more local fatigue and should feel visually/intentionally more demanding.
- Giant sets are best represented as three or more exercises in sequence, followed by one rest period after the round.

## Recovery, CNS, And Workout Time

- Large compound lifts and heavy strength work need longer recovery because local muscle fatigue, stabilizer fatigue, mental readiness, and cardiovascular recovery all affect next-set quality.
- Shortening rest increases density and saves time, but can reduce performance if the user is not ready for the next high-skill or high-load set.
- Supersets are a useful time-saving structure, but should not be hidden as a single set flag; the user needs to see the sequence and where rest happens.
- UI should make density explicit: visual linking, ordered round positions, and rest after the final linked exercise.

## UI/UX Implications By Type

- Standard set: plain numbered row, normal rest after completion.
- Warmup: distinct row badge, no working-volume emphasis.
- Drop set / mechanical drop: same exercise row with compact metadata, because the work stays within one exercise.
- Rest-pause / myo reps: nested mini-set chips under one row, because the work is one activation set plus micro-rest repeats.
- Pause reps / negatives / partials / forced reps: per-set badges are appropriate because the technique modifies rep execution.
- Pyramid / down sets / 20x60: per-set or sequence metadata, but still within one exercise.
- Superset: exercise-level link of two exercises; show rail and advance input to next linked exercise.
- Giant set: exercise-level link of three or more exercises; show the same rail with `GIANT SET`.
- AMRAP / EMOM / For Time: session/block style; per-row badges are acceptable only until a richer timed block UI exists.

## Sources

- ACSM: https://acsm.org/resistance-training-guidelines-update-2026/
- NSCA PTQ rest intervals: https://www.nsca.com/contentassets/fb8a7be6eb174934bb8844703c4de4cc/ptq-10.1.3-how-to-manipulate-rest-intervals-to-maixmize-strength-training-effectiveness.pdf
- Iversen et al., Sports Medicine / PubMed: https://pubmed.ncbi.nlm.nih.gov/34125411/
- Superset vs traditional review / PubMed: https://pubmed.ncbi.nlm.nih.gov/39903375/
