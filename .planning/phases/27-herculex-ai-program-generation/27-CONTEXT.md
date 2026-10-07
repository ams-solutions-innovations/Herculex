# Phase 27: Herculex AI Program Generation - Context

**Gathered:** 2026-09-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Add a fourth `ProgramBuildMode` ("Herculex AI") to the program builder alongside the
existing `smart`/`guided`/`manual` modes. This mode calls a new server-side Gemini
`kind: "program_brief"`, grounded in `knowledge_base.ts`'s `programming` segment (Phase
26's corpus contract). The AI returns a **program design brief** — split, periodization
model, weekly day roles (each with its own rationale), muscle priorities, phase intent —
and **never** an exercise list, sets, reps, load, RPE, tempo, or metcon time caps. The
brief is validated against existing Dart enums and a new configuration-level guardrail
check before it is allowed to become a real program; a violating brief is rejected with a
visible explanation and the builder falls back to the existing deterministic
recommendation. On success the brief pre-fills the same builder screens Smart/Guided use
today (not a separate one-shot flow), the user can still hand-edit any field, and the
resulting program lands in the existing `ProgramReviewView` archived and unactivated,
exactly like today's Smart/Guided paths, showing per-day AI rationale and requiring
explicit confirmation via `_confirm()`.

Requirements: AIP-01–05 (locked by ROADMAP.md/REQUIREMENTS.md — this discussion covers
HOW, not WHETHER).

**Explicitly out of scope for this phase:** exercise selection (stays with
`SmartProgramPlanner`), any new `PeriodizationModel`/`SplitType`/`ExperienceLevel` enum
values, `TrainingStyle` (Arnold/Heavy-Duty/evidence-first) as a concept, the real corpus
content deploy for `knowledge_base.ts`'s `programming` segment (separate, can ship as its
own deploy independent of this phase's code).

</domain>

<decisions>
## Implementation Decisions

### musclePriorities schema
- **D-01:** The brief's `musclePriorities` field reuses `dream_physique`'s existing
  `programmingProfile.musclePriorities` schema exactly: canonical `muscleId` (19-value
  enum: `chest, back, lats, traps, front_delts, side_delts, rear_delts, biceps, triceps,
  forearms, abs, obliques, neck, quads, hamstrings, glutes, calves, adductors, abductors`),
  `priority` (`high`/`medium`/`maintenance`), `confidence` (0.0–1.0), `rationale`, and
  `uncertainties[]`. This is a deliberate reuse, not a new shape — it plugs directly into
  `block_builder_view.dart`'s existing `_applyDreamPhysiqueTuning()` →
  `weeklySetCaps`/`muscleFocusWave` pump with no new apply logic.
- **D-02:** If the AI returns a `muscleId` outside the canonical 19-value list, the
  validator **rejects the entire brief** (not just that one priority entry) — consistent
  with how every other enum field in the brief is treated (D-04 below) and with the
  delivered textbook's `VALIDATE-PLAN-01` rule ("unknown enum value = rejection, not a
  silent default").

### Builder flow shape
- **D-03:** Selecting "Herculex AI" does **not** skip the existing builder screens. The
  brief pre-fills split/periodization/day-roles/muscle-priority pickers on the same
  screens Smart/Guided already render, exactly the way dream-physique priorities pre-fill
  Smart mode today (and can still be overridden via the existing manual-muscle-plan
  toggle pattern). No new one-shot "black box → review" screen is built.
- **D-04:** Generation is **not** auto-fired on mode selection. A "Generate" button
  triggers one `program_brief` call (one quota unit); a later "Regenerate" action re-fires
  it. This keeps quota consumption tied to an explicit user action.
- **D-05:** When the validator rejects a brief (guardrail violation or unknown enum
  value), the user sees a visible message explaining **what** was rejected (e.g. "The AI
  suggested a 6-day PPL with Max Effort, which exceeds the safety limit"), and the builder
  automatically falls back to showing the existing Smart/Guided recommendation as the
  starting point — never a dead end. No silent automatic retry with a stricter prompt is
  built; one call, one visible outcome.

### Guardrail extraction scope
- **D-06:** The Max-Effort-per-week (max 2) and 6-day-PPL-with-Max-Effort checks
  currently inline in `block_builder_view.dart`'s `_create()` (around lines 3232, 3237)
  are extracted into a **new method on the existing `ProgramGuardrails` class**
  (`lib/features/programs/domain/program_guardrails.dart`) — not a new standalone class.
  `ProgramGuardrails` already validates materialized slots
  (`validateMaxEffortWeek(Iterable<GuardedProgramSlot>)`); the new method validates
  **pre-materialization configuration** (chosen split, periodization model, per-day
  method selections) as a second, earlier-lifecycle check on the same class — one
  guardrail home regardless of validation stage.
- **D-07:** `_create()` for **all** build modes (manual, smart, guided) is retrofitted to
  call the new shared method instead of its current inline `StateError` throws, and the
  Herculex AI brief validator calls the exact same method. This removes duplication
  end-to-end rather than adding a second copy of the rule for only the new AI path.
  **Regression risk:** existing tests covering manual/smart/guided creation-time
  validation must keep passing after the extraction — planning should budget for
  characterization tests before the refactor, not just after.

### Brief provenance & rationale persistence
- **D-08:** The accepted brief is persisted in a **new small table**, modeled directly on
  `PhysiqueProgrammingProfiles`'s existing shape (`prioritiesJson`, `source`,
  `modelVersion`, `confirmedAt`, `active`) — add `source: 'herculex_ai'`,
  `knowledgeVersion`, a `programId` link, and the per-day rationale structure (D-09). This
  is a full 5-chore schema bump per `CLAUDE.md` (schemaVersion + guarded `onUpgrade`,
  drift schema dump/generate, migration test retargeting, matching
  `supabase/migrations/NNNN_*.sql`) — planning should check whether this table needs sync
  (likely yes, same as `PhysiqueProgrammingProfiles`, which has `SyncColumns`/
  `SyncTombstone`).
- **D-09:** AIP-04's "shows its rationale per day" is taken literally: the AI returns a
  **separate rationale per `dayRoles[]` entry** (each `{dayIndex, role, focus}` gets its
  own short "why"), not one paragraph covering the whole brief. This is a deliberate
  divergence from the single-`rationale`-string sketch in
  `docs/herculex-ai-plan-2026-09-27.md` §3.1 — that sketch is a starting point, not the
  locked shape. The new table (D-08) stores this as a structured per-day array, not a
  flat string, so `ProgramReviewView` can render it alongside each day the way it already
  renders per-slot `SelectionExplanation` rationale from Phase 17 (a **different**
  rationale, for a different question — see Code Context below).

### Claude's Discretion
- Exact `knowledgeVersion`/`modelVersion` field placement and JSON shape within the new
  table beyond what D-08 fixes (column names, indexing) — standard 5-chore schema-bump
  territory, same latitude given to Phase 28's `tdee_estimates` table.
- Exact wording of the rejection message in D-05 and the "Generate"/"Regenerate" button
  copy.
- Exact retry/backoff behavior of the `program_brief` Gemini call itself (network
  failure vs. validation rejection are different failure modes — D-05 only covers the
  latter; AIP-05's offline/unconfigured/over-quota degradation covers the former and is
  already locked by the requirement, not re-discussed here).
- Whether the new `ProgramGuardrails` configuration method takes the raw builder state
  directly or a small intermediate value object — planner/researcher's call, informed by
  what `_create()`'s existing local variables (`_mainMethodByDayLabel`, `_model`,
  `_split`) look like at the call site.
- Per-kind quota number for `program_brief` within Phase 26's already-decided tiering
  shape (cheap-frequent > occasional > expensive-multi-image) — Phase 26 fixed the
  *shape*, not every kind's exact number; `program_brief` is a new kind this phase adds
  to that table.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Textbook (delivered 2026-09-29, the source for the `programming` corpus segment)
- `outputs/bodybuilding-blueprint/The Bodybuilding Programming Blueprint.docx` (PDF render:
  `outputs/bodybuilding-blueprint/research/render_full_qa/The Bodybuilding Programming
  Blueprint.pdf`) — Part XI (§45–50) is the direct model for this phase's brief/validate/
  fallback pipeline; Part VI (§22–26) is the source prose for `knowledge_base.ts`'s
  `programming` segment content (a separate deploy, not blocked by this phase).
- `outputs/bodybuilding-blueprint/Herculex_Programming_Rules.json` — 34 machine-readable
  rule IDs (`VALIDATE-PLAN-01`, `SAFETY-*`, `VOLUME-*`, etc.), JSON schemas, and example
  profile/week payloads. Numeric/enum rules here belong in Dart validators per this
  discussion's D-02/D-06, not injected into the AI prompt as instructions the model could
  override. **Note for research:** this JSON's `ExperienceLevel` has 5 tiers (novice,
  early intermediate, intermediate, advanced, elite) vs. the app's 3
  (`novice`/`intermediate`/`advanced`) — mapping this is research's job, not decided here
  since it's outside AIP-01–05's locked scope (no new enum values, per Domain boundary
  above); a lossy collapse (early→novice/intermediate boundary, elite→advanced) is the
  likely approach but should be verified against how `ExperienceRecommendation` is
  consumed elsewhere.
- The folder `outputs/bodybuilding-blueprint/` is **untracked** and contains a `.venv` and
  whisper model cache — only the `.docx` and `Herculex_Programming_Rules.json` should ever
  be referenced or committed from it, never the whole directory.

### Herculex AI amendment & house rules
- `docs/herculex-ai-plan-2026-09-27.md` §3 ("Faza 27") — the original design sketch this
  discussion refines: the JSON brief shape example (§3.1, superseded by D-01/D-09 above),
  the "AI never returns exercise IDs/sets/reps/time-caps" prohibition (§3.2, unchanged),
  the confirm-flow diagram (§3.4, unchanged — `program_review_view.dart:287` `_confirm()`
  is still the only point a program becomes real), and the explicit call to extract the
  Max-Effort/PPL checks (§3.3, refined by D-06/D-07).
- `.planning/ROADMAP.md` (Phase 27 section) — goal, requirements, success criteria.
- `.planning/REQUIREMENTS.md` §13 (AIP-01–05) — the five locked requirements.
- `.planning/phases/26-herculex-ai-knowledge-base-brand-unification/26-CONTEXT.md` —
  corpus injection mechanism (D-01/D-02 there: `systemInstruction` field, `knowledge_base.ts`
  segments), `knowledgeVersion`/`modelVersion` provenance shape (D-05–D-09 there, this
  phase's D-08 table follows that pattern), and per-kind quota tiering shape (D-10/D-11
  there — this phase adds `program_brief` as a new kind within that shape).
- `.planning/phases/06-label-ocr-and-photo-assist/06-AI-SPEC.md` — house rule
  ("deterministic primary, AI bounded, AI never writes to the database, user confirms")
  that AIP-02/03/04 directly implement.

### CLAUDE.md house rules that apply
- `CLAUDE.md` "Schema changes are five chores, not one" — the new brief-persistence table
  (D-08) is a full 5-chore bump; local drift is at v44/v45 depending on whether Phase 28's
  `tdee_estimates` (v45) has landed first per the execution order.
- `CLAUDE.md` "No hand-written file over 600 lines" — `block_builder_view.dart` is already
  3398 lines; per the amendment doc's own risk log, splitting it via `part`/`part of` into
  a subfolder is this phase's **first** task, not a cleanup afterthought, since the 4th
  mode's UI adds to an already-over-budget file.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `supabase/functions/gemini-analyze/prompts.ts` `dreamPhysiquePrompt` (~line 260–375) —
  the `musclePriorities`/`programmingProfile` JSON schema this phase's brief reuses
  verbatim (D-01), including the exact safety-rule prose pattern ("Do not choose a final
  exercise list or silently prescribe/change a program... Herculex makes later
  deterministic programming decisions") that the new `program_brief` prompt should mirror
  for AIP-02's exercise-list prohibition.
- `lib/features/programs/presentation/views/block_builder_view.dart`
  `_applyDreamPhysiqueTuning()` / `_dreamPhysiquePriorities` / `_useManualMusclePlan` /
  `weeklySetCaps` / `muscleFocusWave` (~lines 264–3300) — the existing "AI-derived
  priorities tune the deterministic plan, user can override" mechanism this phase's
  musclePriorities field plugs into directly (D-01).
- `lib/data/local/tables.dart:964` `PhysiqueProgrammingProfiles` — the direct schema
  template for the new brief-persistence table (D-08): `prioritiesJson`, `source`,
  `modelVersion`, `confirmedAt`, `active`, already using `SyncColumns`/`SyncTombstone`.
- `lib/features/programs/domain/program_guardrails.dart` `ProgramGuardrails` (abstract
  final class) — already has `maxEffortMinimumGap`, `maxSmartMaxEffortSlotsPerWeek`, and
  `validateMaxEffortWeek(Iterable<GuardedProgramSlot>, {smartMode})`; D-06 adds a sibling
  method here for pre-materialization configuration checks.
- `lib/features/programs/domain/selection_explanation.dart` `SelectionExplanation` +
  `lib/data/local/tables.dart:929` `ProgramSlotExplanations` (Phase 17) — answers "why
  this exercise was chosen" per slot. **Not reusable for this phase's rationale** (D-09) —
  it's a different question (exercise-selection rationale vs. design-brief rationale) at a
  different granularity (per-slot vs. per-day). Both will render in `ProgramReviewView`
  side by side but come from separate tables/mechanisms.

### Established Patterns
- `lib/features/programs/data/smart_program_planner.dart:109` class doc comment —
  "Deterministic local planner used by both Smart and Guided builder modes. Gemini may
  provide muscle priorities, but final exercise selection remains here where equipment,
  preferences and safety rules are enforceable." This exact seam is what the Herculex AI
  mode extends to a full brief without changing.
- `lib/features/programs/presentation/views/block_builder_view.dart:~3210–3240` `_create()`
  — the current inline home of the Max-Effort/PPL checks (D-06/D-07 extraction target) and
  the place `buildMode`, `trainingGoal`, `experienceLevel` are already threaded into
  `createProgramFromSplit(...)`.
- `lib/features/programs/presentation/views/program_review_view.dart:287` `_confirm()` —
  the single point a program becomes real (`archiveProgram(..., archived: false)`);
  unchanged by this phase (AIP-04).
- `supabase/functions/gemini-analyze/index.ts:29` `GeminiKind` union type (currently 8
  values) — `program_brief` is a 9th value this phase adds, following the exact same
  dispatch/quota/provenance pattern as the other 8 (per-kind limit in `kindLimits`,
  display name in `kindDisplayNames`, fail-closed quota per Phase 26's D-13).

### Integration Points
- `lib/features/programs/domain/programming_models.dart:9` `ProgramBuildMode` enum (3
  values today: `smart`, `guided`, `manual`) — gains a 4th value this phase (AIP-01).
- `lib/features/programs/domain/split_template.dart` `SplitType`,
  `lib/features/programs/domain/periodization.dart` `PeriodizationModel`,
  `lib/features/programs/domain/programming_models.dart` `DayStressRole`/`TrainingGoal`/
  `ExperienceLevel` — the closed enum set the brief validator checks every field against
  (D-02's "unknown = reject" policy applies uniformly across all of these, not just
  `muscleId`).

</code_context>

<specifics>
## Specific Ideas

No specific visual mockups were dictated. The concrete reference point throughout
discussion was "match how dream-physique priorities already behave in the builder today"
(D-01, D-03) — that existing interaction is the closest thing to a mockup this phase has,
and downstream agents should look at it directly rather than design a new pattern.

</specifics>

<deferred>
## Deferred Ideas

- Real content for `knowledge_base.ts`'s `programming` segment (sourced from the delivered
  textbook's Part VI) — this can ship as an independent deploy, before or after this
  phase's code, since Phase 26 already built the injection path against a placeholder.
  Not blocking, not this phase's task to write the prose itself unless planning decides
  otherwise.
- Mapping the textbook's 5-tier experience model and style concepts (Arnold-inspired,
  Heavy-Duty-inspired, evidence-first) onto the app — explicitly out of scope per the
  Domain Boundary (no new enum values in this phase). If a future phase wants this, it
  needs its own discussion.
- Any retry/regenerate cap beyond quota itself (e.g. "max 3 regenerates per program
  creation session") — not raised during discussion; quota is the only limiting
  mechanism decided (D-04).

None — no other scope-creep suggestions came up; all four discussed areas stayed within
the AIP-01–05 boundary.

</deferred>

---

*Phase: 27-herculex-ai-program-generation*
*Context gathered: 2026-09-29*
