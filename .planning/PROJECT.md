# Herculex

## What This Is

Herculex is a Flutter fitness application built on an offline-first architecture with local-authoritative Drift/SQLite databases, Supabase cloud synchronization, nutrition tracking, workout execution, live buddy training, deterministic Hercul coaching, and anthropometric ergonomics.

## Active Milestone: v2.0 — Training Programs Revamp, Dream Physique & Gamification

**Defined:** 2026-09-13  
**Blueprint:** [`docs/training-programs-physique-gamification-plan-2026-09-10.md`](../docs/training-programs-physique-gamification-plan-2026-09-10.md)  
**Core Value:** Safe, deterministic, and explainable training program generation; flexible program and wave editing; persistent Dream Physique goals with phased nutrition plans; and an authentic 15-tier XP gamification system.

### Key Objectives

1. **Deterministic Program Generation:** Unified `ProgramGenerationRequest`, hard prerequisite & equipment filters before scoring, elimination of unexpected 8×3 Dynamic Effort for beginners, and explainable selection rationales.
2. **Exercise Taxonomy & Metadata:** Explicit curation of `difficultyLevel`, `commonnessTier`, `disciplines`, `prerequisiteSlugs`, and `basicWeights` filtering.
3. **True Program & Wave Editor:** Week dropdown, exercise wave strip, and scoped exercise substitutions (`thisWave`, `thisAndFutureWaves`, `entireBlock`) without altering frozen started workouts.
4. **Prescription Fidelity & Time Budgeting:** Unified `SlotPrescriptionCodec` shared between preview, editor, and workout; automatic warmup calculation and realistic session time estimation.
5. **Specialized Tracks:** Dedicated CrossFit/GPP session blueprints (warmup, skill, metcon, cooldown) and Primary Lift Specialization (e.g. Squat Specialization with sticking point targetting).
6. **Persistent Dream Physique:** Synchronized goal and assessment history, locally encrypted/safe photo storage with EXIF stripping, and multi-phase nutrition roadmaps (`cut`, `maintain`, `recomp`, `bulk`).
7. **Idempotent 15-Rank Gamification:** Double-entry XP ledger keyed on verified workout/nutrition evidence, distinct from training experience, with progress explanations.
8. **Cloud Sync & Privacy Hardening:** Drift schemas, Supabase migrations, RLS isolation, complete account wipe, and structured JSON export.

### Constraints & Guiding Principles

- **No Silently Relaxed Filters:** If no safe exercise satisfies user constraints, the planner must return an explainable "no safe candidate" message rather than prescribing an unsafe or unsuitable movement.
- **Single Source of Truth:** The prescription shown in the preview must match the exact prescription executed in the workout session.
- **Privacy First:** Physique photos stay local by default; face blur/crop and EXIF stripping available before storage.
- **Zero Negative or Manipulative Gamification:** XP is never subtracted, cannot be earned through unhealthy food logging or extreme weight cuts, and rank never unlocks technically restricted exercises.

---

<details>
<summary>Archived Milestones</summary>

### Milestone v1.0: Nutrition & Workout Core (Shipped 2026-09-13)
- **Archive:** [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) | [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) | [v1.0-MILESTONE-AUDIT.md](v1.0-MILESTONE-AUDIT.md)
- Curated 44,913-food EU database in SQLite/FTS with exact string barcode matching.
- Basis-aware portions (100g, 100ml, legacy servings) and user-defined meal slots.
- Offline barcode verification & on-device OCR with Gemini review flow.
- Consolidated `TrainingSnapshot` effective load; soft-deleted records (`deletedAt`) excluded.
- Live Gym Buddy sharing protocol with Realtime broadcast & event replay.
- Exercise taxonomy with 51 new exercises and unit-preserving logging metrics (`durationSeconds`, `distanceM`, `calories`).
- Deterministic Hercul coaching rule engine (Normal / Honest 18+).
- Anthropometric ergonomics ratio calculator and movement-specific guidance.

</details>

---
*Last updated: 2026-09-13 after initiating Milestone v2.0*
