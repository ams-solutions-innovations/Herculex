# 12-01 Summary — Movement layer completion

**Executed:** 2026-08-18. All changes in `tool/derive_movements.py`; the asset
was regenerated, never hand-edited.

## What changed

**Grip/attachment qualifiers now strip before clustering.** A new
`VARIANT_QUALIFIERS` set lists parenthetical content that names a grip,
attachment or start position — `wide grip`, `rope`, `v-bar`, `below knee`,
`feet elevated`, `knees`, and so on. `strip_variant_qualifier()` drops the whole
parenthetical when its content matches, and `normalize()` runs it first.

Matching is on the **entire** parenthetical, not a substring, so qualifiers that
carry real meaning survive: `Hack Squat (Machine)` names equipment, `L-Sit
(floor)` names the apparatus, `Chin-Up (Supinated)` is the only grip a chin-up
has, and `Ab Crunch Bench (Angled)` is its own exercise. All four were verified
to remain standalone.

**Plainness tokens strip too.** `PLAINNESS_TOKENS = standard, conventional,
regular, classic`. Only two rows in the catalogue carry one, and both were being
excluded from their own family by it:

- `Standard Push-Up` clustered as `standard push up` while every ring and TRX
  push-up clustered as `push up` — so the group's bare "Push Up" alias went to a
  Ring Push-Up, and searching "push up" returned the rings first.
- `Conventional Deadlift` clustered alone while the trap-bar and axle-bar
  deadlifts formed a `deadlift` group without it.

`Sumo Deadlift` and `Romanian Deadlift` are unaffected — those qualifiers name a
real variant, not plainness.

**Canonical ranking penalises self-naming equipment.** `canonical_rank` gained an
`equipped` component: a member whose *name* states its apparatus is a variant;
one whose name does not is the movement itself. Without it, `Ring Push-Up` and
`Standard Push-Up` tied on every other component and the tie went alphabetically.
The token test shares `_spaced()` with `normalize()` so parentheses are flattened
the same way — the first version missed `Around the World (Plate)` because it did
not strip them.

## Result

| | before | after |
|---|---:|---:|
| rows grouped into a movement | 173 | 207 |
| picker rows | 297 | 265 |
| movements | 62 | 62 |

Canonical members were diffed across all 62 movements: exactly the two intended
changes (`push-up-horizontal-push` → Standard Push-Up, `deadlift-hinge` →
Conventional Deadlift). Every added row was checked against existing groups;
none joined one accidentally.

## Regression caught

`test/exercise_search_test.dart` — "the best match is first for the queries that
used to fail" — failed on query `push up` after the grip merge, returning Ring
Push-Up. That was the symptom that exposed the plainness-token and canonical-rank
problems above. It passes now, and the full suite is back to its pre-existing
26 failures (all unrelated, and present on a stashed baseline).
