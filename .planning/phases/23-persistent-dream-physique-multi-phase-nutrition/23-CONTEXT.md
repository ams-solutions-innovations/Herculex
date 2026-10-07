# Phase 23: Persistent Dream Physique & Multi-Phase Nutrition - Context

**Gathered:** 2026-10-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Turn Dream Physique from a SharedPreferences summary (capped at 20 entries) plus local-only `ProgressPhotos` into a persistent, synced goal with assessment/check-in history, private sandboxed photos (EXIF stripped, optional face blur), structured multi-phase nutrition roadmaps (`cut`, `maintain`, `recomp`, `maingain`, `bulk`) with realistic tempo, underage/low-confidence guardrails, and a progress screen (active phase, roadmap position, charts, 7-day check-in cap, confidence-banded verdict). Requirements: PHYS-01–08.

</domain>

<decisions>
## Implementation Decisions

### Roadmap shape & phase transitions
- **D-01:** The multi-phase roadmap is **generated deterministically, then editable**. The planner proposes phases from BF gap, weight and age (extending `DreamPhysiqueNutritionRecommender`). The user may reorder, resize or delete phases before accepting.
- **D-02:** Phase advancement is **prompt + user confirms**. When exit criteria are met (target weight/BF reached or planned duration elapsed) the app offers "move to next phase" with accept/postpone. Nothing changes calorie targets silently; consistent with the house rule and Phase 28 D-10.
- **D-03:** **One active goal at a time, history kept.** Starting a new goal archives the previous one with its assessments and photos. The 7-day check-in cap (PHYS-06) is per goal.
- **D-04:** Tempo comes from the **existing `DietPhaseCalculator` presets** (cut 20%, bulk 10%, maingain +150 kcal), **capped by a % bodyweight/week ceiling**. Tempo realism is derived from that. No new training-level tempo model this phase.

### Minor & low-confidence guardrails (PHYS-04)
- **D-05:** **Under 18 cannot cut or bulk.** Only maintain, recomp and small-surplus maingain are offered; the UI explains why and suggests maintenance. Profile has only `ageYears` (no DOB), so a **missing age is treated as restricted** until entered.
- **D-06:** A visual assessment is **low-confidence when the AI returns a low label or a wide confidence band**. Low confidence restricts to maintain/recomp and shows a "log measurements to refine" hint. The guardrail lives in the deterministic domain layer, not the UI. Aligns with Phase 28's PHYS-04 stance.

### Photo storage, privacy & migration (PHYS-01, PHYS-02)
- **D-07:** Optional facial blur is **on-device via `google_mlkit_face_detection`** (new dependency; the repo already uses mlkit text recognition). Blur is applied on save and the unblurred face is never stored. EXIF is always stripped.
- **D-08:** Existing `ProgressPhotos` rows and the SharedPreferences summary are **migrated into an initial goal**, stripping EXIF on copy; originals are removed only after a successful copy. The 20-entry summary history becomes real rows.
- **D-09:** Sync is **metadata only, never image bytes**: goals, assessments, roadmap phases and photo rows (path, pose, date) sync; files stay in the app sandbox.

### Progress screen & check-in UX (PHYS-05–08)
- **D-10:** The progress screen is a **new route** (`AppRoutes`/`AppPaths` constant) linked from the existing Dream Physique summary card in Profile. It does not grow `dream_physique_view.dart` (1780 lines).
- **D-11:** The PHYS-07 verdict is a **three-state chip (on track / off track / inconclusive) + confidence range bar + one-line reason**, never a percentage. Any calorie action is a deep-link to the nutrition editor, never an automatic write.
- **D-12:** PHYS-08 charts are **stacked over the goal horizon with a 1M/3M/All toggle**, using `fl_chart`: bodyweight with the phase-target band, e1RM on canonical lifts, and training level (`ExperienceLevel` / strength standards, **not** the Phase 24 XP rank).
- **D-13:** When the 7-day cap blocks a check-in, the button is **disabled with "Next check-in available <date>"**. The repository still enforces the cap with a typed error as the real gate (PHYS-06).

### Claude's Discretion
- Exact % bodyweight/week ceilings, confidence-band width threshold, and the precise exit-criteria definitions per phase type.
- Table and column design (goals, assessments, roadmap phases, photo metadata), within the 5-chore schema checklist.
- Chart axis/styling details and the number of canonical lifts shown.

### Post-planning clarifications (2026-10-02, plan-check revision; genuine user answers)
- **D-08 clarification, legacy goal for photos-only users:** a user with legacy `ProgressPhotos` rows but no Dream Physique summary history still gets an initial goal. It is synthesized with `source = legacy_import`, no target (nullable `targetBfPercent` and `estimatedMonths`, empty style) and a single maintain-only roadmap proposal, so every legacy photo is migrated with EXIF stripped on copy and originals removed only after the copy commits. The migrator is state-based and idempotent: photos the Measurements screen writes to the legacy table later are appended to the same goal (each at most once). Routing Measurements capture through the new pipeline stays out of scope and is a recorded known limitation (Plan 17).
- **Low-confidence gate scope (RESEARCH Open Question 1):** low confidence gates roadmap generation and the deep-link preset phase only. The manual nutrition editor is gated by age only (D-05 stays global).
- **Training-level chart (RESEARCH Open Question 2):** the weekly `ExperienceLevel.recommend` approach is accepted. Its Intermediate cap (`understandsRirRpe` and `hasRunStructuredBlocks` have no history) is a recorded known limitation, not a defect to fix in this phase.
- **Over-cap files (user decision):** minimal, line-budgeted edits to `dream_physique_view.dart` (must not grow) and `nutrition_targets_view.dart` (net growth at most 40 lines) are accepted instead of splitting those files first; all new logic lives in new domain, application and presentation files. This supersedes the "split first if touched" guidance under Integration Points below and in UI-SPEC's "Edits to existing surfaces" for this phase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements and design
- `.planning/ROADMAP.md` (Phase 23) and `.planning/REQUIREMENTS.md` (PHYS-01–08)
- `docs/herculex-ai-plan-2026-09-27.md` §6 — Phase 23 extension (progress screen, weekly check-in, "training level is not XP rank", no false-precision percentage)
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` — source blueprint
- `docs/GDPR_ARTICLE_9_COMPLIANCE.md` — physique photos are special-category data
- `docs/ARCHITECTURE.md` and `CLAUDE.md` — layout rules, 5-chore schema checklist, 600-line limit

### Prior decisions that carry forward
- `.planning/phases/28-adaptive-tdee-activity-calibration/28-CONTEXT.md` — D-10 explicit accept/dismiss, PHYS-04 applies to adaptive TDEE
- `.planning/phases/26-herculex-ai-knowledge-base-brand-unification/` — `knowledgeVersion`/`modelVersion` provenance on AI results, per-kind quota failing closed (PHYS-07 verdict consumes this)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DietPhase` / `DietPhaseCalculator` (`lib/features/nutrition/domain/diet_phase.dart`): phase maths and presets.
- `DreamPhysiqueNutritionRecommender` / `PhysiqueNutritionDirection` (`lib/features/profile/domain/dream_physique_nutrition_recommendation.dart`): deterministic heuristic, deep-link only; basis for the roadmap generator.
- `DreamPhysiqueService.compareAndAnalyzePhysique` (`dream_physique_service.dart`): AI analysis; `DreamPhysiqueProgrammingProfile` carries `modelVersion`/`source`.
- `MeasurementsRepository` photo methods (`watchPhotos`, `getRecentPhotos`, insert/delete) and the `image` / `image_picker` packages.
- `fl_chart` (already in project); Phase 28 `tdee_*` domain files for bodyweight/energy trends.

### Established Patterns
- `ProgressPhotos` (`lib/data/local/tables.dart:1469`) is local-only with no goal FK; the summary lives in SharedPreferences (`dream_physique_summary_repository.dart`, schemaVersion 1, 20-entry cap).
- Drift is at **schemaVersion 46**; every bump is the five chores. New tables need `@DataClassName`, SyncColumns, `syncTableSpecs` entry and a `supabase/migrations/NNNN_*.sql`. Migrations 0015/0016 are still unapplied.
- Rate limits and guardrails belong in repositories/domain, not widgets. Time math goes through `Clock`.

### Integration Points
- Profile `Profile.ageYears` (nullable) for the minor guard.
- Nutrition targets editor (deep-link target, pre-set to the phase).
- `dream_physique_view.dart` (1780 lines, `dream_physique_priorities_view.dart` 608 lines): over the 600-line limit; avoid growing (minimal line-budgeted edits are accepted instead of a split, see Post-planning clarifications).
- Phase 27 consumes Dream Physique `musclePriorities` via the existing tuning seam; keep that contract intact.

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the decisions above; open to standard approaches within the house rules (deterministic primary, AI bounded, AI never writes to the database, user confirms).

</specifics>

<deferred>
## Deferred Ideas

- Concurrent multiple goals: rejected for this phase (D-03).
- Training-level-based tempo model (beginner vs advanced gain rates): possible future refinement of D-04.

</deferred>

---

*Phase: 23-Persistent Dream Physique & Multi-Phase Nutrition*
*Context gathered: 2026-10-02*
