# Herculex Roadmap

## Milestones

- **v1.0 Nutrition & Workout Core**: [Shipped 2026-09-13](milestones/v1.0-ROADMAP.md) — 11 phases, 27 plans, 36/39 requirements satisfied (3 deferred). [Audit Report](v1.0-MILESTONE-AUDIT.md).
- **v2.0 Training Programs Revamp, Dream Physique & Gamification**: In Progress (Phases 15–29).

---

## Milestone v2.0: Training Programs Revamp, Dream Physique & Gamification

Blueprint reference: [`docs/training-programs-physique-gamification-plan-2026-09-10.md`](../docs/training-programs-physique-gamification-plan-2026-09-10.md)

Herculex AI amendment (2026-09-27, Phases 26–29 and PHYS-05–08): [`docs/herculex-ai-plan-2026-09-27.md`](../docs/herculex-ai-plan-2026-09-27.md)

**Execution order — not numeric.** Phases 26–29 were appended to preserve existing
numbering, but they have real dependencies that cut across 22–25:

```
26 → 28 → 27 → 22 → 23 → 29 → 24 → 25
```

Phase 26 is foundational: it ships the knowledge-base contract, the Herculex AI rename,
and the per-kind quota model that 27, 29 and PHYS-07 all consume. Phase 28 carries no AI
dependency and feeds both 23 and 29. Phase 25 must stay last so its sync, wipe, and export
hardening can cover every table the new phases add.

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

**Plans:** 9/9 plans complete

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

- [x] 21-07-PLAN.md — Wave 4: Thread sessionSegment/supersetGroup through planned_session_resolver.dart materialization, end-to-end threading tests

**Gap closure (Wave 1, parallel, no interdependency)**

- [x] 21-08-PLAN.md — Wire CrossfitScalingPolicy.complexityCheck into smart_program_planner.dart's _createStableSlots (real candidate-pool substitution + explicit accepted-exception rationale), 2 new regression tests (CF-02)
- [x] 21-09-PLAN.md — Decode prescriptionCodecJson in program_review_view.dart's _ExerciseRow for metcon rows, replacing the "1 sets · 1 reps" placeholder with the real AMRAP/EMOM/For-Time summary (CF-01)

### Phase 22: Primary Lift Strength Specialization

**Goal:** Enable specialized strength programs centered around a single target lift (e.g. Squat) with sticking point transfer exercises and baseline volume maintenance.

**Requirements:** SPEC-01–03

**Success:** Sticking point selections (bottom, mid, lockout) map to biomechanically relevant variations; anchor lift frequency is preserved; non-target muscle groups remain above maintenance volume; unrealistic deadlines prompt realistic time projections.

**Plans:** 4/4 plans complete

Plans:
**Wave 1**

- [x] 22-01-PLAN.md — Wave 1: D-12 sticking-point branching for bench/OHP/pull-up, SquatSpecialization dead-code removal, ProgramGuardrails.validateVolumeFloor/validateKgIncrease
- [x] 22-02-PLAN.md — Wave 1: split-flexibility Apply logic (D-01–D-03), sticking-point helper copy, computed exposures-per-week fix (Pitfall 3)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 22-03-PLAN.md — Wave 2: Weeks-picker timeline-shortfall auto-adjust + kg-increase ceiling warning (D-08–D-11)

**Wave 3** *(blocked on Wave 2 completion — serialized with 22-03 due to a shared edit target, test/block_builder_view_test.dart, not a functional dependency)*

- [x] 22-04-PLAN.md — Wave 3: SpecializationVolumeFloorCard live preview + Create-time volume-floor/kg-increase confirmation (D-04–D-07, D-11)

Cross-cutting constraints:
- D-11 (kg-increase ceiling) is enforced in two places — 22-03's Weeks-picker sheet banner and 22-04's Create-time confirmation — both reading the same `ProgramGuardrails.kgIncreaseCeilings` constants introduced by 22-01.

### Phase 23: Persistent Dream Physique & Multi-Phase Nutrition

**Goal:** Transform Dream Physique into a persistent goal with synchronized assessment history, private local photo storage, structured multi-phase nutrition roadmaps, and a progress screen that shows where the user stands against that goal.

**Requirements:** PHYS-01–08

**Success:** Goals and assessments persist across app restarts and sync; photos stored locally with EXIF stripped and optional blur; phased nutrition plans (`cut`, `maintain`, `recomp`, `bulk`) compute realistic tempos; underage users protected from aggressive deficits/surpluses; the progress screen names the active phase and position in the roadmap; check-ins are capped at one photo per 7 days and return a confidence-banded directional verdict rather than a false-precision percentage; bodyweight, strength, and training-level trends chart against the goal horizon.

**Plans:** 17/17 plans complete

Plans:
**Wave 1**

- [x] 23-01-PLAN.md — Pure-Dart guardrails (PhaseEligibility, under-18 / missing-age / low-confidence), tempo policy, deterministic editable roadmap generator
- [x] 23-02-PLAN.md — Schema v47: four synced physique tables (five chores) + Supabase migration file and parity tests (written, not applied)
- [x] 23-03-PLAN.md — Private photo pipeline: sandbox store, EXIF-stripping sanitiser, on-device face blur (ML Kit), privacy prefs
- [x] 23-04-PLAN.md — gemini-analyze: physique_checkin kind, shared consent gate, per-kind quota, Dream Physique BF range + confidence

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 23-05-PLAN.md — Exit criteria + advance offer, 7-day cap policy, three-state verdict classifier, chart series builders
- [x] 23-06-PLAN.md — Goal and roadmap repositories (start/archive/reconcile, accept/edit/advance/postpone)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 23-07-PLAN.md — Assessment repository (transactional 7-day cap, baseline photos, soft delete) and chart-series repository
- [x] 23-08-PLAN.md — Dart AI service: PhysiqueCheckInBackend, check-in service/parser, Dream Physique confidence fields
- [x] 23-09-PLAN.md — Summary bridge, idempotent legacy migrator (summary history + progress photos), account-wipe extension
- [x] 23-10-PLAN.md — Progress route constants, typography helper, phase pill, restriction notice, verdict chip/range bar/block

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 23-11-PLAN.md — Application layer: providers, chart providers, goal starter, check-in flow

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 23-12-PLAN.md — Bodyweight + target band, e1RM, and training-level chart cards
- [x] 23-13-PLAN.md — Roadmap editor sheet, check-in history, past goals, photo thumbnail, confirmation dialogs

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 23-14-PLAN.md — Check-in sheet (blur, consent, analyse, baseline mode), camera-resume enum + main_scaffold, migration notice
- [x] 23-15-PLAN.md — Nutrition editor eligibility gates, DB-backed summary providers + Dream Physique save path, Profile card link

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 23-16-PLAN.md — Physique progress screen (phase card, timeline, check-in card, charts) + route registration

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 23-17-PLAN.md — Privacy docs, full verification gate, human checkpoints: real-device blur, Supabase v47 push, function deploy

### Phase 24: Gamification System & 15-Rank XP Ledger

**Goal:** Establish an authentic, idempotent 15-tier ranking system driven by verified workout and nutrition progress without manipulative gamification.

**Requirements:** XP-01–04

**Success:** Idempotent `xp_events` ledger prevents duplicate awards; 15 Herculex ranks reflect verified training and consistency without bypassing generator safety gates; strength XP accounts for historical bodyweight and canonical movements; progress details are fully transparent.

### Phase 25: Cloud Sync, Privacy & Export Hardening

**Goal:** Ensure complete data synchronization, owner-only RLS security, local data wipe, and complete JSON export across all new tables.

**Requirements:** SYNC-01–03

**Success:** Drift schemas (v39/v40+) and Supabase migrations apply cleanly with verified replay tests; local data wipe purges all v2.0 rows and photos; JSON export delivers complete user history.

### Phase 26: Herculex AI Knowledge Base & Brand Unification

**Goal:** Establish the server-side coaching knowledge base that grounds every Herculex AI output, make provenance traceable, unify the user-facing brand on "Herculex AI", and replace the shared daily AI cap with per-kind quotas that fail closed.

**Requirements:** KB-01–05

**Success:** The knowledge corpus lives beside `prompts.ts` and never ships in the app bundle; every AI result carries `knowledgeVersion` and `modelVersion`; no user-visible string reads "Gemini" while internal provider naming is untouched; Hercul's deterministic rule engine and its closed-vocabulary test keep working offline beside a clearly-labelled AI advice channel; per-kind quota exhaustion fails closed with a clear message.

**Plans:** 7/7 plans complete

Plans:
**Wave 1**

- [x] 26-01-PLAN.md — Wave 1: knowledge_base.ts corpus + system_instruction/modelVersion provenance plumbing (KB-01, KB-02)
- [x] 26-03-PLAN.md — Wave 1: brand-data consistency across prompts.ts + gemini_food_analyzer_service.dart + gemini_photo_analysis_dialog.dart (KB-03)
- [x] 26-04-PLAN.md — Wave 1: dream_physique_view.dart consent reword + Pitfall-1-safe rename (KB-03)
- [x] 26-05-PLAN.md — Wave 1: measurements feature brand rename (KB-03)
- [x] 26-06-PLAN.md — Wave 1: nutrition feature brand rename, non-data sites (KB-03)
- [x] 26-07-PLAN.md — Wave 1: supplements/workouts/profile-services brand rename (KB-03)

**Wave 2** *(blocked on Wave 1 completion — 26-01)*

- [x] 26-02-PLAN.md — Wave 2: per-kind AI quotas, fail-closed retry, KB-03 index.ts renames, migration 0021 + [BLOCKING] db push (KB-03, KB-04, KB-05)

### Phase 27: Herculex AI Program Generation

**Goal:** Add a Herculex AI path to program creation that proposes a program design brief grounded in the knowledge base, while the deterministic planner remains the sole selector of every exercise.

**Requirements:** AIP-01–05

**Success:** The builder offers a manual path and a Herculex AI path; the AI returns a design brief (split, periodization, day roles, muscle priorities, phase intent, rationale) and never an exercise list; a brief violating any Phase 16–21 guardrail is rejected with fallback to the deterministic recommendation; generated programs land archived and unactivated in the existing review gate with per-day rationale; offline, unconfigured, or over-quota states degrade to the existing Smart/Guided path.

**Plans:** 13/13 plans complete

Plans:
**Wave 1**

- [x] 27-01-PLAN.md — Wave 1: Split block_builder_view.dart into a part/part-of subfolder (mechanical, zero behavior change — prerequisite for every later edit to this file)
- [x] 27-02-PLAN.md — Wave 1: D-07 characterization tests for _create()'s current inline Max-Effort/6-day-PPL guardrail throws, before the extraction touches them
- [x] 27-03-PLAN.md — Wave 1: ProgramBrief domain model — strict enum rejection (D-02), AIP-02 exercise-field prohibition, toJson/fromJson round-trip
- [x] 27-04-PLAN.md — Wave 1: HerculexAiProgramBriefs drift table + schema v46 (5-chore bump, chores 1–4)
- [x] 27-05-PLAN.md — Wave 1: GeminiBackend.generateProgramBrief() + provenance-returning helper (3-tier interface)
- [x] 27-06-PLAN.md — Wave 1: Edge Function program_brief kind — prompt, quota tier, strict server-side normalizer
- [x] 27-07-PLAN.md — Wave 1: AiBriefRejectionBanner + AiDayRationaleCard widget primitives

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 27-08-PLAN.md — Wave 2: Extract Max-Effort/6-day-PPL guardrail into ProgramGuardrails.validateConfiguration() (D-06), retrofit _create() for all build modes (D-07)
- [x] 27-09-PLAN.md — Wave 2: HerculexAiBriefService — generate/parse/persist/read, AIP-05 failure-category translation
- [x] 27-10-PLAN.md — Wave 2: Supabase migration for herculex_ai_program_briefs v46 + [BLOCKING] db push, independently verified

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 27-11-PLAN.md — Wave 3: ProgramBuildMode.herculexAi + 4th mode tile, Generate/Regenerate, guardrail validation, rejection/offline/quota failure states
- [x] 27-12-PLAN.md — Wave 3: Per-day AI rationale rendering in ProgramReviewView, conditional on an active Herculex AI brief

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 27-13-PLAN.md — Wave 4: Pre-fill Step 1–5 from the accepted brief via the existing Dream Physique tuning seam (D-01), persist the brief on program creation (D-08)

### Phase 28: Adaptive TDEE & Activity Calibration

**Goal:** Replace the hand-picked activity multiplier with a measured expenditure estimate that the app calibrates and re-calibrates on its own cadence.

**Requirements:** TDEE-01–05

**Success:** Observed expenditure from logged intake and bodyweight trend becomes the baseline when adherence passes threshold; an activity classifier over `HealthSamples` and logged training supplies the multiplier otherwise; the app picks its own calibration window and cadence without asking the user for a duration; every estimate exposes method, confidence, window, and inputs, and never overrides a manually-set maintenance value; a material shift surfaces in the weekly report instead of silently rewriting confirmed targets.

**Plans:** 11/11 plans complete

Plans:
**Wave 1**

- [x] 28-01-PLAN.md — Wave 1: TdeeEstimateResult/badge-state types + ActivityClassifier (HealthSamples to continuous multiplier)
- [x] 28-02-PLAN.md — Wave 1: MacroTargets split (bmr, multiplierFor, fromMaintenance) with characterization test + TargetResolver TDEE-04 test
- [x] 28-03-PLAN.md — Wave 1: TdeeEstimates drift table + schema v45 + sync registration + migration test retarget

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 28-04-PLAN.md — Wave 2: TdeeEstimator — EWMA trend, observed expenditure, gates, hysteresis/grace, cadence, material shift (D-01–D-04, D-09)
- [x] 28-05-PLAN.md — Wave 2: Supabase migration 20260928000000_tdee_estimates_v45.sql + column-parity test

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 28-06-PLAN.md — Wave 3: TdeeEstimatesRepository + TdeeInputsRepository (Clock-injected, presence-based adherence)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 28-07-PLAN.md — Wave 4: tdee providers, baselineTargetsProvider rewire, recalibration controller registered in app.dart

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 28-08-PLAN.md — Wave 5: Route editor, phase planner and dream-physique through maintenanceKcalProvider/baselineTargetsProvider
- [x] 28-10-PLAN.md — Wave 5: Onboarding copy (D-12) + Profile reset caption/confirm/snackbar (D-13–D-15)

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 28-09-PLAN.md — Wave 6: TdeeEstimateBadge + TdeeEstimateSheet under the maintenance field (D-05–D-08)

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 28-11-PLAN.md — Wave 7: [BLOCKING] user-run Supabase push (0015, 0016 first) + phase-level verification

### Phase 29: Weekly Report & Herculex AI Narrative

**Goal:** Deliver an opt-in Sunday report that snapshots the week across nutrition, training, recovery, physique, and TDEE drift, with a knowledge-grounded narrative layered over measured numbers.

**Requirements:** RPT-01–05

**Success:** One persisted report row per ISO week covering adherence, frequent foods, volume and strength, recovery/sleep/activity, physique progress, and TDEE drift; measured sections computed locally and visually separated from the AI narrative; a Sunday `dayOfWeekAndTime` notification deep-links into a report generated on open rather than in the notification callback; past weeks are browsable and never regenerate differently; recovery/sleep/activity relationships are stated as correlation, not causation.

**Plans:** 2/20 plans executed

Plans:
**Wave 1**

- [x] 29-01-PLAN.md — Wave 1: IsoWeek (ISO key, window, tap-time week), CausalLanguageGuard + strict WeeklyNarrative, route constants
- [x] 29-02-PLAN.md — Wave 1: weekly_reports drift table, schema v48, four sync/wipe registries, drift dump/generate
- [ ] 29-03-PLAN.md — Wave 1: gemini-analyze weekly_report kind (prompt, normalizer, per-day quota, corpus) + Deno tests
- [ ] 29-04-PLAN.md — Wave 1: opt-in NotificationSettings fields + Sunday dayOfWeekAndTime scheduler (id 5001) + payload constant

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 29-05-PLAN.md — Wave 2: OQ3 duplicate-week pull test, sync-registration + wipe tests
- [ ] 29-07-PLAN.md — Wave 2: versioned WeeklyReportPayload + section types + sanitised size-capped AI facts
- [ ] 29-08-PLAN.md — Wave 2: notifier/sync wiring, settings toggle + time row, privacy/GDPR docs
- [ ] 29-09-PLAN.md — Wave 2: WeeklyReportBackend (separate interface) + narrative service with typed failure kinds
- [ ] 29-10-PLAN.md — Wave 2: notification tap path (foreground, background queue, cold start) with no work in callbacks

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 29-06-PLAN.md — Wave 3: Supabase migration SQL (written, not applied) + parity test + WeeklyReportRepository (immutable snapshot)
- [ ] 29-11-PLAN.md — Wave 3: nutrition + training section calculators (pure, deterministic)
- [ ] 29-12-PLAN.md — Wave 3: correlation statements (RPT-05), recovery/physique calculators, TDEE shift + history queries
- [ ] 29-13-PLAN.md — Wave 3: measured section cards + distinct Herculex AI narrative card

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 29-14-PLAN.md — Wave 4: week inputs repository + WeeklyReportService (generate on open, narrative attempt-before-call)

**Wave 5** *(blocked on Wave 4 completion)*

- [ ] 29-15-PLAN.md — Wave 5: providers + app-lifetime de-duplicating controller (auto-once narrative, retry, opt-in gate)

**Wave 6** *(blocked on Wave 5 completion)*

- [ ] 29-16-PLAN.md — Wave 6: TDEE shift card — delta-preserving "Update my target" (OQ2, isolated, user-confirmed)
- [ ] 29-17-PLAN.md — Wave 6: history view, Analytics entry card, dashboard ready card

**Wave 7** *(blocked on Wave 6 completion)*

- [ ] 29-18-PLAN.md — Wave 7: report view (generate on open, frozen render) + router registration

**Wave 8** *(blocked on Wave 7 completion)*

- [ ] 29-19-PLAN.md — Wave 8: phase verification, gates, traceability and open-question list

**Wave 9** *(blocked on Wave 8 completion)*

- [ ] 29-20-PLAN.md — Wave 9: [BLOCKING, human-gated] apply Supabase migrations + deploy gemini-analyze + on-device UAT

---

## Deferred & Future Scope

- **Samsung Now Bar Live Update (Deferred to January):** Upgrade ongoing workout surface into a native Android 16 (API 36) `requestPromotedOngoing(true)` / `ProgressStyle` Live Update.
- **Buddy VS comparison (BUD-07):** Post-workout head-to-head comparison views.
- **Friends model (BUD-08):** Persistent social graph and invitations.
- **Challenges (BUD-09):** Goal-based peer challenges with deadlines.
- **Recipe URL import (PLAN-01)** & **Meal planner / grocery lists (PLAN-02)**.
- **Voice food entry (VOICE-01)**.
