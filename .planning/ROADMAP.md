# Herculex Roadmap

## Milestones

- **v1.0 Nutrition & Workout Core**: [Shipped 2026-09-13](milestones/v1.0-ROADMAP.md) — 11 phases, 27 plans, 36/39 requirements satisfied (3 deferred). [Audit Report](v1.0-MILESTONE-AUDIT.md).
- **v2.0 Training Programs Revamp, Dream Physique & Gamification**: In Progress (Phases 15–25).

---

## Milestone v2.0: Training Programs Revamp, Dream Physique & Gamification

Blueprint reference: [`docs/training-programs-physique-gamification-plan-2026-09-10.md`](../docs/training-programs-physique-gamification-plan-2026-09-10.md)

### Phase 15: Program Generator Regression Fixes & Interaction Hardening

**Goal:** Eliminate immediate regressions causing unexpected 8×3 Dynamic Effort sets, fix transparent replacement sheet modal, hide shell controls during keyboard focus, and resolve calendar session start/resume ambiguity.

**Requirements:** FIX-01–04

**Success:** Novice linear full body programs never receive 8×3 Dynamic Effort; replacement sheet is fully opaque; keyboard input safely hides bottom navigation, finish, and add buttons; calendar launches specific `scheduleId` without creating duplicate sessions.

### Phase 16: Exercise Programming Metadata & Discipline Taxonomy

**Goal:** Provide the catalog and database runtime with explicit difficulty levels, commonness tiers, discipline tags, prerequisites, and basic weights profile data.

**Requirements:** META-01–04

**Success:** Every generable movement carries difficulty, commonness, and discipline tags; beginners cannot receive advanced calisthenics (planche, muscle-up) without verified prerequisites; basic weights profile contains no specialty bars or specialist variations.

### Phase 17: Deterministic Program Planner & Hard Guardrails

**Goal:** Unify program generation under a single authoritative contract (`ProgramGenerationRequest`), enforce strict hard filters before scoring, and return transparent selection explanations.

**Requirements:** PLAN-01–04

**Success:** Generation matrix is deterministic; hard constraints (injury, equipment, difficulty, style) are never relaxed to fill a slot; anchor lifts remain guaranteed across weeks; planner outputs human-readable rationales.

**Plans:** 5/5 plans complete

Plans:
**Wave 1**

- [x] 17-01-PLAN.md — Wave 0: ProgramSlotExplanations table (schema v42), SelectionExplanation model, JointModel.excludedMusclesFor helper, EmptySlotNotice widget
- [x] 17-02-PLAN.md — Wave 1: injury/pain + prerequisites hard filters, delete unused ProgramGenerationRequest, replace crash-on-exhaustion with D-01/D-03 graceful empty-slot resolution

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 17-03-PLAN.md — Wave 2: anchor-lift lock across block weeks (D-09–D-12)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 17-04-PLAN.md — Wave 3: persist SelectionExplanation to ProgramSlotExplanations for every slot/week

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 17-05-PLAN.md — Wave 4: surface empty-slot rationale in the program review UI (D-04)

### Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions

**Goal:** Align generated programs to user time constraints and unify set prescriptions across preview, editor, and workout sessions.

**Requirements:** PRES-01–04

**Success:** `SlotPrescriptionCodec` ensures byte-equivalent prescriptions from preview to active session; automatic warmup sets scale with target intensity; time estimator maintains session length within ±10% tolerance; intensity techniques require opt-in.

**Plans:** 6/6 plans complete

Plans:
**Wave 1**

- [x] 18-01-PLAN.md — SlotPrescriptionCodec + schema v43 (3 new columns, full 5-chore migration)
- [x] 18-02-PLAN.md — WarmupResolver + WorkoutDurationEstimator (pure domain services)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 18-03-PLAN.md — Hard-hide advanced set types for SlotRole.main / opt-in gating
- [x] 18-04-PLAN.md — planned_session_resolver.dart: codec decode + WarmupResolver wiring
- [x] 18-05-PLAN.md — smart_program_planner.dart: duration-estimator trim loop + codec encode + persisted opt-in

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 18-06-PLAN.md — Calendar preview renders full set-by-set prescription detail

### Phase 19: Program & Wave Editor with Explainable Periodization

**Goal:** Enable clear weekly and wave-level program inspection and editing, with scoped exercise replacements and in-depth method explanations.

**Requirements:** EDIT-01–04

**Success:** Single active week view with Week dropdown and Wave indicator; exercise replacement supports `thisWave`, `thisAndFutureWaves`, and `entireBlock` scopes; periodization guide provides transparent 8-week examples; edits never alter started workouts.

**Plans:** 4/4 plans complete

Plans:
**Wave 1**

- [x] 19-01-PLAN.md — WaveLabel domain function (anchor-slot wave-boundary walk + count, TDD)
- [x] 19-02-PLAN.md — Extract ExerciseReplacementSheet into a shared presentation/sheets/ file
- [x] 19-03-PLAN.md — Periodization guide 8-week expansion + EDIT-03 replace/rematerialize safety regression test

**Wave 2** *(blocked on Wave 1 completion — 19-01, 19-02)*

- [x] 19-04-PLAN.md — Retrofit block_detail_view.dart: Week dropdown + wave-strip + per-exercise replacement (part/part-of split)

### Phase 20: Active Workout Shell & Calendar Execution Flow

**Goal:** Solidify interaction contracts between active workout execution, shell controls, and calendar navigation.

**Requirements:** FLOW-01–03

**Success:** `KeyboardObstructionScope` reliably hides navigation and action buttons; scheduled workout preview renders details without writing to the database; calendar routing cleanly distinguishes preview/start, resume, and history detail.

**Plans:** 5/5 plans complete

Plans:
**Wave 0**

- [x] 20-01-PLAN.md — GoRouter widget-test harness (infra for FLOW-02/FLOW-03 test coverage)

**Wave 1**

- [x] 20-02-PLAN.md — KeyboardObstructionScope extraction (FLOW-01)
- [x] 20-03-PLAN.md — plannedWorkoutPreview route + provider + PlannedWorkoutPreviewView (FLOW-02)

**Wave 2** *(blocked on Wave 1 completion — 20-03)*

- [x] 20-04-PLAN.md — Status-gated View-workout routing: done/in-progress to WorkoutHistoryView (FLOW-03)

**Wave 3** *(blocked on Wave 2 completion — 20-04)*

- [x] 20-05-PLAN.md — Calendar occurrence wiring: initialScheduleId + highlight for MonthCalendar and WeekBoard (FLOW-03)


### Phase 21: CrossFit & GPP Training Tracks

**Goal:** Support structured CrossFit and GPP training programs with multi-segment session blueprints and scaled gymnastics/metcons.

**Requirements:** CF-01–03

**Success:** Sessions structured into warmup, skill/strength, metcon, and cooldown segments; AMRAP, EMOM, and For Time formats preserve time caps; Full Body 2× + GPP split delivers dedicated conditioning without 8×3 sets.

**Plans:** 6/7 plans executed

Plans:
**Wave 1**

- [x] 21-01-PLAN.md — Wave 1: SessionSegment enum + CrossfitSlotNeed descriptor + schema v44 (sessionSegment ×2, supersetGroup, plannedSessionSegment) + matching Supabase migration [BLOCKING]
- [x] 21-02-PLAN.md — Wave 1: CrossfitScalingPolicy — time caps per level, complexity ceiling, recovery-reserve day-spacing check (D-06)
- [x] 21-03-PLAN.md — Wave 1: WorkoutDurationEstimator.estimateCappedSegment + prerequisiteSlugs metadata curation (kipping/strict muscle-up, 6 Olympic lifts)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 21-04-PLAN.md — Wave 2: CrossfitProgramPlanner — warmup/skill/strength/metcon/cooldown segment assembly, AMRAP/EMOM/For-Time format rotation (D-01–D-05)
- [x] 21-05-PLAN.md — Wave 2: GppProgramPlanner — standalone GPP day content, Dynamic-Effort guard hardening (CF-03)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 21-06-PLAN.md — Wave 3: Wire CrossfitProgramPlanner/GppProgramPlanner into smart_program_planner.dart, week-driven format rotation, capped-duration trim, end-to-end regression tests

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 21-07-PLAN.md — Wave 4: Thread sessionSegment/supersetGroup through planned_session_resolver.dart materialization, end-to-end threading tests

### Phase 22: Primary Lift Strength Specialization

**Goal:** Enable specialized strength programs centered around a single target lift (e.g. Squat) with sticking point transfer exercises and baseline volume maintenance.

**Requirements:** SPEC-01–03

**Success:** Sticking point selections (bottom, mid, lockout) map to biomechanically relevant variations; anchor lift frequency is preserved; non-target muscle groups remain above maintenance volume; unrealistic deadlines prompt realistic time projections.

### Phase 23: Persistent Dream Physique & Multi-Phase Nutrition

**Goal:** Transform Dream Physique into a persistent goal with synchronized assessment history, private local photo storage, and structured multi-phase nutrition roadmaps.

**Requirements:** PHYS-01–04

**Success:** Goals and assessments persist across app restarts and sync; photos stored locally with EXIF stripped and optional blur; phased nutrition plans (`cut`, `maintain`, `recomp`, `bulk`) compute realistic tempos; underage users protected from aggressive deficits/surpluses.

### Phase 24: Gamification System & 15-Rank XP Ledger

**Goal:** Establish an authentic, idempotent 15-tier ranking system driven by verified workout and nutrition progress without manipulative gamification.

**Requirements:** XP-01–04

**Success:** Idempotent `xp_events` ledger prevents duplicate awards; 15 Herculex ranks reflect verified training and consistency without bypassing generator safety gates; strength XP accounts for historical bodyweight and canonical movements; progress details are fully transparent.

### Phase 25: Cloud Sync, Privacy & Export Hardening

**Goal:** Ensure complete data synchronization, owner-only RLS security, local data wipe, and complete JSON export across all new tables.

**Requirements:** SYNC-01–03

**Success:** Drift schemas (v39/v40+) and Supabase migrations apply cleanly with verified replay tests; local data wipe purges all v2.0 rows and photos; JSON export delivers complete user history.

---

## Deferred & Future Scope

- **Samsung Now Bar Live Update (Deferred to January):** Upgrade ongoing workout surface into a native Android 16 (API 36) `requestPromotedOngoing(true)` / `ProgressStyle` Live Update.
- **Buddy VS comparison (BUD-07):** Post-workout head-to-head comparison views.
- **Friends model (BUD-08):** Persistent social graph and invitations.
- **Challenges (BUD-09):** Goal-based peer challenges with deadlines.
- **Recipe URL import (PLAN-01)** & **Meal planner / grocery lists (PLAN-02)**.
- **Voice food entry (VOICE-01)**.
