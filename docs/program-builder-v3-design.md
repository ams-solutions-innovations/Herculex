# Program Builder v3 — Slots, Pools & Smart Exercise Rotation

Status: **design agreed · engine core implemented · UI not started**
Date: 2026-08-23
Supersedes: the exercise-by-exercise content step in `block_builder_view.dart` (step 3)
Related: V2 §12 (periodization + accommodation), HANDOFF Phase 5 (done), HANDOFF Phase 9 (smart substitution — merges into this)

---

## 0. Decisions taken

| # | Decision | Chosen |
| --- | --- | --- |
| D1 | When rotation resolves to a concrete exercise | **Planned + drift** — materialize the whole plan, offer a reasoned one-tap swap at session start, never change silently |
| D2 | Where favourite exercises live | **Global favourites + per-program override** — `ExercisePreferences` is app-wide, a program snapshots it into a pool it may edit |
| D3 | Selection intelligence | **Full scoring engine** — every pick carries a `why` |
| D4 | MEV/MRV band source | **Population prior, shrinking toward the user** — priors ship for all 19 groups, personal tolerance takes over as evidence accrues (§11) |
| D5 | Re-roll granularity | **Per-slot Swap and whole-program Shuffle. No per-week re-roll** (§9.3) |
| D6 | Drift quiet mode | **Learned, not a settings toggle** — mute per trigger after three dismissals, plus an explicit per-program "Locked plan" (§10.2) |

---

## 1. The shift

Today a program is a list of **exercises**. It becomes a list of **slots**.

```
Program = Blueprint  (skeleton of slots per day)
        + Pools      (candidate exercises per slot, seeded from favourites)
        + Model      (how each week is prescribed)
        + Overlays   (technique: 2 sets to failure, myo reps, drop …)
```

The user edits the *pool* once. The engine fills 4 weeks × 5 days × 6 exercises.

Everything the engine decides must be explainable in one sentence shown on tap.
If a pick cannot produce a `why`, the rule that produced it is wrong.

---

## 2. Movement Slot

The atomic unit. Replaces the bare `ProgramDayExercises.exerciseId` row.

| Field | Values | Notes |
| --- | --- | --- |
| `role` | `main` · `supplemental` · `accessory` · `isolation` · `conditioning` | drives prescription archetype *and* rotation speed |
| `muscleGroup` | one of the 19 (`muscle_recovery_v3.dart`) | what the slot is *for* |
| `pattern` | `squat` · `hinge` · `horizontal_push` · … | already in `ExerciseCatalog.movementPattern` |
| `poolId` | → `ExerciseRotations` | candidate set |
| `rotationPolicy` | derived from `(model, role, phase)`, overridable | §5 |
| `prescription` | derived from `(model, role, week)`, overridable | §6 |
| `overlay` | technique template | §7 |

A slot with a one-member pool is just a fixed exercise. Same code path, no
special case.

**Implemented:** `lib/features/programs/domain/slot_role.dart`

---

## 3. Global favourites layer

New table, app-wide, **not** per program.

```dart
class ExercisePreferences extends Table with SyncColumns, SyncTombstone {
  IntColumn  get id            => integer().autoIncrement()();
  IntColumn  get exerciseId    => integer().references(ExerciseCatalog, #id,
                                    onDelete: KeyAction.cascade)();
  TextColumn get muscleGroup   => text()();          // one of the 19
  IntColumn  get affinity      => integer().withDefault(const Constant(0))();
                                  // -1 never | 0 ok | 1 like | 2 core lift
  IntColumn  get eligibleRoles => integer().withDefault(const Constant(0))();
  IntColumn  get variantId     => integer().nullable()();
  TextColumn get note          => text().nullable()();
}
```

### Why `eligibleRoles` is not optional

Affinity alone is not enough. A Leg Extension can be a *liked* exercise and must
still never be prescribed as "work up to a heavy single". Without this gate the
generator eventually produces nonsense.

The default is **derived, not asked** — see `SlotRoleEligibility.derive`:

| Signal | Implies |
| --- | --- |
| compound + barbell/dumbbell/smith/plate-loaded + `cnsScore ≥ 5` | `main` eligible |
| compound | `supplemental` eligible |
| anything liftable | `accessory` eligible |
| isolation | `isolation` eligible, `main` **not** |
| `loggingMetric ∈ {time, distance}` or `category = cardio` | `conditioning` eligible |

The user only ever sees the override, never the derivation.

### Three write points

1. **Catalog** — a ⭐ on any exercise row
2. **History** — after N logged sessions of an exercise, offer "add to favourites" once
3. **Builder** — step 3 (§9.1)

---

## 4. Smart Exercise Rotation — the scoring engine

Replaces `ExerciseRotation.activeMemberIndex`
(`(weekIndex ~/ every) % memberCount`), which is a blind round-robin.

For slot `S`, week `w`, candidate pool `P`: pick `argmax score(c)` over
`c ∈ P` after hard filters.

### Hard filters, and the relaxation ladder

| Filter | Relaxed at |
| --- | --- |
| `affinity == -1` (blacklist) | **never** |
| role not in `eligibleRoles` | never |
| realization phase, heavy slot, not the anchor lift | never |
| performed within `minGapWeeks` | first |
| equipment unavailable at the program's gym | second (and the session is flagged) |
| everything failed | fall back to the pool anchor |

The slot is never left empty and the scorer never returns null. The result
reports which rung of the ladder it landed on, so the UI can say "no safety bar
here — using Front Squat" instead of silently substituting.

### Score terms

| Term | Weight | Direction | Source |
| --- | --- | --- | --- |
| **stagnation** — e1RM on this variant flat for N exposures | 3.0 | ↓ | per-variant 1RM engine |
| **staleness** — weeks since last performed (never = max) | 1.5 | ↑ | `WorkoutSets` history |
| **recovery** — target group still down × the exercise's `recoveryImpact` | 1.2 | ↓ | 19-group heatmap |
| **CNS budget** — `cnsScore` against what the week has left | 1.2 | ↓ | `ExerciseCatalog.cnsScore` |
| **affinity** | 1.0 | ↑ | `ExercisePreferences` |
| **variety** — distance from the last two picks | 1.0 | ↑ | catalog |
| **tier fit** — suits the block phase | 1.0 | ↑ | catalog + phase |
| **novelty** — heavy slot, almost no logged history | 0.8 | ↓ | history |

Stagnation is a penalty on the *stalled candidate*, not a trigger. That is the
whole accommodation law expressed as one term: an exercise that has stopped
going up simply stops winning, and the fresh variant takes the slot. No special
case, no separate rule engine.

Stagnation is weighted at full strength only for `main` and `supplemental`
slots (×0.35 elsewhere) — a lateral raise that has not added weight in a month
is not a problem to solve.

### Determinism

`seed = hash(programId, slotId)`, applied as a jitter three orders of magnitude
below any real term. Consequences:

- the preview is byte-identical to what the calendar will show
- **Shuffle** is `seed++`
- the jitter breaks ties and can never overturn a real difference
- rotation is unit-testable without a database

### Note on `movementSlug`

`movementSlug` groups equipment variants of one movement (every curl shares
`curl-isolation`).

- **accessory / isolation**: rotating inside a slug is weak variety → distance
  is cut to a quarter. Swapping the handle is not a new exercise.
- **main / supplemental**: a modality change inside a slug (barbell bench →
  dumbbell floor press) *is* legitimate accommodation → not penalized. Only a
  like-for-like repeat (same slug *and* same modality) scores zero.

**Implemented:** `lib/features/programs/domain/exercise_scorer.dart`

### Shared with Phase 9

The same scorer backs "Substitute" in the active workout (HANDOFF Phase 9). One
engine, two entry points: `rank()` for rotation, and the same call with the
current session's context for substitution. Phase 9's biomech matching becomes
the *variety* term. Do not build two engines; delete
`smart_substitution_sheet.dart`'s Phase-1 mock when wiring it.

---

## 5. Rotation policy per periodization model

This is where Concurrent / Block / Max Effort actually diverge.
`rotateEveryWeeks` stops being a user-set field on the pool and becomes a
derivation of `(model, role, phase)` with an optional per-slot override.

| Model | `main` | `supplemental` | `accessory` / `isolation` |
| --- | --- | --- | --- |
| **Max Effort** (Westside) | **2 weeks, min pool 3** — rotation *is* the progression | 3 weeks | 4 weeks |
| **Concurrent** | 4 weeks — you need the same lift long enough to read the wave | 3 weeks | 3 weeks |
| **Block** | **locked inside a phase, forced at every phase boundary** | forced at phase boundary | 3 weeks |
| **Linear** | **never** — the whole point is adding load to one lift | 4 weeks | 4 weeks |
| **None** | 2 weeks | 2 weeks | 2 weeks |

### Block: the phase also narrows the pool

| Phase | UI label | Pool tier | Prescription |
| --- | --- | --- | --- |
| `accumulation` | **Volume phase** | machines, cables, dumbbells | 4×8 @70%, ×1.2 volume |
| `transmutation` | **Strength phase** | barbell compounds | 5×5 @82% |
| `realization` | **Peak week** | **the anchor lift only, rotation off** | 3×2 @92%, ×0.7 volume |

`Periodization._block` already emits these phases and factors — this adds the
pool-tier consequence and the human-readable labels. The words *accumulation*,
*transmutation*, *accommodation*, *MEV* and *MRV* belong in this document and
never in the UI.

### The accommodation guard

A `main` slot under `maxEffort` with a pool of **< 3 members** is a hard warning
at save time. Rotating between two lifts is alternating, not accommodation.

### Rotation epochs

`RotationPolicy.epochFor(week)` returns a counter that increments exactly when a
fresh exercise is due. Two weeks sharing an epoch resolve to the same exercise,
which is what keeps the calendar stable. For phase-bound slots the epoch is the
number of phase changes so far, so "locked inside a phase" needs no special
casing anywhere else.

**Implemented:** `lib/features/programs/domain/rotation_policy.dart`

---

## 6. Prescription pipeline

One pure function, so every number on screen is traceable.

```
resolve(slot, weekIndex) =
    archetype(model, role, phase)
  × WeekPrescription(intensity, volume)     // exists: Periodization.plan()
  × exerciseAdjust(mechanics, modality, unilateral)
  × overlay(user template)
  → { sets, reps, %1RM | RIR, rest, why }
```

Exercise adjustments that matter in practice:

- **cable / selectorized / band / bodyweight** → the percentage prescription is
  dropped entirely. Stack numbers are not comparable to a barbell 1RM and
  prescribing 85% of one is fiction.
- **single-joint work in a light slot** → +2/+3 reps.
- **a ramp is never scaled.** "Work up to a heavy single" does not become "work
  up to 1.1 heavy singles" in a good week.

`why` is composed only from the factors that actually moved a number:

> "Peak week · intensity +10% · volume −30%."
> "Your \"2 to failure\" template · load by feel — percentages do not transfer
> on this equipment."

**Implemented:** `lib/features/programs/domain/prescription_resolver.dart`

---

## 7. Technique overlays — "2 sets to failure"

Failure is an **intent**, not a structure. It must compose with any `SetType`
(you can run myo-reps to failure), so it does not become a new `SetType`.

```dart
enum Intent { technical, rir3, rir2, rir1, toFailure, amrap, rampToMax }

class WorkSegment {
  final int sets, repsMin, repsMax;
  final Intent intent;
  final double? percentOf1Rm;
  final SetType setType;       // existing enum: standard | myoReps | drop | …
  final int? restSeconds;
  final Map<String, Object?> meta;
}

class SlotPrescription {
  final String name;
  final List<WorkSegment> segments;
}
```

`ProgramDayExercises` gains `targetRir` alongside the existing `targetRpe` —
store RIR, because it is what the lifter thinks in; RPE is a display conversion.

### Built-ins that ship

| Name | Reads as |
| --- | --- |
| Westside ME | `Work up to a heavy single + 3x3-5 @85%` |
| Dynamic Effort 8x3 | `8x3 @55%` |
| 2 to failure | `1x6-8 @RIR2 + 2x6-12→F` |
| Straight 3x8 RPE8 | `3x8 @RIR2` |
| Myo 1+3 | `1x12-20→F Myo Reps` |
| 20x3 @60% | `20x3 @60%` |

This is the whole "customizable but not exhausting" trick: configure "my
2-to-failure" once, then it is one chip on any slot forever.

**Implemented:** `lib/features/programs/domain/slot_prescription.dart`

---

## 8. The zero-input path

**The single most important UX property of this feature.**

A user who opens the builder and presses Next four times without touching
anything must get a program that is *actually good* — correct volume, sane
rotation, exercises they own equipment for. Every screen has a correct default;
customization is an opt-in layer on top, never a prerequisite.

Concretely this means every step must be able to answer "what happens if the
user does nothing here?" with a real answer, not an empty state:

| Step | If the user does nothing |
| --- | --- |
| Basics | 4 weeks, their current split, the model their last program used |
| Split | the spacing table already in `SplitTemplates.weekdaySpacing` |
| Pools | pre-filled from favourites → history → catalog, filtered by their gym |
| Techniques | archetypes per model; RIR 2 everywhere |
| Preview | valid program, save enabled |

If a step cannot produce a good default, that step is a design failure, not a
user problem.

---

## 9. Builder flow

Reworking `block_builder_view.dart` from 4 steps to 5.

| Step | Content | Status |
| --- | --- | --- |
| 1 | **Basics** — goal, model, weeks, days/week | exists |
| 2 | **Split + Blueprint** | split exists; blueprint new |
| 3 | **Pools** ← *the heart* | new |
| 4 | **Techniques** | new |
| 5 | **Preview** | partly exists |

### 9.1 Step 3 — Pools

One card per muscle group present in the split. Nothing else on the screen.

**Card anatomy**

```
┌───────────────────────────────────────────────┐
│ CHEST                     ▮▮▮▮▮▮▮▯▯▯  On target│
│                                                │
│ ⭐Barbell Bench   ●Close-Grip   ●Floor Press   │
│ ●Incline DB      ○Dips          ○Machine Press │
│                                    + 9 more    │
│                                                │
│ Rotates every 2 weeks · 4 in pool              │
└───────────────────────────────────────────────┘
```

**Chip states**

| State | Meaning |
| --- | --- |
| ⭐ filled | core lift — always included, never rotated out |
| ● filled | in the pool |
| ○ outline | available, not in the pool |
| strikethrough | marked never |
| 🔒 badge | pinned to a specific role |

**Interactions** — chip-level only, no forms:

- tap → toggle in/out of the pool
- long-press → sheet: *Always include · Never · Set role · Open exercise*
- drag → reorder (order is a tiebreak, not a schedule)
- "+ N more" → the existing exercise picker, filtered to this muscle group

**The volume bar in the header is live.** Toggling a chip moves it immediately.
Four states — *Light · On target · Hard · Over* — never a raw MEV/MRV number.
The number is available on tap for people who want it.

**Inline warnings**, amber, inside the card, never a blocking dialog:

> ⚠ Max effort needs at least 3 variations to work. Add one more.

The decisive detail: **the card arrives pre-filled and already valid.** It shows
what the app chose and why. An empty state here would turn the best feature in
the app into homework.

### 9.2 Step 4 — Techniques

Three controls. Not more.

1. **Default intent** — one slider: `Technical · 3 RIR · 2 RIR · 1 RIR · Failure`
2. **Take the last set to failure** — one switch. The single most-asked-for
   thing, and it should not require understanding the template system.
3. **Prescription chips** — the built-ins plus anything the user has saved.
   Dropping one on a *role* (not a slot) applies it everywhere that role
   appears: "all my accessory work is 2-to-failure" is one tap.

Per-slot overrides are reached from the preview, where the user can see what
they are overriding — not from here.

### 9.3 Step 5 — Preview

The grid: rows = weeks, columns = days, cells = the resolved exercises.

**The only thing emphasized is change.** A cell whose exercise differs from the
previous week gets an accent bar and full-weight text; everything unchanged is
dimmed. This is what turns a wall of 120 exercise names into "here is what
actually varies", and it is what makes rotation legible instead of noisy.

Tap any exercise → sheet with:

- the prescription, formatted (`3x8 @RIR2`)
- the `why`, verbatim from the scorer
- **Swap** — the next three candidates, each with its own one-line why
- **Pin** — freeze this exercise for the rest of the program
- **Change technique** — the chip row from step 4, scoped to this slot

Below the grid: volume bars per muscle group, same four states as step 3.

Bottom bar: **Save** (primary) · **Shuffle** (secondary, undoable).

### Swap, not re-roll (D5)

No dice icon anywhere. **Swap** shows a ranked list of three alternates, each
with its reason. A dice is a slot machine; a ranked list with reasons teaches
the user what the engine optimizes for, and after a week of using it they
predict the app instead of fighting it.

**Per-week re-roll is deliberately rejected.** Under Max Effort and Block the
rotation cadence *is* the method. Letting someone re-roll week 3 alone silently
breaks the accommodation schedule, and the app cannot honestly explain what it
did afterwards. Per-slot Swap and whole-program Shuffle cover every real use
without that.

---

## 10. Planned + drift (D1)

### 10.1 Materialize

```dart
class RotationAssignments extends Table with SyncColumns, SyncTombstone {
  IntColumn  get id         => integer().autoIncrement()();
  IntColumn  get programId  => integer().references(Programs, #id,
                                onDelete: KeyAction.cascade)();
  IntColumn  get slotId     => integer()();      // ProgramDayExercises.id
  IntColumn  get weekIndex  => integer()();
  IntColumn  get exerciseId => integer().references(ExerciseCatalog, #id,
                                onDelete: KeyAction.restrict)();
  TextColumn get reason     => text().nullable()();   // the `why`
  TextColumn get source     => text().withDefault(const Constant('planned'))();
                                // planned | drifted | manual
}
```

Written at build time for every week. The calendar and the preview both read
this table, which is why they agree.

### 10.2 Drift

At **session start** — not before, fatigue data must be current — re-run the
scorer for that day's slots. If the winner differs from the assignment *and* a
named trigger fired, surface one card above the first exercise:

```
┌─────────────────────────────────────────────┐
│ Your Close-Grip Bench hasn't gone up in     │
│ 3 sessions.                                  │
│                                              │
│ Close-Grip Bench  →  Floor Press             │
│                                              │
│ [ Swap ]            [ Keep my plan ]   why?  │
└─────────────────────────────────────────────┘
```

**Exactly one card per session.** If several triggers fire, show the highest
priority only — equipment > stagnation > recovery. A card the user has to
dismiss twice is a nag, and a nag gets ignored along with everything else the
app says.

Rules:

- **never silent.** One tap to accept, one to dismiss.
- accepting writes a `RotationAssignments` row with `source = 'drifted'`
- dismissing is recorded too
- drift affects the current session only, unless the user picks
  "apply to the rest of the block"

### Quiet mode, learned (D6)

Not a settings toggle — nobody finds those, and the people who need it most are
the ones already annoyed. After **three dismissals of the same trigger type**,
ask once, inline:

> You've kept your plan three times. Stop suggesting swaps when a lift stalls?

Mute is per trigger type, reversible from program settings. Separately, a
per-program **Locked plan** switch turns drift off entirely — for people
following a coach's program, where the plan is the deliverable and second-
guessing it is worse than useless.

---

## 11. Volume bands (D4)

Population priors for all 19 groups ship in `VolumeBands.priors`, expressed as
`(minimum, adaptive, maximum)` weekly working sets. They exist so a user with no
history still gets a program that is neither pointless nor injurious.

As the user trains, the band shrinks toward what they have actually sustained:

```
maximum = prior × (1 − blend) + personal × blend
blend   = weeksObserved / (weeksObserved + 4)
```

`personal` is the highest weekly set count held for two or more consecutive
weeks without a drop in performance on that group's lifts. The band keeps the
prior's proportions as it moves, so `minimum < adaptive < maximum` always holds.
Four weeks of shrinkage is fast enough to adapt within a block and slow enough
that one deload week does not rewrite the band. The band is only *labelled*
personal after six observed weeks.

The user never sees "MEV" or "MRV". They see *Light · On target · Hard · Over*.

**Implemented:** `lib/features/programs/domain/volume_bands.dart`

---

## 12. Save-time guardrails

All warnings with an override, except where noted.

| Check | Threshold |
| --- | --- |
| weekly sets per muscle group | inside the band (§11) |
| ME frequency per movement pattern | ≤ 2 / week |
| weekly CNS estimate | Σ(`cnsScore` × sets × `SlotPrescription.cnsUnits`) under budget |
| **ME pool size** | ≥ 3 members — **hard warning** |
| slot with an empty pool after filters | **blocks save** |

---

## 13. Schema delta — v24, additive only

**New tables**
- `ExercisePreferences`
- `PrescriptionTemplates` — `id, name, payload (JSON SlotPrescription), scope, isBuiltIn`
- `RotationAssignments`

**`ExerciseRotations` +**
- `strategy` — `round_robin | stagnation | smart` (default `smart`)
- `minGapWeeks` — default 3
- `poolSource` — `manual | favorites_by_muscle`
- `muscleGroup` — nullable

**`ProgramDayExercises` +**
- `slotRole` — default `accessory`
- `prescriptionTemplateId` — nullable
- `targetRir` — nullable
- `overlayJson` — nullable

`rotateEveryWeeks` stays on `ExerciseRotations` but becomes an **override**:
null ⇒ derive from `(model, role, phase)`.

Every existing program keeps working: no `slotRole` ⇒ `accessory`, no
`RotationAssignments` ⇒ fall back to `activeMemberIndex`.

---

## 14. Build order

| # | Step | State |
| --- | --- | --- |
| 1 | Pure-Dart engine core + unit tests | **done** — see §14.1 |
| 2 | `ExercisePreferences` table + ⭐ in the catalog | next |
| 3 | Repository layer: build `ScorerCandidate`s from catalog + history + gym | next |
| 4 | `RotationAssignments` + materialize at build; preview reads it | |
| 5 | Builder step 3 (Pools) | |
| 6 | `PrescriptionTemplates` + builder step 4 | |
| 7 | Tune the stagnation / recovery / CNS weights against real data | needs 2–3 weeks of logs |
| 8 | Drift cards at session start | |
| 9 | Point Phase 9 "Substitute" at the same scorer; delete the mock | |

Steps 2–5 deliver most of the felt value.

### 14.1 What already exists

```
lib/features/programs/domain/
  slot_role.dart             SlotRole, SlotRoleEligibility.derive
  rotation_policy.dart       RotationPolicy.forSlot, PoolTier, epochFor
  exercise_scorer.dart       ScorerCandidate, SlotScoringContext, rank/pick
  slot_prescription.dart     Intent, WorkSegment, SlotPrescription, builtIns
  prescription_resolver.dart archetypes + the resolve pipeline
  volume_bands.dart          priors, shrinkage, four-state verdicts

test/features/programs/
  slot_role_test.dart
  rotation_policy_test.dart
  exercise_scorer_test.dart
  slot_prescription_test.dart
  prescription_resolver_test.dart
  volume_bands_test.dart
```

All pure Dart — no Flutter widgets, no drift, no codegen. `flutter test` runs
them as-is.

---

## 15. UI copy rules

Small, and they decide whether this feels intelligent or arbitrary.

- Never show a number without a unit or a `why` behind it.
- Never use *MEV*, *MRV*, *accommodation*, *transmutation*, *realization* in the
  UI. Phases read **Volume phase · Strength phase · Peak week**.
- The `why` is one sentence, lowercase after the exercise name, ending in a
  full stop. It names the reason, never the mechanism: "not trained for 5
  weeks", not "staleness term 1.5".
- The builder is resumable — save a draft on every step transition.
- The preview is reachable from the program later, not only at build time.
- A rotation change shows on the calendar tile too: **New: Floor Press**.
