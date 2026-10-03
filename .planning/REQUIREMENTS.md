# Requirements: Milestone v2.0 — Training Programs Revamp, Dream Physique & Gamification

**Defined:** 2026-09-13  
**Amended:** 2026-09-27 — Herculex AI scope added (Phases 26–29, PHYS-05–08). See [`docs/herculex-ai-plan-2026-09-27.md`](../docs/herculex-ai-plan-2026-09-27.md).  
**Source Blueprint:** [`docs/training-programs-physique-gamification-plan-2026-09-10.md`](../docs/training-programs-physique-gamification-plan-2026-09-10.md)  
**Core Value:** Safe, deterministic, and explainable training program generation; flexible program and wave editing; persistent Dream Physique goals with phased nutrition; and an authentic 15-tier XP gamification system. Herculex AI is an additive, bounded layer over that core — it proposes and explains, the deterministic engines decide.

---

## Requirements

### 1. Regression & Safety Fixes (Phase 15)

- [ ] **FIX-01**: Novice linear full-body programs never receive Dynamic Effort 8×3 sets without explicit user opt-in.
- [ ] **FIX-02**: Replacement exercise modal renders using opaque `surfaceContainer` (via `HxSheet`) across light and dark themes.
- [ ] **FIX-03**: Active workout input focus hides and un-focuses navigation bar, Finish, and Add buttons simultaneously with hit-testing disabled.
- [ ] **FIX-04**: Calendar day detail launches scheduled workouts by explicit `scheduleId`, cleanly differentiating Start from Resume.

### 2. Exercise Programming Metadata & Disciplines (Phase 16)

- [x] **META-01**: Exercise catalog defines explicit `difficultyLevel` (novice, intermediate, advanced), `commonnessTier` (basic, common, specialty, manualOnly), and `disciplines`.
- [x] **META-02**: Technical movements enforce prerequisite checks (`prerequisiteSlugs`) before entering candidate pools.
- [x] **META-03**: `basicWeights` training style restricts movements strictly to standard barbell, dumbbell, cable, and machine equipment without specialty bars/variants.
- [x] **META-04**: Scaling groups (`scalingGroup`, `scalingOrder`) allow automated progressive regression for advanced movements.

### 3. Deterministic Planner & Hard Guardrails (Phase 17)

- [ ] **PLAN-01**: Unified `ProgramGenerationRequest` acts as single authoritative entry point for all generation parameters.
- [ ] **PLAN-02**: Hard filters (injury/pain, equipment, style, experience, prerequisites) execute before scoring and are never relaxed to fill a slot.
- [x] **PLAN-03**: Core anchor movements remain guaranteed across block weeks rather than rotating out on affinity scoring.
- [x] **PLAN-04**: Planner returns human-readable selection rationales (`SelectionExplanation`) for every chosen and excluded movement.

### 4. Time Budget, Warmups & Prescriptions (Phase 18)

- [ ] **PRES-01**: `SlotPrescription` uses a versioned JSON codec (`SlotPrescriptionCodec`) guaranteed byte-equivalent across review, editor, and workout.
- [ ] **PRES-02**: `WorkoutDurationEstimator` calculates realistic workout durations including warmups, rest intervals, and unilateral work.
- [ ] **PRES-03**: `WarmupResolver` automatically scales warmup sets according to planned target intensity and movement order.
- [ ] **PRES-04**: Advanced intensity techniques (failure, rest-pause, drop, myo-reps) are opt-in and barred from technical compound lifts.

### 5. Program & Wave Editor (Phase 19)

- [x] **EDIT-01**: Program viewer renders single active week with dedicated Week dropdown and exercise wave indicators (`Week N of M`, `Wave X of Y`).
- [x] **EDIT-02**: Exercise replacements offer scoped choices: `thisWave`, `thisAndFutureWaves`, or `entireBlock`.
- [x] **EDIT-03**: Program edits never mutate or overwrite previously started or completed workout occurrences.
- [x] **EDIT-04**: Periodization options (Linear, Concurrent, Westside, Block) display dedicated educational guides with 8-week examples.

### 6. Active Workout Shell & Calendar Execution Flow (Phase 20)

- [ ] **FLOW-01**: `KeyboardObstructionScope` manages keyboard visibility, animations, and hit-testing across shell and active workout screens.
- [ ] **FLOW-02**: `PlannedWorkoutPreviewView` renders full workout preview with exercise details without writing to the database.
- [ ] **FLOW-03**: Calendar entries correctly route to Preview & Start, Resume active session, or History detail based on status.

### 7. CrossFit & GPP Training Tracks (Phase 21)

- [x] **CF-01**: CrossFit sessions structure into ordered blueprint segments (warmup, skill/strength, metcon, cooldown) with time caps.
- [x] **CF-02**: CrossFit experience levels scale movement complexity and metcon formats (AMRAP, EMOM, For Time).
- [x] **CF-03**: Full Body 2× + GPP split delivers dedicated conditioning sessions without unintended Dynamic Effort sets.

### 8. Primary Lift Strength Specialization (Phase 22)

- [x] **SPEC-01**: Strength specialization targets user-selected lift (e.g. Squat) with current 1RM, target weight, and sticking point analysis (bottom, mid, lockout).
- [x] **SPEC-02**: Specialization planner preserves anchor lift frequency while maintaining all non-target muscle groups above baseline maintenance volume.
- [x] **SPEC-03**: Unrealistic target timelines generate realistic projected time horizons with warnings rather than aggressive programming.

### 9. Persistent Dream Physique & Multi-Phase Nutrition (Phase 23)

- [x] **PHYS-01**: Dream Physique goals, assessments, and check-in history persist in synchronized local/remote tables.
- [x] **PHYS-02**: Physique photos are stored in app-sandboxed local documents with EXIF stripped and optional facial blur.
- [x] **PHYS-03**: Multi-phase nutrition roadmaps (`cut`, `maintain`, `recomp`, `maingain`, `bulk`) compute realistic deficit/surplus pacing.
- [x] **PHYS-04**: Underage users and low-confidence visual assessments are barred from aggressive caloric deficits or surpluses.
- [x] **PHYS-05**: Progress screen shows the active body-composition phase (`cut`, `recomp`, `maingain`, `bulk`, `maintain`), position within the multi-phase roadmap, time in phase, and exit criteria, driven by the persisted plan from PHYS-03.
- [x] **PHYS-06**: Check-in photos are rate-limited to at most one per 7 days per goal, enforced in the repository rather than the widget, with the next eligible date surfaced in the UI.
- [x] **PHYS-07**: Each check-in returns a Herculex AI directional verdict (on track, off track, inconclusive) as a confidence-banded range against the baseline, never a false-precision percentage, and never auto-changes calorie targets.
- [x] **PHYS-08**: Progress screen charts bodyweight trend, strength trend (e1RM on canonical lifts), training level, and the phase-target band across the goal horizon.

### 10. Gamification & 15-Rank XP Ledger (Phase 24)

- [ ] **XP-01**: Double-entry idempotent `xp_events` ledger records verifiable points from completed workouts, PRs, and physique check-ins.
- [ ] **XP-02**: 15 Herculex ranks (`Novice I–V`, `Intermediate I–V`, `Advanced I–V`) reflect earned lifetime XP without manipulating generator eligibility.
- [ ] **XP-03**: Strength XP normalizes against historical bodyweight and canonical movement slugs using `TrainingSnapshot` effective load.
- [ ] **XP-04**: UI displays transparent progress breakdown, recent XP events, and upcoming rank requirements without negative gamification.

### 11. Cloud Sync, Privacy & Export Hardening (Phase 25)

- [ ] **SYNC-01**: Drift schemas and Supabase migrations support all v2.0 tables with strict foreign keys, outbox triggers, and owner-only RLS.
- [ ] **SYNC-02**: Local data wipe completely purges all v2.0 tables, XP ledgers, and physical image assets.
- [ ] **SYNC-03**: Full structured JSON export packages all workout, program, physique, and gamification history for user download.

### 12. Herculex AI Knowledge Base & Brand Unification (Phase 26)

- [x] **KB-01**: A versioned coaching knowledge base ships server-side beside `prompts.ts`, is injected as system instruction for knowledge-grounded kinds, and never appears in the app bundle. _(Foundational scope per 26-CONTEXT.md D-04: corpus + injection plumbing shipped; no kind consumes it yet — that's a later phase's job.)_
- [x] **KB-02**: Every AI result records `knowledgeVersion` and `modelVersion`, so any recommendation is traceable to the corpus that produced it. _(Foundational scope per D-06: modelVersion ships on all 8 kinds now; knowledgeVersion intentionally deferred until a kind injects a corpus segment.)_
- [x] **KB-03**: No user-visible string reads "Gemini"; every AI surface reads "Herculex AI", while provider naming remains internal to class names, `kind` values, and docs.
- [x] **KB-04**: Hercul gains a labelled AI advice channel alongside the deterministic engine; `hercul_rules.json`, `HerculSignals.all`, and the closed-vocabulary test stay intact and keep working offline. _(Non-regression half verified. The "labelled AI advice channel" itself is deferred — human decision 2026-09-28, see 26-VERIFICATION.md — and not yet claimed by any future phase; Phase 27/28/29 planning should pick this up.)_
- [x] **KB-05**: Per-kind AI quotas replace the single shared daily cap, and quota exhaustion fails closed with a clear message rather than silently.

### 13. Herculex AI Program Generation (Phase 27)

- [x] **AIP-01**: `ProgramBuildMode` gains a fourth mode so the builder offers both a manual path and a Herculex AI path.
- [x] **AIP-02**: Herculex AI returns a program design brief (split, periodization model, weekly day roles, muscle priorities, phase intent, rationale) and never an exercise list; `SmartProgramPlanner` remains the sole exercise selector. _(27-03 built the client-side gate that proves this contract — `ProgramBrief.fromJson` strictly validates every enum and rejects any exercise-shaped field at any nesting depth. 27-05 added `GeminiBackend.generateProgramBrief()`, the client-side entry point. 27-06 added the Edge Function's `program_brief` kind itself — prompt, quota, and `normalizeProgramBriefResult()` as the server-side first line of the two-tier defense. 27-09 added `HerculexAiBriefService.generateBrief()`, the calling service — a brief can now actually be requested, transported, and strictly parsed end-to-end, proven by test. UI wiring to trigger it (plan 27-11) is a separate concern from this contract being true.)_
- [x] **AIP-03**: The brief is validated against a strict schema and rejected, falling back to the deterministic recommendation, if it violates any existing guardrail. _(27-02 laid the pre-refactor groundwork; 27-03 delivered the strict-schema half — `ProgramBrief.fromJson` — reusing Dream Physique's musclePriorities shape and rejecting unknown enum values as a whole-brief FormatException. 27-05/27-06 wired the client/server transport. 27-07 built the rejection-message UI (`AiBriefRejectionBanner`). 27-08 extracted the Max-Effort-per-week and 6-day-PPL+Max-Effort checks into `ProgramGuardrails.validateConfiguration()`. 27-11 closes the loop: `_generateHerculexBrief()` calls `validateConfiguration()` against the parsed brief's implied split/periodization immediately after a successful generate, and on any blocking issue shows `AiBriefRejectionBanner` with the validator's verbatim message while leaving the existing Smart/Guided recommendation as the active builder state — never applying the rejected brief. Proven by 7 new widget tests in `test/block_builder_view_test.dart`.)_
- [x] **AIP-04**: An AI-generated program enters the existing review gate archived and unactivated, shows its rationale per day, and requires explicit user confirmation. _(27-04 built the local persistence target the review-gate rendering will read from — `HerculexAiProgramBriefs`, schema v46, D-08's `briefJson` blob carrying D-09's per-day rationale, FK'd to `programId`. 27-07 built the per-day rationale UI (`AiDayRationaleCard`, primary-tinted, fixed "Why this day" heading, renders `dayRoles[].rationale` verbatim, D-09). 27-09 built `HerculexAiBriefService.persistBrief()`/`watchBriefForProgram()`, the sole read/write seam the review gate calls. 27-10 applied and independently verified the matching Supabase migration (chore 5 — owner-only RLS, triggers, realtime, pull index — all confirmed live on `ldzgyzigvbwofbswitrv` via 4 read-only queries), so persisted briefs now sync instead of quarantining. 27-11 added the Generate/Regenerate UI and the accepted-brief state (`_acceptedHerculexBrief`/`_herculexBriefProvenance`) plan 27-13 pre-fills/persists from. 27-12 closes the loop: `ProgramReviewView._DayCard` now renders `AiDayRationaleCard` per day, additive to the existing `EmptySlotNotice` rendering, conditional on an active `HerculexAiProgramBriefs` row with `source == 'herculex_ai'` for the reviewed program — absent entirely for manual/smart/guided programs. `_confirm()` (the sole activation point) is unchanged, proven by `git diff` showing zero changed lines in that method. Proven by 6 new widget tests in `test/program_review_view_test.dart`.)_
- [x] **AIP-05**: AI generation degrades to the existing Smart/Guided path when offline, unconfigured, or over quota. _(27-09 built the failure-category signal this depends on — `HerculexAiBriefException.isQuotaExhausted`, distinguishing an over-quota failure from the generic offline/unconfigured case (detected via the Edge Function's exact 429 message substrings), proven by test. 27-11 wires the UI degrade-to-Smart/Guided behavior: `_generateHerculexBrief()` catches `HerculexAiBriefException` and shows one of two distinct UI-SPEC-exact messages — offline/unconfigured vs. over-quota — via `AiBriefRejectionBanner`, always leaving the existing Smart/Guided recommendation as the active state. Proven by 2 dedicated widget tests.)_

### 14. Adaptive TDEE & Activity Calibration (Phase 28)

- [x] **TDEE-01**: An observed-expenditure estimator derives TDEE from logged intake and the bodyweight trend over a rolling window, and becomes the baseline source when adherence passes a stated threshold.
- [x] **TDEE-02**: When adherence is insufficient, an activity classifier derives the activity level from `HealthSamples` plus logged training, and Mifflin-St Jeor runs with the derived multiplier instead of the hand-picked one.
- [x] **TDEE-03**: The app chooses its own calibration window and re-calibration cadence from data density; the user never picks a measurement duration.
- [x] **TDEE-04**: Every estimate carries method, confidence, sample window, and inputs, is visible to the user, and never overrides a manually-set maintenance value.
- [x] **TDEE-05**: A material TDEE shift is surfaced in the weekly report and never silently rewrites confirmed targets. _(Non-regression half delivered: `TdeeEstimator.isMaterialShift` persists every shift to `tdee_estimates` and never overwrites a saved manual target, per D-11. The "surfaced in the weekly report" half is deferred to Phase 29 by design (D-10/D-11) — no accept/dismiss UI or material-shift event exists yet.)_

### 15. Weekly Report & Herculex AI Narrative (Phase 29)

- [ ] **RPT-01**: One persisted report row per ISO week, opt-in, covering nutrition adherence, frequent foods, training volume and strength, recovery/sleep/activity, physique progress, and TDEE drift.
- [ ] **RPT-02**: The measured section is computed locally from existing analytics; Herculex AI adds a knowledge-grounded narrative on top, visually separated from the numbers.
- [ ] **RPT-03**: A Sunday notification uses `DateTimeComponents.dayOfWeekAndTime` and deep-links into the report; the report is generated on open, never in the notification callback.
- [ ] **RPT-04**: Reports are browsable as history and never regenerate differently for a past week.
- [ ] **RPT-05**: The report attributes how recovery, sleep, and activity correlate with performance using existing correlation providers, stated as correlation rather than causation.

---

## Traceability

| Requirement | Phase | Status |
|---|---:|---|
| FIX-01–04 | 15 | Pending |
| META-01–04 | 16 | Pending |
| PLAN-01–04 | 17 | Pending |
| PRES-01–04 | 18 | Pending |
| EDIT-01–04 | 19 | Complete |
| FLOW-01–03 | 20 | Complete |
| CF-01–03 | 21 | Complete |
| SPEC-01–03 | 22 | Complete |
| PHYS-01–08 | 23 | Complete |
| XP-01–04 | 24 | Pending |
| SYNC-01–03 | 25 | Pending |
| KB-01–05 | 26 | Complete |
| AIP-01–05 | 27 | Pending |
| TDEE-01–05 | 28 | Complete |
| RPT-01–05 | 29 | Pending |
