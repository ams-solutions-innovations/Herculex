# Phase 28: Adaptive TDEE & Activity Calibration - Research

**Researched:** 2026-09-28
**Domain:** Deterministic statistical estimation over existing local data (energy-balance math,
signal smoothing, drift/Supabase schema) — no AI, no new external packages.
**Confidence:** MEDIUM (domain/formula math is HIGH confidence and codebase integration points
are VERIFIED by direct code read; the specific numeric constants for window/cadence/hysteresis/
classifier-weighting are informed recommendations, not externally mandated values — see
Assumptions Log).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Adherence threshold (gates observed-expenditure vs. activity-classifier)**
- **D-01:** A "logged day" for the food-diary side of adherence means food was logged that
  day. Bodyweight adherence is checked separately: enough distinct bodyweight logs somewhere
  in the same window, not required to be the same days as food logs. Two independent gates,
  not one combined daily requirement.
- **D-02:** The bar is **~70% of window days** with food logged (e.g. 10 of the last 14) to
  qualify for observed-expenditure mode. Exact bodyweight-log count within the window and the
  precise window length itself are research/planning's job.
- **D-03:** Method switching requires **sustained crossing**, not an immediate flip on a
  single recalibration where adherence happens to sit right at the line. Exact dwell/hysteresis
  mechanism is planning's job.
- **D-04:** When a user was on observed-expenditure and then stops logging, the app holds the
  **last observed estimate** (clearly labelled as aging/stale) for a grace period before
  falling back to the activity classifier. Exact grace-period length is planning's job.

**Estimate visibility (TDEE-04: method, confidence, window, inputs — always visible)**
- **D-05:** An inline badge next to "Maintenance calories" in `nutrition_targets_view.dart`
  (e.g. "Measured · High confidence" or "Classified · Medium confidence") that expands via tap
  into a detail sheet with method, window, confidence, and the inputs used. Not an
  always-expanded card, not a separate hidden screen.
- **D-06:** When the classifier is active, its underlying `HealthSamples` inputs (e.g. "avg
  9,200 steps/day, 3 logged workouts/week") are shown individually in the detail sheet, not
  collapsed into a bare confidence label.
- **D-07:** The detail sheet shows the live estimate **and** the user's currently-saved manual
  target side by side when one exists (e.g. "Your target: 2,400 kcal (set manually) · Current
  estimate: 2,290 kcal") — this same comparison is what the weekly-report material-shift prompt
  (D-08/D-09) will surface later.
- **D-08 (cold start):** Before enough data exists (brand-new user), the badge reads a
  "Calibrating" state (e.g. "Calibrating — using onboarding estimate") and the number shown is
  Mifflin-St Jeor × the onboarding `ActivityLevel` pick, used purely as a seed. Never blank,
  never an error state.

**Material-shift handling (TDEE-05: surfaced in weekly report, never silent)**
- **D-09:** A shift counts as "material" when it exceeds **whichever is bigger: ±100 kcal or
  ±5% of the current baseline**.
- **D-10:** When surfaced in the (future, Phase 29) weekly report, it's an **explicit
  accept/dismiss prompt** — "Update my target to X" / "Keep current target" — not passive
  information.
- **D-11 (Phase 28 ↔ Phase 29 handoff):** Phase 28 is responsible for persisting **TDEE
  estimate history only** — a table of estimates over time (method, confidence, window, kcal,
  timestamp) via its own 5-chore schema bump. It does **not** additionally emit a distinct
  "material shift detected" event/record. Phase 29 computes "was there a material shift this
  week" itself by diffing that history using the D-09 threshold.

**Onboarding activity picker**
- **D-12:** The onboarding `ActivityLevel` question is **kept**, but reframed in copy as a
  starting estimate rather than a permanent setting.
- **D-13:** After a user has calibrated (past the "Calibrating" cold-start state), the
  `ActivityLevel` picker **stays visible and editable in Profile**, relabeled as a manual
  reset/nudge.
- **D-14:** A manual reset from Profile **reseeds only** — it becomes the new seed value for
  the next classifier recalibration but does **not** discard prior TDEE estimate history.
- **D-15:** A manual reset does **not** force the method back to "Calibrating"/classifier-seeded
  if the user currently qualifies for observed-expenditure mode under D-01–D-04.

### Claude's Discretion (resolved by this research — see Open Questions Resolved below)
- Exact calibration window length and re-calibration cadence mechanics (TDEE-03).
- Exact bodyweight-log count required within the window for D-01's "enough weight logs" gate.
- Exact hysteresis/dwell mechanism for D-03.
- Exact grace-period length in D-04.
- Weight-trend smoothing method (EWMA vs. moving average vs. another technique).
- Exact activity-classifier output shape (4-tier `ActivityLevel` enum vs. continuous multiplier).
- Exact TDEE-estimate-history table schema for D-11.

### Deferred Ideas (OUT OF SCOPE)
- The exact weekly-report UI/screen that renders the D-10 accept/dismiss prompt — Phase 29's job
  entirely; this phase only needs to persist the estimate history Phase 29 will diff (D-11).
- PHYS-04 (underage users / low-confidence visual assessments barred from aggressive
  deficits/surpluses) — Phase 23's requirement, not yet built. Phase 28 must not create a
  bypass but does not implement the gate itself. See "PHYS-04 Integration Point" below.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TDEE-01 | Observed-expenditure estimator derives TDEE from logged intake + bodyweight trend over a rolling window; becomes baseline when adherence passes threshold | See "Architecture Patterns → TdeeEstimator", "Code Examples → Observed-Expenditure Formula", "Open Questions Resolved #1, #2, #5" |
| TDEE-02 | Activity classifier derives activity level from `HealthSamples` + logged training when adherence insufficient; Mifflin-St Jeor runs with derived multiplier | See "Open Questions Resolved #6", "Code Examples → Classifier Multiplier" |
| TDEE-03 | App self-selects calibration window and re-calibration cadence; user never picks a duration | See "Open Questions Resolved #1" |
| TDEE-04 | Every estimate carries method/confidence/window/inputs, is visible, never overrides a manually-set maintenance value | See "Reusable Assets → TargetResolver", "Don't Hand-Roll", "Common Pitfalls #1" |
| TDEE-05 | Material TDEE shift surfaced in weekly report, never silently rewrites confirmed targets | See "Open Questions Resolved #7", D-09/D-11 (locked, not re-researched) |
</phase_requirements>

## Summary

This phase replaces one line of arithmetic (`MacroTargets.fromProfile`'s hand-picked
`ActivityLevel` multiplier lookup) with a small deterministic estimation subsystem that reads
data the app already stores — the food diary (`FoodEntries`), bodyweight logs
(`BodyMeasurements` where `metric == 'bodyweight'`), and passive telemetry (`HealthSamples`:
`steps`/`sleep_hours`/`active_kcal`/`resting_hr`) — and writes one new synced table
(`TdeeEstimates`, drift v45). There is exactly one integration point,
`baselineTargetsProvider` (`nutrition/application/nutrition_providers.dart:69`), and the
existing `TargetResolver` already guarantees a saved manual target always wins over whatever
that provider returns, so TDEE-04's "never overrides a manual value" requirement needs **no new
code** to be true — only needs verifying with a test, since none currently exists for
`target_resolver.dart`.

The math is well-established outside this codebase (MacroFactor and comparable adaptive-TDEE
tools use the identical `TDEE ≈ mean intake − Δstored_energy/days` back-calculation with
EWMA-smoothed bodyweight and a 14–28 day rolling window), which gives HIGH confidence to the
formula itself and MEDIUM confidence to the specific constants this research recommends
(window bounds, EWMA alpha, hysteresis depth, grace period). None of those constants are
mandated by any spec — they are tuning knobs the plan should implement as named constants in
one place (mirroring how `DietPhaseCalculator` already centralizes its own tunable constants:
`defaultCutPct`, `cutProteinPerKg`, etc.) so they can be revised after real usage without a
redesign.

The project has no background-task capability (no `workmanager`, no
`android_alarm_manager` in `pubspec.yaml` — confirmed absent), which the design doc already
established as the reason Phase 29's Sunday report must be generated on open rather than in a
notification callback. The same constraint applies here: recalibration cannot be a scheduled
job. It must be an opportunistic check (cheap "is it time yet?" comparison) run when the
nutrition screen loads / app foregrounds, not a reactive recompute on every food log.

**Primary recommendation:** Build a pure-Dart `TdeeEstimator` domain service (formula +
adherence gates + hysteresis + classifier, fully unit-testable, zero Flutter/drift imports,
mirroring `target_resolver.dart`'s existing shape), a thin `TdeeEstimatesRepository` for the new
table, and wire both into `baselineTargetsProvider` via a new intermediate provider — leave
`DietPhaseCalculator`, `TargetResolver`, and the phase-math pipeline completely untouched.

## Architectural Responsibility Map

> Herculex is an offline-first Flutter client (no application server beyond Supabase
> Postgres+Edge Functions used only for AI/sync), so the standard web-tier table doesn't fit.
> This maps each capability to the project's own feature-first layers instead
> (`domain/` → `data/` → `application/` → `presentation/`, per `CLAUDE.md`).

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Observed-expenditure formula (intake − Δweight×7700/days) | Domain | — | Pure math, no I/O; must be unit-testable in isolation like `target_resolver.dart` |
| Bodyweight EWMA smoothing | Domain | — | Pure function over a list of (date, value) pairs |
| Adherence gate (food-logged %, bodyweight-log count) | Domain | Data | Domain owns the threshold logic; Data supplies the raw counts (`FoodEntries`, `BodyMeasurements` queries) |
| Method hysteresis / dwell state | Domain | Data | Domain owns the state machine; the `TdeeEstimates` history table itself is the persisted state (no separate flag table needed — see schema below) |
| Activity classifier (HealthSamples → multiplier) | Domain | Data | Domain owns the weighting/curve; Data supplies `HealthSamples` rows + logged-workout counts |
| Window/cadence self-selection (TDEE-03) | Domain | Application | Domain computes "what window given this data density"; Application decides *when* to invoke it (app-open gate) |
| `TdeeEstimates` persistence (schema v45) | Data | — | New drift table + repository, standard 5-chore bump |
| `baselineTargetsProvider` wiring | Application | — | Riverpod provider composition only; `TargetResolver`/`DietPhaseCalculator` untouched |
| Estimate badge + detail sheet (D-05–D-08) | Presentation | — | New `part`/`part of` file under `nutrition_targets_view.dart`'s subfolder — file is already 1450+ lines |
| Manual reset flow (D-12–D-15) | Presentation | Application | Existing `ActivityLevel` picker in Profile; write path unchanged, only copy/label changes |
| Weekly-report diffing (D-11 consumer) | Out of phase scope | — | Phase 29 reads `TdeeEstimates` history; Phase 28 only writes it |

## Standard Stack

**No new external packages are required.** This phase is pure Dart domain logic over data the
app already collects, plus a standard drift/Supabase schema bump. `drift`, `flutter_riverpod`,
and `health` are already dependencies and already used by the exact tables/providers this phase
reads (`HealthSamples`, `BodyMeasurements`, `FoodEntries`, `health_providers.dart`).

### Core (reused internal components — not new packages)
| Component | Location | Purpose | Why reuse |
|---|---|---|---|
| `TargetResolver`/`TargetRule` | `lib/features/nutrition/domain/target_resolver.dart` | Manual-target-wins resolution | Already makes TDEE-04's core guarantee true by construction — do not duplicate this logic |
| `MacroTargets.fromProfile` | `lib/features/nutrition/domain/macro_targets.dart` | Mifflin-St Jeor + multiplier + goal adjustment | The exact formula the classifier fallback must keep feeding; needs a small refactor (see Open Questions Resolved #6), not a rewrite |
| `MeasurementsRepository.latestBodyweightKg` / `watchMetric('bodyweight')` | `lib/features/measurements/data/measurements_repository.dart` | Bodyweight log source | Direct data source for D-01's bodyweight-adherence gate and the Δweight term |
| `HealthSamples` table + `HealthService` | `lib/data/local/tables.dart:1122`, `lib/features/health/data/health_service.dart` | `steps`/`sleep_hours`/`active_kcal`/`resting_hr` | Direct data source for the classifier; already populated, no schema change needed for it |
| `Clock`/`clockProvider` | `lib/core/utils/clock.dart` | Injectable "now" | **Mandatory** — CLAUDE.md: "All time-of-day math goes through Clock." Any window/cadence code that calls `DateTime.now()` directly breaks tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled EWMA (≈3 lines: `trend = trend + alpha*(raw-trend)`) | A pub.dev moving-average package | Not worth a dependency for one arithmetic line; also no vetted package specifically implements the Hacker's-Diet-style gap-filled EWMA this domain wants |
| Hand-rolled hysteresis counter | A state-machine package (e.g. a formal FSM library) | Overkill for a 2-state, 1-counter dwell rule; adds a dependency for something expressible in ~15 lines, inconsistent with the rest of the domain layer's style |

**Installation:** None — no `pubspec.yaml` changes required for this phase.

## Package Legitimacy Audit

**Not applicable — this phase installs no external packages.** All new code is pure Dart domain
logic plus a drift table addition using already-declared dependencies (`drift`, `uuid` via the
existing `SyncColumns` mixin). Skip the slopcheck/registry-verification gate.

## Architecture Patterns

### System Architecture Diagram

```
                 ┌────────────────────────────────────────────────┐
                 │  App open / nutrition screen load (Application) │
                 └───────────────────────┬────────────────────────┘
                                          │ "is it time to recalibrate?"
                                          ▼
                 ┌────────────────────────────────────────────────┐
                 │   TdeeEstimatesRepository.latestEstimate()      │◄───── TdeeEstimates table
                 │   → compare estimatedAt vs. Clock.now()         │        (drift v45, synced)
                 └───────────────────────┬────────────────────────┘
                     elapsed ≥ cadence OR bodyweight-trend shift OR
                     activity-pattern shift (all read from Data layer)
                                          ▼
                 ┌────────────────────────────────────────────────┐
                 │              TdeeEstimator (Domain)             │
                 │  1. adherence gate: FoodEntries % + BodyMeas.   │
                 │     count in self-selected window               │
                 │  2a. PASS → observed-expenditure formula        │
                 │       (mean intake − Δ EWMA-weight×7700/days)   │
                 │  2b. FAIL → activity classifier over            │
                 │       HealthSamples + logged training            │
                 │  3. hysteresis: only *switch* method after N     │
                 │     consecutive qualifying recalibrations        │
                 │  4. grace period: hold last observed (stale)     │
                 │     before falling back to classifier             │
                 └───────────────────────┬────────────────────────┘
                                          │ TdeeEstimateResult
                                          │ (kcal, method, confidence,
                                          │  windowDays, inputsJson)
                                          ▼
                 ┌────────────────────────────────────────────────┐
                 │  TdeeEstimatesRepository.record(result)          │──► persists new row
                 └───────────────────────┬────────────────────────┘
                                          ▼
                 ┌────────────────────────────────────────────────┐
                 │  baselineTdeeProvider (Application, new)         │
                 │  reads latest TdeeEstimates row, falls back to   │
                 │  Mifflin-St Jeor × onboarding ActivityLevel      │
                 │  when no row exists yet (D-08 cold start)         │
                 └───────────────────────┬────────────────────────┘
                                          ▼
                 ┌────────────────────────────────────────────────┐
                 │  baselineTargetsProvider (existing, unchanged     │
                 │  signature) — now sources its kcal from the       │
                 │  provider above instead of the raw ActivityLevel  │
                 │  multiplier                                       │
                 └───────────────────────┬────────────────────────┘
                                          ▼
                 ┌────────────────────────────────────────────────┐
                 │  TargetResolver.resolve() (existing, untouched)   │
                 │  manual NutritionTargetData row still wins        │
                 └───────────────────────┬────────────────────────┘
                                          ▼
                 ┌────────────────────────────────────────────────┐
                 │  DietPhaseCalculator.apply(baselineKcal:) →        │
                 │  effectiveTargetsProvider (existing, untouched)   │
                 └────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
lib/features/nutrition/
├── domain/
│   ├── target_resolver.dart          # existing, untouched
│   ├── macro_targets.dart            # existing, small refactor (see below)
│   ├── tdee_estimator.dart           # NEW — pure Dart, formula + gates + hysteresis
│   ├── tdee_estimate.dart            # NEW — TdeeEstimateResult value type + Method/Confidence enums
│   └── activity_classifier.dart      # NEW — HealthSamples+training → multiplier (separate file:
│                                      #   keeps tdee_estimator.dart focused on the observed-
│                                      #   expenditure half; classifier is its own testable unit)
├── data/
│   └── tdee_estimates_repository.dart # NEW — drift reads/writes for the new table
├── application/
│   └── nutrition_providers.dart      # baselineTargetsProvider modified; new
│                                      #   baselineTdeeProvider added
└── presentation/
    └── views/
        └── nutrition_targets_view/    # NEW subfolder (view file is 1450+ lines, over the
            └── _tdee_badge.part.dart  #   600-line cap) — part/part of, per CLAUDE.md
```

### Pattern 1: Pure-Dart domain service, zero Flutter/drift imports
**What:** `TdeeEstimator` and `ActivityClassifier` take plain Dart types (`List<(DateTime, double)>`
for weight logs, `int` counts for adherence, `double` averages for `HealthSamples`) and return
plain Dart result objects — no `AppDatabase`, no `Ref`, no `DateTime.now()`.
**When to use:** Always, for this phase's core math — mirrors `target_resolver.dart` exactly,
which is why that file has zero test-setup friction today.
**Example:**
```dart
// Source: pattern derived from lib/features/nutrition/domain/target_resolver.dart
// (existing file, same "pure static methods over plain data" shape)
class TdeeEstimator {
  static TdeeEstimateResult estimate({
    required List<MapEntry<DateTime, double>> weightLogs,
    required List<MapEntry<DateTime, double>> dailyIntakeKcal, // 0 entries on unlogged days
    required int windowDays,
    required DateTime asOf,
  }) { /* ... */ }
}
```

### Pattern 2: Opportunistic recalibration check, not a reactive StreamProvider
**What:** Recalibration is triggered by a cheap comparison against `Clock.now()` performed once
per app-open / nutrition-screen-load, not by a `StreamProvider` that recomputes on every
`FoodEntries` insert.
**When to use:** For the "when do we recalibrate" gate specifically (TDEE-03's cadence half).
The *display* of the current estimate can still be a `StreamProvider` reading the latest
`TdeeEstimates` row (cheap — single-row query) — only the expensive recompute-and-persist step
needs to be gated.
**Example:**
```dart
// Source: pattern — no direct precedent in codebase for a "gated recompute", but
// nutrition_providers.dart's own averageWeeklyMacroProvider (line ~887) already shows the
// house style for "derive from history, Provider.autoDispose, no live recompute on every entry".
final tdeeRecalibrationGateProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(tdeeEstimatesRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final last = await repo.latestEstimate();
  if (last != null &&
      clock.now().difference(last.estimatedAt) < recalibrationCadence &&
      !await repo.hasTriggerCondition(since: last.estimatedAt)) {
    return; // not time yet, no material shift, no activity-pattern change
  }
  final result = TdeeEstimator.estimate(/* ... */);
  await repo.record(result);
});
```

### Anti-Patterns to Avoid
- **Recomputing TDEE inside `effectiveTargetsProvider` or on every `FoodEntries` write:**
  expensive (scans a multi-week window) and thrashy (a single new log entry shouldn't move the
  displayed baseline until an actual recalibration event fires per TDEE-03/D-03).
- **Threading the classifier's continuous multiplier through the 4-value `ActivityLevel` enum:**
  re-introduces the exact ±15% bucket-error problem this phase exists to fix (see Open
  Questions Resolved #6).
- **A second "manual override" flag on the new table:** `TargetResolver` already owns that
  distinction. Do not add `isManual`/`isLocked` columns to `TdeeEstimates` — the manual-target
  precedence lives entirely in `NutritionTargetData` + `TargetResolver`, one layer up.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "Which day-of-week / ISO-week is this" | A custom week-boundary calculator | Existing `intl`/`DateFormat` usage already in `nutrition_providers.dart` (`DateFormat('yyyy-MM-dd')`) | Consistency with the rest of the codebase; ISO-week logic is explicitly Phase 29's territory, not this phase's |
| kcal↔kg conversion constant | A different or "more precise" energy-density constant | The locked `7700 kcal/kg` from CONTEXT.md/design doc | Already a locked decision; a different constant would silently disagree with the design doc's own worked examples |
| JSON snapshot of estimate inputs (for D-06/D-07 detail sheet) | Manual string concatenation | `dart:convert`'s `jsonEncode`/`jsonDecode`, same as `wearSyncControllerProvider`'s payload building in `nutrition_providers.dart` | Existing house pattern; also makes the stored `inputsJson` column trivially round-trippable in tests |
| "Does today have logged food" | A new bespoke query | Reuse the same `FoodEntries` date-range query shape as `watchDailyTotalsForRange` (`nutrition_repository.dart:630`) | That method already proves the correct date-window query pattern against `FoodEntries`; the adherence gate needs the same range, just counting distinct `dateIso` values instead of summing macros |

**Key insight:** Every raw ingredient this phase needs (bodyweight logs, food-logged days,
health samples) already has a working repository method or an adjacent one to copy. The actual
new work is entirely in the domain layer (the estimation math itself) — resist the urge to
re-derive data access patterns that already exist one file away.

## Common Pitfalls

### Pitfall 1: `DateTime.now()` creeping into the estimator or cadence gate
**What goes wrong:** Window/cadence code calls `DateTime.now()` directly instead of
`ref.watch(clockProvider).now()`.
**Why it happens:** The domain layer is pure Dart and doesn't naturally have a `Ref` in scope,
so it's tempting to just pass nothing and call `DateTime.now()` inside `TdeeEstimator`.
**How to avoid:** `TdeeEstimator.estimate()` takes `asOf: DateTime` as an explicit parameter
(shown in Pattern 1 above) — the *caller* (Application layer, which has `Ref`) resolves it from
`Clock` and passes it in. This is exactly how `DietPhaseCalculator.apply` and
`TargetResolver.resolve` already take `date`/`asOf`-style parameters instead of reading the
clock themselves.
**Warning signs:** Any `flutter test` for this feature that can't be made deterministic without
mocking global time is a sign `Clock` was bypassed.

### Pitfall 2: EWMA applied to raw, gappy weight logs
**What goes wrong:** A user logs weight on Monday and again the following Thursday. Applying
the EWMA update once per *log* (not once per *day*) treats a 4-day gap as a single-day jump,
producing a much larger trend swing than the data actually supports.
**Why it happens:** The naive implementation iterates the log rows directly instead of a daily
grid.
**How to avoid:** Linear-interpolate to fill missing days between consecutive logs before
running the EWMA update daily (this is what MacroFactor's public documentation describes doing
— see Sources). For days with no log at all before the first entry, don't backfill; the trend
simply starts at the first real log.
**Warning signs:** Trend line visibly jumps by more than a plausible single-day water-weight
swing (~1–2 kg) right after a multi-day gap in logging.

### Pitfall 3: "Logged day" adherence conflated with "non-zero calorie day"
**What goes wrong:** Counting a day as "food logged" only when `DailyTotals.kcal > 0`, which
would incorrectly exclude a day where the user logged something with a snapshot/recipe basis
that resolves to a very low but real kcal figure, or double-count via wear-sync quick-adds.
**Why it happens:** `DailyTotals` is the readily-available aggregate, so it's tempting to reuse
its truthiness instead of querying `FoodEntries` for row existence.
**How to avoid:** Per D-01, "food was logged that day" is presence-based, not magnitude-based —
query `FoodEntries` for `dateIso` distinctness in the window (same table `watchDailyTotalsForRange`
already queries), not `DailyTotals.kcal > 0`.
**Warning signs:** Adherence percentage disagrees with what the user can see in their own diary
history for the same window.

### Pitfall 4: Treating this as an AI feature
**What goes wrong:** A future contributor (or reviewer) assumes any "estimate with a confidence
level" must route through the Herculex AI Edge Function / per-kind quota system (`KB-05`)
established in Phase 26, because Phase 26–29 are colloquially "the AI phases."
**Why it happens:** Phase numbering proximity (26→28→27→29) and the shared vocabulary
("confidence", "estimate") invite the association.
**How to avoid:** STATE.md is explicit: "Phase 28: ... No AI dependency; feeds 23 and 29." This
phase's "confidence" is a statistically-derived label (adherence level / method reliability),
computed entirely client-side, with zero network calls and zero Gemini/Herculex-AI involvement.
Nothing in this phase should import anything from `services/ai/` or reference `GeminiBackend`/
`ai_usage_bump`.
**Warning signs:** Any import of an AI service, or any code path that fails differently when
offline vs. online (the estimator must work fully offline, same as the rest of nutrition
tracking).

### Pitfall 5: Growing `nutrition_targets_view.dart` further in-place
**What goes wrong:** Adding the D-05 badge + detail-sheet trigger directly inline in the
existing 1450+-line file, worsening an already-over-limit file (CLAUDE.md: no hand-written file
over 600 lines; 51 files already violate this).
**Why it happens:** The badge sits right next to the existing `_maintenanceKcal` field
(`nutrition_targets_view.dart:1594`), so the path of least resistance is to add a widget method
in the same file.
**How to avoid:** Per CLAUDE.md's own prescribed pattern, split into a `part`/`part of`
subfolder named after the file (`nutrition_targets_view/`) so the public import path is
unchanged. The badge widget and its state can be a `part` file; the detail sheet (likely a
`HxSheet`, per FIX-02's established pattern for sheet theming) can be its own file in the same
subfolder.
**Warning signs:** `dart run tool/check_structure.dart` flags the file, or a diff review shows
the file growing past its current line count instead of shrinking or staying flat.

### Pitfall 6: `HealthSamples` has no sync — classifier "memory" doesn't survive a reinstall
**What goes wrong:** Assuming the classifier's historical inputs persist across devices/reinstalls
the same way the new `TdeeEstimates` table will.
**Why it happens:** Both tables feed the same feature, so it's easy to assume both are synced.
**How to avoid:** `HealthSamples` (`lib/data/local/tables.dart:1122`) intentionally has **no**
`SyncColumns`/`SyncTombstone` mixin — it's local-only telemetry today, confirmed by direct read
of `tables.dart`. This is a known, pre-existing limitation, not something to fix in this phase.
A reinstalled app cold-starts the classifier again (D-08 handles this gracefully) even though
its `TdeeEstimates` *history* (which is synced) survives. Document this as expected behavior,
don't attempt to retrofit sync onto `HealthSamples` as part of this phase — out of scope.

### Pitfall 7: New migration compounding the unapplied-migration risk noted in CLAUDE.md
**What goes wrong:** CLAUDE.md flags migrations `0015`/`0016` as "written but not applied" to
the live Supabase project as of the last audit. Adding a new `20260928000000_tdee_estimates_v45.sql`
migration file is a normal, required part of this phase's 5-chore bump (writing the `.sql` file
is in scope; *deploying* it via `supabase db push`/CLI is an operational step this phase's task
list should call out explicitly but that is separate from writing the migration itself — exactly
how `20260916000000_session_segment_v44.sql` was authored without this research being able to
confirm it was deployed).
**Why it happens:** Easy to conflate "the file exists in the repo" with "the schema is live in
Postgres" — the CLAUDE.md gotcha exists precisely because that gap has bitten this project before
(PGRST204 quarantine).
**How to avoid:** The plan should have an explicit task/checkpoint for confirming the new
migration was actually applied against the live `ldzgyzigvbwofbswitrv` Supabase project (not
`jioesomepkauponjrena`) before considering the phase's sync half done — this is a verification
step, not a code-writing step.
**Warning signs:** `SyncService` quarantining `tdee_estimates` rows with `PGRST204` after ~8
attempts (the exact failure mode CLAUDE.md's schema-bump section describes).

## Code Examples

### Observed-Expenditure Formula (TDEE-01)
```dart
// Source: docs/herculex-ai-plan-2026-09-27.md §4.2 (locked formula) + MacroFactor's public
// methodology description (caleye.fit/blog/macrofactor-tdee-tracking-accuracy, MEDIUM
// confidence — describes the same back-calculation, not Herculex-specific).
// TDEE ≈ mean daily intake − (Δ smoothed bodyweight kg × 7700 kcal/kg) / days
double observedExpenditure({
  required List<double> dailyIntakeKcal, // one entry per day in window, 0 for unlogged days
  required double startTrendWeightKg,    // EWMA-smoothed weight at window start
  required double endTrendWeightKg,      // EWMA-smoothed weight at window end
  required int days,
}) {
  final meanIntake =
      dailyIntakeKcal.reduce((a, b) => a + b) / dailyIntakeKcal.length;
  final deltaKg = endTrendWeightKg - startTrendWeightKg;
  const kcalPerKg = 7700.0; // locked constant — do not substitute a different value
  return meanIntake - (deltaKg * kcalPerKg) / days;
}
```

### Bodyweight EWMA with Gap-Fill (Pitfall 2)
```dart
// Source: pattern — Hacker's Diet / Trendweight-style EWMA, alpha=0.1, MEDIUM confidence
// (multiple independent secondary sources agree on this exact constant; see Sources).
// Fills gaps by linear interpolation before the daily EWMA update so a 4-day gap between
// logs doesn't get treated as a single enormous one-day delta.
double ewmaTrend({
  required List<MapEntry<DateTime, double>> sortedLogs, // ascending by date
  double alpha = 0.1,
}) {
  if (sortedLogs.isEmpty) return double.nan;
  var trend = sortedLogs.first.value;
  for (var i = 1; i < sortedLogs.length; i++) {
    final prev = sortedLogs[i - 1];
    final curr = sortedLogs[i];
    final gapDays = curr.key.difference(prev.key).inDays;
    for (var d = 1; d <= gapDays; d++) {
      final interpolated =
          prev.value + (curr.value - prev.value) * (d / gapDays);
      trend = trend + alpha * (interpolated - trend);
    }
  }
  return trend;
}
```

### Material-Shift Threshold (TDEE-05, D-09 — already locked, shown for completeness)
```dart
// Source: 28-CONTEXT.md D-09 (locked decision, restated as code)
bool isMaterialShift({required int currentBaselineKcal, required int newEstimateKcal}) {
  final delta = (newEstimateKcal - currentBaselineKcal).abs();
  final pctFloor = (currentBaselineKcal * 0.05).round();
  final threshold = pctFloor > 100 ? pctFloor : 100;
  return delta > threshold;
}
```

### New Table — Post-Hoc Synced Table Migration Pattern (verified against a real prior phase)
```sql
-- Source: supabase/migrations/0014_joint_pain_logs.sql (VERIFIED by direct read — the exact
-- pattern this project already uses for "a single new synced table added after the fact",
-- distinct from the addColumn-only pattern used by 20260916000000_session_segment_v44.sql).
create table tdee_estimates (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  method text not null,          -- 'observed' | 'classifier' | 'coldStart'
  confidence text not null,      -- 'high' | 'medium' | 'low'
  window_days integer not null,
  kcal integer not null,
  inputs_json text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table tdee_estimates enable row level security;

create policy tdee_estimates_select_own
  on tdee_estimates for select using (user_id = auth.uid());
create policy tdee_estimates_insert_own
  on tdee_estimates for insert with check (user_id = auth.uid());
create policy tdee_estimates_update_own
  on tdee_estimates for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy tdee_estimates_delete_own
  on tdee_estimates for delete using (user_id = auth.uid());

create trigger t_set_updated_at_tdee_estimates
  before insert or update on tdee_estimates
  for each row execute function set_updated_at();

create trigger t_record_tombstone_tdee_estimates
  after delete on tdee_estimates
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.tdee_estimates;
```

### Matching Drift Table (onCreate half of the 5-chore bump)
```dart
// Source: pattern — lib/data/local/tables.dart's existing NutritionTargets (SyncColumns +
// SyncTombstone shape) and the "new table" branch style already used at
// database.dart:134-145 (`if (from < N) { await m.createTable(...) }`).
@DataClassName('TdeeEstimateData')
class TdeeEstimates extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  TextColumn get method => text()();       // 'observed' | 'classifier' | 'coldStart'
  TextColumn get confidence => text()();   // 'high' | 'medium' | 'low'
  IntColumn get windowDays => integer()();
  IntColumn get kcal => integer()();
  TextColumn get inputsJson => text()();
}

// database.dart: schemaVersion => 45;
// onUpgrade: if (from < 45) { await m.createTable(tdeeEstimates); }
```

## Open Questions Resolved

> These directly answer the 8 items CONTEXT.md flagged as "Claude's Discretion" / research's job.

### 1. Calibration window length and re-calibration cadence (TDEE-03)
**Recommendation:** Minimum window 14 days, preferred/default 21–28 days, hard cap 35 days.
Self-selection rule: at recalibration time, evaluate the *widest* window up to the cap for which
the D-02 70% food-logging adherence bar is met; if even the 14-day minimum fails, adherence has
failed outright and the classifier fallback applies. This means data-rich users naturally settle
into a steadier ~28-day estimate while adherence-marginal users get the shortest window that
still qualifies, rather than being pushed to fail entirely.
Cadence: evaluate the "is it time to recalibrate" gate opportunistically on nutrition-screen
load / app foreground (no background scheduler exists in this project — confirmed by
`pubspec.yaml` absence of `workmanager`/`android_alarm_manager`, and by the design doc's own
Phase 29 rationale for the same constraint). Recompute-and-persist only when **any** of:
elapsed ≥ 7 days since the last estimate, a material bodyweight-trend shift (reuse the same
"bigger of ±100kcal/±5%" idea applied to the raw expenditure delta, or simpler: trend weight
moved ≥1 kg since last estimate), or average daily steps shifted ≥25% since last estimate.
**Confidence:** MEDIUM — 14–28 day windows and weekly cadence are directly corroborated by
public descriptions of comparable tools (see Sources); the exact trigger thresholds for
bodyweight/activity-pattern shift are ASSUMED (tunable constants, not externally verified).

### 2. Bodyweight-log count for the D-01 adherence gate
**Recommendation:** At least 2 distinct bodyweight logs per week of window length, floor 4 (so:
14-day window needs ≥4 logs, 21-day needs ≥6, 28-day needs ≥8), **and** at least one log in each
half of the window (prevents a cluster of 5 same-week logs from producing a meaningless
single-point "trend"). This is intentionally a lower bar than the 70% *daily* food-logging
requirement (D-02) — real-world weigh-in habits are typically less frequent than food logging,
and the EWMA smoothing (see #5) tolerates gaps by design.
**Confidence:** LOW/ASSUMED — no external source specifies this exact count; it's a defensible
design choice consistent with the "two independent gates" shape D-01 already locked. Flag for
planner/user confirmation.

### 3. Hysteresis/dwell mechanism (D-03)
**Recommendation:** Apply hysteresis only to the **classifier → observed** promotion direction:
require adherence to pass on **2 consecutive weekly recalibration checks** before actually
switching `baselineTdeeProvider`'s active method from classifier to observed. The **observed →
classifier** demotion direction does not need a separate hysteresis counter — D-04's grace
period (below) already serves as that direction's dwell mechanism, and stacking both would make
the app unresponsive to a genuine, sustained logging lapse.
**Confidence:** LOW/ASSUMED — "2 consecutive" is a reasonable, simple choice (asymmetric: cheap
to verify, prevents single-week flapping) but not externally sourced. Implement as a named
constant (`const hysteresisCycles = 2`) so it's trivially tunable later.

### 4. Grace period length (D-04)
**Recommendation:** 7 days, matching the weekly recalibration cadence from #1 — i.e., exactly
one missed recalibration cycle is tolerated holding the stale observed estimate before falling
back to the classifier on the *next* cycle. This keeps the grace period conceptually simple
("one cycle of grace") rather than an independent constant to separately tune.
**Confidence:** LOW/ASSUMED.

### 5. Weight-trend smoothing method
**Recommendation:** EWMA with **alpha = 0.1**, applied to a linearly-interpolated daily grid
(fills gaps between logs before each daily update — see Pitfall 2 and the code example above).
This is the same constant used by the well-established Hacker's Diet / Trendweight / Libra-app
lineage of weight-trend tools.
**Confidence:** MEDIUM — alpha=0.1 is corroborated by multiple independent secondary sources
describing the same established technique (see Sources); its specific fit for *this* app's
population/use-case is not independently verified, but it's a sound, widely-used default rather
than an invented number.

### 6. Activity-classifier output shape
**Recommendation:** The classifier computes a **continuous multiplier** directly (e.g.
1.15–1.90 range, clamped), *not* funneled through the 4-value `ActivityLevel` enum — mapping to
only 4 discrete buckets would reintroduce the same ±15% coarse-error problem this phase exists
to eliminate (per the design doc's own stated rationale for building this feature at all).
This requires a small, additive refactor to `macro_targets.dart`: extract the
"BMR × multiplier" step so it accepts an explicit `double multiplier` parameter directly, with
`fromProfile`'s existing enum-based lookup becoming just one caller of that extracted step (used
for the D-08 cold-start seed and any manual-reset-with-no-classifier-data-yet case). The
classifier's inputs → multiplier mapping should be a simple weighted/interpolated model over
`HealthSamples` (steps as primary signal — interpolate between known anchor points matching the
existing enum's own values, e.g. 3000 steps→1.20, 7500→1.375, 10000→1.55, 15000+→1.725, then
extrapolate/clamp beyond) plus a small additive adjustment for logged-training frequency (TEA
not otherwise captured by steps), with `sleep_hours`/`resting_hr` as secondary
confidence-affecting signals rather than direct multiplier inputs. Classifier-derived estimates
should never claim "high" confidence — by construction they're the *lower-confidence fallback*,
which the D-05 badge already reflects (see the CONTEXT.md badge-copy example: "Classified ·
Medium confidence").
**Confidence:** The *shape* recommendation (continuous, not enum-bucketed) is MEDIUM confidence
(directly follows from the design doc's own stated problem). The specific anchor-point
coefficients are LOW/ASSUMED — genuinely a tuning problem with no authoritative source; flag
explicitly for post-ship calibration against real usage, not a one-shot "correct" answer.

### 7. `TdeeEstimates` schema
See the Code Examples section above for the concrete column list. Key choices:
- **No `isCurrent`/`isActive` boolean.** Query `ORDER BY date_iso DESC LIMIT 1` for "the current
  estimate," mirroring the existing `latestBodyweightKg()` pattern in
  `measurements_repository.dart` — avoids an extra invariant ("exactly one row has
  `isCurrent=true`") that would need its own maintenance code.
- **`inputsJson` as a single TEXT column**, not normalized sub-columns — the inputs shown in the
  D-06 detail sheet differ by method (observed: mean intake, Δweight, window; classifier: avg
  steps, sleep, workouts/week), so a flexible JSON blob avoids a wide, mostly-null column set.
  Matches the house pattern already used for `wearSyncControllerProvider`'s JSON payloads.
- **Synced** (`SyncColumns` + `SyncTombstone`), confirmed correct per CONTEXT.md's "very likely
  synced" note — Phase 29's weekly-report diffing needs this history to survive a reinstall, and
  it is genuinely small/append-mostly data, unlike `HealthSamples`' local-only telemetry volume.
- **Migration pattern:** follow `0014_joint_pain_logs.sql` exactly (a single new post-hoc
  synced table), not the addColumn pattern from `20260916000000_session_segment_v44.sql` — this
  is a brand-new table, not new columns on an existing one.
- **Indexing:** a plain index on `date_iso` is sufficient for the range queries Phase 29's
  diffing will need; no composite index required at this phase's data volume (at most one row
  per ~week per user).
**Confidence:** MEDIUM — directly derived from two real, existing migrations in this exact
codebase (VERIFIED by direct read), not external convention.

### 8. PHYS-04 ordering / integration point
**Confirmed: Phase 28 does not need to implement any safety gate itself.** The observed-
expenditure and classifier paths both compute a **maintenance** estimate only — they feed
`baselineTargetsProvider`, which is strictly upstream of `DietPhaseCalculator.apply
(baselineKcal:)`, the component that actually applies a deficit/surplus. Phase 28 never touches
deficit/surplus magnitude, so it cannot itself become "a path that skips" a future aggressive-
deficit gate — that gate, whenever Phase 23 ships it, necessarily belongs at or after
`DietPhaseCalculator.apply` (or at the target-save flow in `nutrition_targets_view.dart`, which
already writes the final `NutritionTargetData` row), not at the baseline-estimation layer this
phase owns. **No integration point needs to be left open in this phase's code** — the existing
`baselineKcal: int` parameter shape of `DietPhaseCalculator.apply` is already the natural
future hook, and it requires no advance modification. Recommend the plan add a one-line code
comment at that call site noting this for the benefit of whoever implements PHYS-04, but no
functional change.
**Confidence:** HIGH — directly follows from the VERIFIED, already-read `diet_phase.dart` and
`nutrition_providers.dart` call chain; not a projection.

## Runtime State Inventory

> Not applicable — this is a greenfield addition (new table, new domain logic), not a
> rename/refactor/migration phase. No existing runtime state carries a string or identity that
> this phase changes.

## Environment Availability

> Skip — no new external dependencies. `drift`, `flutter_riverpod`, `health`, and Supabase are
> already present and already used by the exact tables this phase reads.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Hand-picked `ActivityLevel` multiplier (1.2/1.375/1.55/1.725), chosen once at onboarding and almost never revisited | Hybrid: observed-expenditure (primary) when adherence qualifies, HealthSamples-derived classifier (fallback) otherwise, self-recalibrating | This phase (Phase 28, 2026-09) | Design doc states the current hand-picked approach carries "typically ±15%" error and never reacts to a lifestyle change (e.g. someone starting to walk 12,000 steps/day) — [CITED: docs/herculex-ai-plan-2026-09-27.md §4.1, internal project doc, not independently re-verified against a clinical source this session] |

**Deprecated/outdated:** None — `MacroTargets.fromProfile`'s enum-based multiplier lookup is
not being removed, only becoming a fallback path (used for D-08 cold start and D-12–D-15 manual
reseed) rather than the sole source of truth.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Window bounds: min 14 / default 21–28 / cap 35 days | Open Questions Resolved #1 | Too narrow a cap → estimate never stabilizes for very consistent loggers; too wide → recalibration reacts too slowly to a real lifestyle change. Easy to retune (named constant), low blast radius. |
| A2 | Recalibration triggers: 7-day elapsed, ≥1kg trend shift, ≥25% steps shift | Open Questions Resolved #1 | Wrong thresholds cause either too-frequent badge changes (user distrust) or missed real shifts (stale estimate lingers). Tunable constants, not structural. |
| A3 | Bodyweight-log count: 2/week floor 4, spread across window halves | Open Questions Resolved #2 | Too strict → users who weigh in reasonably (2-3x/week) get stuck on the classifier despite good food-logging adherence, defeating the primary method's purpose. Too loose → a meaningless 2-point "trend" from same-week logs. |
| A4 | Hysteresis: 2 consecutive qualifying cycles for classifier→observed promotion only | Open Questions Resolved #3 | Too few cycles → flapping (D-03's explicit concern); too many → slow to reward genuinely-improved logging. Directly testable in isolation once implemented. |
| A5 | Grace period: 7 days (one recalibration cycle) | Open Questions Resolved #4 | Too short → stale-estimate value shown for a trivial reason defeats D-04's purpose; too long → a genuinely-lapsed user sees an increasingly wrong "stale" number for too long. |
| A6 | EWMA alpha = 0.1 | Open Questions Resolved #5 | MEDIUM confidence (externally corroborated constant) — main risk is this app's logging cadence/population differing enough from the sources' assumed daily-weigh-in habit that 0.1 over/under-smooths; worth validating against real user data post-ship. |
| A7 | Classifier: continuous multiplier via step-anchor interpolation + training-frequency adjustment | Open Questions Resolved #6 | The exact coefficients are a genuine tuning problem with no ground truth available at research time — likely needs revision after observing real classifier-vs-observed agreement once both paths are live for the same users. |
| A8 | `TdeeEstimates` schema (columns, no isCurrent flag, synced, indexed on date_iso) | Open Questions Resolved #7 | Low risk — directly modeled on two real existing migrations in this codebase; the main risk is Phase 29 needing a column this research didn't anticipate (e.g. an explicit `isColdStart` flag distinct from `method='coldStart'`), which would be an additive follow-up migration, not a breaking change. |
| A9 | New domain/data files land under `lib/features/nutrition/` (not a new `features/tdee/`) | Architecture Patterns → Recommended Project Structure | If the estimator later grows enough to also serve, e.g., a future non-nutrition consumer, a `features/nutrition/` home could feel mislocated — low risk given TDEE-04/05's explicit nutrition-target framing and the single integration point being inside `nutrition_providers.dart` already. |

**If this table is empty:** N/A — see entries above.

## Open Questions

1. **Exact classifier coefficients (A7).** No amount of research produces a "correct" answer
   here without real usage data — recommend the plan implement the interpolation model as
   described, ship it, and treat post-launch calibration (comparing classifier output against
   observed-expenditure output for the same user once they cross the adherence bar) as expected
   follow-up work, not a gap in this phase.
2. **Whether `MacroTargets.fromProfile`'s refactor (Open Questions Resolved #6) should also
   change its public signature**, or whether a new sibling function (e.g.
   `MacroTargets.fromMultiplier(profile, multiplier)`) is cleaner than modifying `fromProfile`
   itself. Both are viable; the planner should pick one and keep `fromProfile`'s existing
   callers (there may be others beyond `nutrition_targets_view.dart` — worth a repo-wide grep
   for `MacroTargets.fromProfile` during planning) unbroken either way.
3. **Whether the D-06 detail sheet needs live re-query of current `HealthSamples` averages, or
   only the frozen `inputsJson` snapshot from the last recalibration.** This research recommends
   the frozen snapshot (matches "every estimate exposes... inputs" — TDEE-04 — as a property of
   the *estimate*, not a live dashboard), but the planner should confirm this reading matches
   D-06's intent literally ("shown individually in the detail sheet" doesn't specify live vs.
   snapshotted).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (bundled with Flutter SDK) + `package:test` conventions, per existing suite |
| Config file | none — no `dart_test.yaml` in repo; standard `flutter test` discovery |
| Quick run command | `flutter test test/tdee_estimator_test.dart` (new file, does not exist yet) |
| Full suite command | `flutter test` (CLAUDE.md: ~2min, 1308 pass / 4 skipped baseline — redirect to a file, don't pipe through `tail`, per CLAUDE.md's own warning about losing the real exit code) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TDEE-01 | Observed-expenditure formula + D-02 adherence gate produce correct kcal given synthetic intake/weight series | unit | `flutter test test/tdee_estimator_test.dart` | ❌ Wave 0 |
| TDEE-01 | EWMA gap-fill smoothing matches expected trend for a sparse-log fixture | unit | `flutter test test/tdee_estimator_test.dart` | ❌ Wave 0 (same file) |
| TDEE-02 | Classifier produces a plausible multiplier from a synthetic `HealthSamples` fixture; falls back correctly when adherence fails | unit | `flutter test test/activity_classifier_test.dart` | ❌ Wave 0 |
| TDEE-03 | Window self-selection picks correct window for varying data density; cadence gate fires only on trigger conditions | unit | `flutter test test/tdee_estimator_test.dart` | ❌ Wave 0 (same file) |
| TDEE-04 | `TargetResolver` still returns the manual `TargetRule` over any `baselineTargetsProvider` value (regression-proves the "never overrides manual" guarantee this phase relies on but doesn't itself implement) | unit | `flutter test test/target_resolver_test.dart` | ❌ Wave 0 — **this file doesn't exist today even though `target_resolver.dart` itself predates this phase**; confirmed absent by direct search |
| TDEE-04 | Badge shows correct method/confidence copy for each state (observed/classifier/coldStart/stale) | widget | `flutter test test/nutrition_targets_view_test.dart` (extend or create) | Check during planning — existing widget test coverage for this view unconfirmed this session |
| TDEE-05 | `isMaterialShift` threshold matches D-09's "bigger of ±100/±5%" rule at boundary values | unit | `flutter test test/tdee_estimator_test.dart` | ❌ Wave 0 (same file) |
| — | drift v45 migration replay (createTable) | integration | `flutter test test/migration_test.dart` | Retarget existing file, per CLAUDE.md's 5-chore checklist — file exists, needs a new `migrateAndValidate(db, 45)` case |

### Sampling Rate
- **Per task commit:** `flutter test test/tdee_estimator_test.dart test/activity_classifier_test.dart test/target_resolver_test.dart` (whichever files the task touched)
- **Per wave merge:** `flutter test` (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`, plus `flutter analyze` at 0 errors (CLAUDE.md: exits 1 on warnings too — check the error count, not just exit code)

### Wave 0 Gaps
- [ ] `test/tdee_estimator_test.dart` — covers TDEE-01, TDEE-03, TDEE-05
- [ ] `test/activity_classifier_test.dart` — covers TDEE-02
- [ ] `test/target_resolver_test.dart` — covers TDEE-04's precondition (pre-existing file gap,
      not introduced by this phase, but load-bearing for TDEE-04 and currently untested)
- [ ] `test/migration_test.dart` — retarget to v45 with a new replay case (existing file, minor
      addition per the established v44 pattern already in the file)
- [ ] Framework install: none — `flutter_test` already present, no new test dependency needed

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Not touched by this phase — reuses existing Supabase auth session |
| V3 Session Management | No | Not touched |
| V4 Access Control | Yes | Owner-only RLS on `tdee_estimates` via `user_id = auth.uid()`, identical pattern to `joint_pain_logs`/every other per-user synced table (VERIFIED against `0014_joint_pain_logs.sql`) |
| V5 Input Validation | Yes | `method`/`confidence` are closed-vocabulary TEXT columns — validate against the Dart enum at the repository boundary before insert, same as `appliesTo` is validated in `TargetResolver`'s scope-matching logic |
| V6 Cryptography | No | No new secrets/crypto — health/bodyweight data already flows through the existing sync pipeline with no new encryption requirement introduced by this phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Cross-user data leakage via missing RLS policy on the new table | Information Disclosure | Owner-only RLS policies on all four operations (select/insert/update/delete), enabled via `enable row level security`, per the verified `0014_joint_pain_logs.sql` template above — do not ship the table without this |
| Free-text `inputsJson` column used to smuggle unexpected structure | Tampering | Treat `inputsJson` as display-only, never `eval`'d or used to drive control flow on read — the domain layer computes `TdeeEstimateResult` first, and `inputsJson` is a serialization of *that already-validated* result, not a pass-through of raw external input |
| Health-adjacent data (`steps`/`sleep_hours`/`resting_hr`) treated with the same casualness as workout data | Information Disclosure | Design doc explicitly distinguishes physique photos (GDPR Art. 9 special category) from general health telemetry; `HealthSamples` is not Art. 9 data and this phase introduces no new photo/biometric-identifier handling — no elevated compliance review needed beyond the standard owner-only RLS already required above |

## Sources

### Primary (HIGH confidence — direct codebase reads, VERIFIED this session)
- `lib/features/nutrition/domain/macro_targets.dart` — current formula, confirmed line-by-line
- `lib/features/nutrition/application/nutrition_providers.dart` — `baselineTargetsProvider` and
  `effectiveTargetsProvider`, confirmed as the single integration point
- `lib/features/nutrition/domain/target_resolver.dart` — confirmed manual-target-wins behavior
- `lib/features/health/domain/activity_adjuster.dart` — confirmed NOT a TDEE multiplier (volume
  factor only), pattern-reference only
- `lib/data/local/tables.dart` — confirmed `HealthSamples` has no `SyncColumns`, confirmed
  `NutritionTargets`/other tables' `SyncColumns`/`SyncTombstone` shape
- `lib/data/local/database.dart` — confirmed `schemaVersion => 44`, confirmed `addIfMissing`
  guard pattern and the `if (from < N) createTable(...)` pattern for brand-new tables
- `supabase/migrations/0014_joint_pain_logs.sql` — confirmed as the exact template for a
  post-hoc new synced table (RLS policies, triggers, realtime publication)
- `supabase/migrations/20260916000000_session_segment_v44.sql` — confirmed current migration
  filename convention (timestamp-prefixed, `_vNN` suffix)
- `test/migration_test.dart` — confirmed `migrateAndValidate(db, 44)` pattern, confirmed no
  `target_resolver_test.dart`/`macro_targets_test.dart` exist in `test/`
- `pubspec.yaml` — confirmed no `workmanager`/`android_alarm_manager` dependency

### Secondary (MEDIUM confidence — WebSearch, cross-verified across multiple independent sources)
- [MacroFactor's Adaptive TDEE: How Accurate Is It Really?](https://caleye.fit/blog/macrofactor-tdee-tracking-accuracy/) — describes the identical `expenditure = mean_intake − Δstored_energy/days` back-calculation, EWMA-smoothed weight trend, and 14-day-minimum/28-day-preferred rolling window
- [MacroFactor weight trend documentation](https://help.macrofactorapp.com/en/articles/21-weight-trend) — EWMA description, linear interpolation for gap-fill
- [How to Track Your Weight Loss With EWMA Formula — Shortform](https://www.shortform.com/blog/ewma-formula/) — confirms Hacker's Diet alpha=0.1 constant
- [One man's look at The Hacker's Diet — Wikiversity](https://en.wikiversity.org/wiki/One_man's_look_at_The_Hacker's_Diet) — corroborates alpha=0.1 as the canonical smoothing constant for this technique

### Tertiary (LOW confidence — single-source or not independently cross-verified)
- Specific classifier multiplier anchor-point coefficients (Open Questions Resolved #6) —
  authored this session by interpolating against the existing `ActivityLevel` enum's own
  multiplier values; not sourced from any external reference
- Exact hysteresis-cycle-count and grace-period-day values (Open Questions Resolved #3, #4) —
  reasoned defaults consistent with the locked D-02/D-09 percentages, not independently verified

## Metadata

**Confidence breakdown:**
- Standard stack / codebase integration points: HIGH — every claim about existing files, line
  numbers, and current behavior was verified by direct `Read`/`Grep` this session, not recalled
  from training data
- Formula and general methodology (observed-expenditure, EWMA smoothing, rolling window):
  MEDIUM-HIGH — corroborated by multiple independent external sources describing the same
  established technique
- Specific tunable constants (window bounds, hysteresis depth, grace period, classifier
  coefficients): LOW — reasoned recommendations, explicitly flagged in the Assumptions Log for
  planner/user confirmation and post-launch tuning, not externally mandated values

**Research date:** 2026-09-28
**Valid until:** No external package versions are pinned by this research (none installed), so
staleness risk is limited to the tunable-constants recommendations above, which are expected to
be revisited after real usage regardless of elapsed time — not a calendar-based expiry.
