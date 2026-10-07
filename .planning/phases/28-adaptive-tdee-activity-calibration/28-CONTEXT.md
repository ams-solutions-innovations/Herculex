# Phase 28: Adaptive TDEE & Activity Calibration - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the hand-picked `ActivityLevel` multiplier in `MacroTargets.fromProfile` with an
adaptive TDEE estimator that becomes the sole value returned by `baselineTargetsProvider`
(`nutrition/application/nutrition_providers.dart:69`), which already flows straight into
`DietPhaseCalculator.apply(baselineKcal:)` — this is the **only** integration point; phase
math, pace presets, and macro splits are untouched.

Two methods, hybrid, already locked by the 2026-09-27 planning session:
- **Primary — observed expenditure:** `TDEE ≈ mean daily intake − (Δ bodyweight kg × 7700
  kcal/kg over the window) / days`, computed from data the app already holds (food diary +
  bodyweight logs). Used when logging adherence passes the threshold decided below.
- **Fallback — activity classification:** derives the same kind of multiplier
  (sedentary/lightly-active/active/very-active-equivalent) from the `HealthSamples` table
  (`steps`, `sleep_hours`, `active_kcal`, `resting_hr`) plus logged training, instead of the
  user hand-picking it. Feeds the existing Mifflin-St Jeor formula in place of the current
  manual `ActivityLevel` selection.

The app self-selects calibration window and re-calibration cadence (TDEE-03) — never asks the
user to pick a measurement duration. Recalibration triggers (already fixed in the design doc):
elapsed interval since last estimate, a material bodyweight-trend shift, or a noticeable
activity-pattern change.

Requirements: TDEE-01–05.

</domain>

<decisions>
## Implementation Decisions

### Adherence threshold (gates observed-expenditure vs. activity-classifier)
- **D-01:** A "logged day" for the food-diary side of adherence means food was logged that
  day. Bodyweight adherence is checked separately: enough distinct bodyweight logs somewhere
  in the same window, not required to be the same days as food logs. Two independent gates,
  not one combined daily requirement.
- **D-02:** The bar is **~70% of window days** with food logged (e.g. 10 of the last 14) to
  qualify for observed-expenditure mode. Exact bodyweight-log count within the window and the
  precise window length itself are research/planning's job (TDEE-03 already says the app
  picks the window from data density — this discussion fixes the *percentage* bar, not the
  window size).
- **D-03:** Method switching requires **sustained crossing**, not an immediate flip on a
  single recalibration where adherence happens to sit right at the line — prevents the
  baseline flapping day-to-day for a borderline logger. Exact dwell/hysteresis mechanism is
  planning's job, consistent with the three recalibration triggers already fixed in the design
  doc.
- **D-04:** When a user was on observed-expenditure and then stops logging, the app holds the
  **last observed estimate** (clearly labelled as aging/stale) for a grace period before
  falling back to the activity classifier — avoids the number jumping the moment someone
  misses a few days. Exact grace-period length is planning's job.

### Estimate visibility (TDEE-04: method, confidence, window, inputs — always visible)
- **D-05:** An inline badge next to "Maintenance calories" in
  `nutrition_targets_view.dart` (e.g. "Measured · High confidence" or "Classified · Medium
  confidence") that expands via tap into a detail sheet with method, window, confidence, and
  the inputs used. Not an always-expanded card (that screen is already 1450+ lines and over
  the 600-line house limit), not a separate hidden screen (discoverability matters).
- **D-06:** When the classifier is active, its underlying `HealthSamples` inputs (e.g. "avg
  9,200 steps/day, 3 logged workouts/week") are shown individually in the detail sheet, not
  collapsed into a bare confidence label — lets the user sanity-check a derived number instead
  of trusting a black box.
- **D-07:** The detail sheet shows the live estimate **and** the user's currently-saved manual
  target side by side when one exists (e.g. "Your target: 2,400 kcal (set manually) · Current
  estimate: 2,290 kcal") — makes the gap visible without touching the saved target, and this
  same comparison is what the weekly-report material-shift prompt (D-08/D-09) will surface
  later.
- **D-08 (cold start):** Before enough data exists (brand-new user), the badge reads a
  "Calibrating" state (e.g. "Calibrating — using onboarding estimate") and the number shown is
  Mifflin-St Jeor × the onboarding `ActivityLevel` pick, used purely as a seed. Never blank,
  never an error state.

### Material-shift handling (TDEE-05: surfaced in weekly report, never silent)
- **D-09:** A shift counts as "material" when it exceeds **whichever is bigger: ±100 kcal or
  ±5% of the current baseline** — a floor-plus-percentage rule so small absolute swings still
  register for lighter/smaller-TDEE users and proportionally larger swings are required before
  flagging bigger-TDEE users.
- **D-10:** When surfaced in the (future, Phase 29) weekly report, it's an **explicit
  accept/dismiss prompt** — "Update my target to X" / "Keep current target" — not passive
  information. The user stays in control; nothing is silently rewritten (TDEE-05's core
  requirement), but the moment is actionable.
- **D-11 (Phase 28 ↔ Phase 29 handoff):** Phase 28 is responsible for persisting **TDEE
  estimate history only** — a table of estimates over time (method, confidence, window, kcal,
  timestamp) via its own 5-chore schema bump. It does **not** additionally emit a distinct
  "material shift detected" event/record. Phase 29 (not yet built) computes "was there a
  material shift this week" itself by diffing that history using the D-09 threshold. This
  keeps Phase 28 from designing a queue/event shape blind, for a screen that doesn't exist
  yet — Phase 29's own discussion can revisit the exact event shape if diffing proves
  insufficient.

### Onboarding activity picker
- **D-12:** The onboarding `ActivityLevel` question is **kept**, but reframed in copy as a
  starting estimate rather than a permanent setting (e.g. "How active are you right now?
  We'll refine this automatically as you log.") — sets correct expectations without removing
  the question or its UI.
- **D-13:** After a user has calibrated (past the "Calibrating" cold-start state), the
  `ActivityLevel` picker **stays visible and editable in Profile**, relabeled as a manual
  reset/nudge (useful when e.g. someone's job or lifestyle changes drastically and they don't
  want to wait out a full recalibration cycle).
- **D-14:** A manual reset from Profile **reseeds only** — it becomes the new seed value for
  the next classifier recalibration but does **not** discard prior TDEE estimate history
  (D-11's table stays continuous, so the weekly report's drift math isn't interrupted).
- **D-15:** A manual reset does **not** force the method back to "Calibrating"/classifier-seeded
  if the user currently qualifies for observed-expenditure mode under D-01–D-04 — resetting
  activity level is irrelevant to someone whose baseline comes from measured energy balance,
  until/unless they ever fall back to the classifier.

### Claude's Discretion
- Exact calibration window length and re-calibration cadence mechanics (TDEE-03 already says
  the app picks these from data density; this discussion fixed the adherence *percentage* bar
  (D-02) and switching behavior (D-03/D-04), not the window/cadence numbers themselves).
- Exact bodyweight-log count required within the window for the "enough weight logs" gate in
  D-01.
- Exact hysteresis/dwell mechanism for D-03 (how many consecutive qualifying recalibrations
  before the method actually switches).
- Exact grace-period length in D-04.
- Weight-trend smoothing method (design doc explicitly calls for smoothing over raw two-point
  deltas — daily water-weight noise exceeds weekly fat-loss signal — but doesn't specify EWMA
  vs. moving average vs. another technique).
- Exact activity-classifier output shape (whether it maps to the existing 4-tier `ActivityLevel`
  enum values or a continuous multiplier) — `ActivityBasedAdjuster`
  (`health/domain/activity_adjuster.dart`) is a pattern reference for shape only; it computes a
  training-volume factor, not a TDEE multiplier, and is not directly reusable.
- Exact TDEE-estimate-history table schema for D-11 (columns beyond method/confidence/
  window/kcal/timestamp, indexing, etc.) — standard 5-chore schema-bump territory.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase design & locked architecture
- `docs/herculex-ai-plan-2026-09-27.md` §4 ("Faza 28 — Adaptivni TDEE", written in Slovenian) —
  full design rationale: why the hand-picked multiplier is wrong (~±15% error), the observed-
  expenditure formula, the `HealthSamples`-based classifier fallback, the three recalibration
  triggers, the single integration point at `baselineTargetsProvider`, and the "manually
  entered Maintenance calories stays superior" rule this discussion's D-05–D-11 builds on.
- `.planning/ROADMAP.md` (Phase 28 section, "Success" paragraph) — the five success criteria
  this phase must satisfy, one per requirement.
- `.planning/REQUIREMENTS.md` §14 (TDEE-01–05) — the five locked requirements.
- `.planning/STATE.md` "Session update — 2026-09-27 (Scope amendment)" — decision #2 of 4:
  "Adaptive TDEE is hybrid. Observed energy balance... is primary... activity classification...
  is the fallback" — the hybrid split this phase implements was already decided at the
  milestone level, not re-litigated here.

### House rules that apply
- `CLAUDE.md` "Schema changes are five chores, not one" — the new TDEE-estimate-history table
  (D-11) is a full 5-chore bump: schemaVersion + onUpgrade, drift schema dump/generate, migration
  test retargeting, and a matching `supabase/migrations/NNNN_*.sql` (this table is very likely
  synced — check against `SyncColumns`/outbox pattern during planning).
- `CLAUDE.md` "No hand-written file over 600 lines" — `nutrition_targets_view.dart` is already
  1450+ lines; the D-05 badge/detail-sheet addition should land in a `part`/`part of` subfolder
  rather than growing the file further in place.
- `.planning/phases/06-label-ocr-and-photo-assist/06-AI-SPEC.md` — house rule cited by every AI
  phase ("deterministic primary, AI bounded, AI never writes to the database, user confirms").
  Not directly triggered here (this phase has no AI dependency per STATE.md), but the "user
  confirms" half is exactly what D-10's accept/dismiss prompt implements for a non-AI estimate.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/features/nutrition/domain/target_resolver.dart` (`TargetResolver`/`TargetRule`) — already
  implements "most-specific matching rule wins, else fall back to baseline" resolution. A saved
  `NutritionTargetData` row (via `nutritionTargetsProvider`) is resolved *before*
  `baselineTargetsProvider` in `effectiveTargetsProvider` — this is the existing mechanism that
  already makes TDEE-04's "never overrides a manually-set value" true by construction: the
  adaptive estimator only changes what `baselineTargetsProvider` returns, and any saved target
  rule already wins over it unconditionally. No new "is this manual" flag needs inventing.
- `lib/features/measurements/data/measurements_repository.dart` (`latestBodyweightKg`,
  `logMeasurement`) — existing bodyweight log storage (`metric == 'bodyweight'` in the
  measurements table) is the direct data source for the D-01 bodyweight-adherence gate and the
  observed-expenditure formula's Δweight term.
- `lib/data/local/tables.dart:1122` `HealthSamples` table — already exists, already populated by
  `HealthService` (`kind`: `steps` | `sleep_hours` | `active_kcal` | `resting_hr`, one row per
  metric per day). This is the direct data source for the D-06 classifier inputs. Note: this
  table has **no** `SyncColumns`/`SyncTombstone` mixin — it's local-only telemetry today; the new
  TDEE-estimate-history table (D-11) is a separate table and can be synced independently.
- `lib/features/health/domain/activity_adjuster.dart` (`ActivityBasedAdjuster`) — closest
  existing pattern for "derive something from HealthSamples", but it returns a training-volume
  factor, not a TDEE multiplier — a shape reference only, per Claude's Discretion above.

### Established Patterns
- `lib/features/nutrition/domain/macro_targets.dart` `MacroTargets.fromProfile` — the exact
  Mifflin-St Jeor + activity-multiplier + goal-adjustment formula the classifier fallback must
  keep feeding (same formula, only the multiplier's source changes from hand-picked to derived).
- `lib/features/nutrition/domain/diet_phase.dart` `DietPhaseCalculator.apply(baselineKcal:)` —
  consumes whatever `baselineTargetsProvider` returns; untouched by this phase per the design
  doc, confirmed by code (`baselineKcal` is just a plain `int` parameter).
- `lib/features/nutrition/presentation/views/nutrition_targets_view.dart` (`_maintenanceKcal`
  `TextEditingController`, ~line 1368) — the "Maintenance calories" field the D-05 badge sits
  next to; pre-filled from `baseline` today, will be pre-filled from the adaptive estimate.
  Saving this field (via the phase-apply flow) is what creates the manually-set `TargetRule`
  that `target_resolver.dart` already treats as authoritative.

### Integration Points
- `lib/features/nutrition/application/nutrition_providers.dart:69` `baselineTargetsProvider` —
  the single point where this phase's output plugs in, per the design doc's explicit "exactly
  one point" statement. Currently `Provider<MacroTargets?>` reading `profileProvider`; becomes a
  provider that also reads the new TDEE-estimate state.
- `lib/features/profile/domain/profile.dart` `ActivityLevel` enum (4 values) — stays as the
  onboarding/reset seed value type (D-12–D-15); the classifier's output should be expressible in
  compatible terms even if internally continuous (see Claude's Discretion).

</code_context>

<specifics>
## Specific Ideas

No specific visual mockups or exact copy were dictated beyond the wording directions captured
in D-05, D-08, and D-12 (badge text examples, "Calibrating" framing, onboarding copy direction)
— those are illustrative starting points for planning/research, not final strings.

</specifics>

<deferred>
## Deferred Ideas

- The exact weekly-report UI/screen that renders the D-10 accept/dismiss prompt — that's Phase
  29's job entirely; this phase only needs to persist the estimate history Phase 29 will diff
  (D-11).
- PHYS-04 (underage users / low-confidence visual assessments barred from aggressive
  deficits/surpluses) — noted in the design doc as applying to adaptive TDEE too ("Adaptivni
  TDEE ne sme postati pot mimo varnostnih vrat" — adaptive TDEE must not become a bypass around
  the safety gate), but PHYS-04 itself is Phase 23's requirement, not yet built. Phase 28 should
  not implement a duplicate safety gate — just not create a path that skips whatever Phase 23
  ships. Flagged for research/planning to check ordering against, not decided here.

None — no other scope-creep suggestions came up during discussion; all four areas stayed within
the TDEE-01–05 boundary.

</deferred>

---

*Phase: 28-adaptive-tdee-activity-calibration*
*Context gathered: 2026-09-28*
