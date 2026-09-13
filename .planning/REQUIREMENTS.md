# Requirements: Milestone v2.0 — Training Programs Revamp, Dream Physique & Gamification

**Defined:** 2026-09-13  
**Source Blueprint:** [`docs/training-programs-physique-gamification-plan-2026-09-10.md`](../docs/training-programs-physique-gamification-plan-2026-09-10.md)  
**Core Value:** Safe, deterministic, and explainable training program generation; flexible program and wave editing; persistent Dream Physique goals with phased nutrition; and an authentic 15-tier XP gamification system.

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
- [ ] **PLAN-03**: Core anchor movements remain guaranteed across block weeks rather than rotating out on affinity scoring.
- [ ] **PLAN-04**: Planner returns human-readable selection rationales (`SelectionExplanation`) for every chosen and excluded movement.

### 4. Time Budget, Warmups & Prescriptions (Phase 18)

- [ ] **PRES-01**: `SlotPrescription` uses a versioned JSON codec (`SlotPrescriptionCodec`) guaranteed byte-equivalent across review, editor, and workout.
- [ ] **PRES-02**: `WorkoutDurationEstimator` calculates realistic workout durations including warmups, rest intervals, and unilateral work.
- [ ] **PRES-03**: `WarmupResolver` automatically scales warmup sets according to planned target intensity and movement order.
- [ ] **PRES-04**: Advanced intensity techniques (failure, rest-pause, drop, myo-reps) are opt-in and barred from technical compound lifts.

### 5. Program & Wave Editor (Phase 19)

- [ ] **EDIT-01**: Program viewer renders single active week with dedicated Week dropdown and exercise wave indicators (`Week N of M`, `Wave X of Y`).
- [ ] **EDIT-02**: Exercise replacements offer scoped choices: `thisWave`, `thisAndFutureWaves`, or `entireBlock`.
- [ ] **EDIT-03**: Program edits never mutate or overwrite previously started or completed workout occurrences.
- [ ] **EDIT-04**: Periodization options (Linear, Concurrent, Westside, Block) display dedicated educational guides with 8-week examples.

### 6. Active Workout Shell & Calendar Execution Flow (Phase 20)

- [ ] **FLOW-01**: `KeyboardObstructionScope` manages keyboard visibility, animations, and hit-testing across shell and active workout screens.
- [ ] **FLOW-02**: `PlannedWorkoutPreviewView` renders full workout preview with exercise details without writing to the database.
- [ ] **FLOW-03**: Calendar entries correctly route to Preview & Start, Resume active session, or History detail based on status.

### 7. CrossFit & GPP Training Tracks (Phase 21)

- [ ] **CF-01**: CrossFit sessions structure into ordered blueprint segments (warmup, skill/strength, metcon, cooldown) with time caps.
- [ ] **CF-02**: CrossFit experience levels scale movement complexity and metcon formats (AMRAP, EMOM, For Time).
- [ ] **CF-03**: Full Body 2× + GPP split delivers dedicated conditioning sessions without unintended Dynamic Effort sets.

### 8. Primary Lift Strength Specialization (Phase 22)

- [ ] **SPEC-01**: Strength specialization targets user-selected lift (e.g. Squat) with current 1RM, target weight, and sticking point analysis (bottom, mid, lockout).
- [ ] **SPEC-02**: Specialization planner preserves anchor lift frequency while maintaining all non-target muscle groups above baseline maintenance volume.
- [ ] **SPEC-03**: Unrealistic target timelines generate realistic projected time horizons with warnings rather than aggressive programming.

### 9. Persistent Dream Physique & Multi-Phase Nutrition (Phase 23)

- [ ] **PHYS-01**: Dream Physique goals, assessments, and check-in history persist in synchronized local/remote tables.
- [ ] **PHYS-02**: Physique photos are stored in app-sandboxed local documents with EXIF stripped and optional facial blur.
- [ ] **PHYS-03**: Multi-phase nutrition roadmaps (`cut`, `maintain`, `recomp`, `maingain`, `bulk`) compute realistic deficit/surplus pacing.
- [ ] **PHYS-04**: Underage users and low-confidence visual assessments are barred from aggressive caloric deficits or surpluses.

### 10. Gamification & 15-Rank XP Ledger (Phase 24)

- [ ] **XP-01**: Double-entry idempotent `xp_events` ledger records verifiable points from completed workouts, PRs, and physique check-ins.
- [ ] **XP-02**: 15 Herculex ranks (`Novice I–V`, `Intermediate I–V`, `Advanced I–V`) reflect earned lifetime XP without manipulating generator eligibility.
- [ ] **XP-03**: Strength XP normalizes against historical bodyweight and canonical movement slugs using `TrainingSnapshot` effective load.
- [ ] **XP-04**: UI displays transparent progress breakdown, recent XP events, and upcoming rank requirements without negative gamification.

### 11. Cloud Sync, Privacy & Export Hardening (Phase 25)

- [ ] **SYNC-01**: Drift schemas and Supabase migrations support all v2.0 tables with strict foreign keys, outbox triggers, and owner-only RLS.
- [ ] **SYNC-02**: Local data wipe completely purges all v2.0 tables, XP ledgers, and physical image assets.
- [ ] **SYNC-03**: Full structured JSON export packages all workout, program, physique, and gamification history for user download.

---

## Traceability

| Requirement | Phase | Status |
|---|---:|---|
| FIX-01–04 | 15 | Pending |
| META-01–04 | 16 | Pending |
| PLAN-01–04 | 17 | Pending |
| PRES-01–04 | 18 | Pending |
| EDIT-01–04 | 19 | Pending |
| FLOW-01–03 | 20 | Pending |
| CF-01–03 | 21 | Pending |
| SPEC-01–03 | 22 | Pending |
| PHYS-01–04 | 23 | Pending |
| XP-01–04 | 24 | Pending |
| SYNC-01–03 | 25 | Pending |
