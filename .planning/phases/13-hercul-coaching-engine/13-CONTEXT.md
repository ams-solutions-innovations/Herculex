# Phase 13 — Context: how Hercul generates an answer

## The premise

Hercul is **not an AI**. Every message is an authored string chosen by a
deterministic rule over the user's own data. That means it works offline, it
costs nothing to run, it never invents a number, and every sentence can be
traced back to a row in a JSON file. It also means the corpus is the product —
the engine is about 200 lines and will not change much; the rules will grow
forever.

Hercul adds **no new analytics**. Everything it says is already computed:
`CnsTrends`, `MuscleRecoveryV3` (including `warnings()`, which the app computes
today and renders nowhere), `WeeklyMuscleVolume`, `BalanceAnalyzer`,
`DailyTotals` against `MacroTargets`, `BodyMeasurements`, `TrainingSnapshot`.
Hercul is the layer that decides which of those facts is worth saying out loud
today, and in which voice.

## The pipeline

```
  existing engines            HerculContext              hercul_rules.json
  (CnsTrends, Recovery,  ──▶  flat signal maps    ◀──    authored rules
   Volume, Nutrition,          + `now`                    (data, not code)
   Bodyweight, History)             │                          │
                                    └──────────┬───────────────┘
                                               ▼
                                       HerculEngine.evaluate
                                    (pure: no DB, no Flutter)
                                               │
                                    ranked List<HerculMessage>
                                               ▼
                                      dashboard Hercul card
```

## HerculContext — the closed vocabulary

`lib/features/hercul/domain/hercul_context.dart`. Three maps and a clock:

| shape | holds | example |
|---|---|---|
| `scalars` | one number per signal | `cns.readiness → 0.31` |
| `series` | signal → subject → number | `volume.weeklySets → {Chest: 14, Rear Delts: 3}` |
| `labels` | categorical signals | `profile.goal → weightLoss` |

**A missing signal is `null`, never `0`.** "No food logged yet" and "ate zero
protein" would otherwise be the same fact, and Hercul would greet a fresh
install by accusing the user of undereating. Every signal name lives in
`HerculSignals.all`, and a test rejects any rule referencing something outside
it — the corpus is data, so nothing else would catch `nutrition.protienPct7d`
before it silently never fired.

Argument-keyed signals (`volume.weeklySets`, `exercise.lastPerformedDays`,
`body.weightDeltaKg`, `exercise.e1rmRatio`) are listed in
`HerculSignals.argumentSignals`, and a test checks each is given an argument and
that non-argument signals are not.

`exercise.e1rmRatio` is keyed `"slugA:slugB"` because a condition compares a
signal to a constant, not to another signal — and the interesting question is
nearly always relative ("is your deadlift keeping up with your squat"), which
also makes the threshold portable across strength levels.

## The rule format

`assets/data/hercul_rules.json`. One object per rule:

```json
{
  "id": "rear-delts-neglected",
  "domain": "volume",
  "priority": 80,
  "cooldownDays": 7,
  "requires": ["nutrition.daysLogged7d"],
  "when": [
    { "signal": "volume.weeklySets", "arg": "Rear Delts", "op": "<", "value": 6 },
    { "signal": "volume.weeklySets", "arg": "Chest", "op": ">", "value": 12 }
  ],
  "copy": {
    "normal": "Hercul sees {volume.weeklySets:Chest|int} chest sets and …",
    "honest": "Hercul sees {volume.weeklySets:Chest|int} sets of chest and …"
  },
  "cta": { "type": "route", "value": "/insights" }
}
```

| field | meaning |
|---|---|
| `id` | stable, unique; the cooldown log keys on it, so never reuse one |
| `domain` | `recovery`, `volume`, `nutrition`, `bodyweight`, `consistency`, `ergonomics`. At most one message per domain per render |
| `priority` | 0–100, highest first. Ties break on `id`, so the card never reshuffles between rebuilds |
| `cooldownDays` | quiet period after firing. Without it, a true fact — "you have not squatted in three weeks" — is repeated every single morning |
| `requires` | signals the *copy* needs but the conditions do not mention |
| `when` | all clauses must hold (AND only) |
| `copy` | **both tones mandatory**; the parser throws without `honest` |
| `cta` | optional. `route` pushes a path, `substitute` opens the substitution sheet |

**Operators:** `<`, `<=`, `>`, `>=`, `==`, `!=`, `between` (inclusive, needs
`upper`). Label signals compare with `"text"` instead of `"value"`; ordering a
label is treated as unsatisfiable rather than silently true.

`when` is deliberately AND-only. An `any` block is easy to add later and
impossible to remove once the corpus depends on it.

**Placeholders:** `{signal}`, `{signal:arg}`, `{signal|fmt}`,
`{signal:arg|fmt}`. Formats: `int`, `1dp`, `pct` (0.78 → "78"), `kg`, `abs`
(magnitude, so the copy supplies the direction — "0.2 kg" reads better than
"-0.2 kg" inside a sentence that already says the weight barely moved). An
unresolved placeholder renders as `—` rather than throwing: a rule is data, and
a typo in one string should degrade that message, not take down the dashboard.

## Evaluation order

1. Drop rules inside their cooldown.
2. Drop rules with any unresolved signal (`when` clauses *and* `requires`).
3. Keep rules where every clause holds.
4. Sort by priority desc, then id.
5. Keep at most one per domain, then cap at 3.

Step 2 is the important one. `HerculCondition.evaluate` returns `bool?` — `null`
means "the signal was never resolved", which is not the same as a failed
comparison, and the engine skips the rule instead of treating absence as data.

## The two voices

**Hercul** — plain, encouraging, states the number.

**Honest Hercul** — sharp and disappointed about *training*. Opt-in behind a
settings toggle and an 18+ check. It is blunt about the work: "you are paying
for the gym and refusing to collect", "Hercul is not angry, just disappointed".
It never targets the user's body, weight or sex, and carries no profanity —
which is both the tone brief and the reason the store rating does not move.

A test enforces this with a banned-word list (`fat`, `weak`, `pathetic`,
`lazy`, `pussy`, `bastard`, …) across both tones, so a future rule cannot cross
the line quietly. Another test requires the two tones to be *different text*, so
`honest` is never a copy-paste of `normal`.

Balance the corpus so encouraging and neutral rules outnumber corrective ones. A
card that only ever nags gets switched off, and then none of it works.

## Storage: asset now, cloud later

The corpus ships as a bundled asset and is read into memory. The next step is
importing it into a Drift `hercul_rules` table via an importer modelled on
`exercise_importer.dart` (idempotent upsert on `id`), plus a `hercul_message_log`
table persisting `ruleId → lastFiredAt` so cooldowns survive a restart. Because
the engine already takes `rules` and `lastFiredAt` as parameters, swapping the
source from asset to table to Supabase changes nothing in the domain.

## Status

Built and tested: `hercul_context.dart`, `hercul_rule.dart`,
`hercul_engine.dart`, `assets/data/hercul_rules.json` (22 rules across all six
domains, both tones), `test/hercul_engine_test.dart` (25 tests).

Not yet built: the `HerculContext` factory that reads the live providers, the
Drift tables, the dashboard card, and the settings toggle. Those are 13-01,
13-02's persistence half, and 13-03.
