# Phase 16: Exercise Programming Metadata & Discipline Taxonomy - Context

**Gathered:** 2026-09-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 16 delivers the catalog, database runtime, and domain eligibility structures with explicit difficulty levels, commonness tiers, discipline tags, prerequisites, scaling groups, and basic weights profile constraints. Downstream generator phases (Phases 17–22) consume this metadata to enforce hard guardrails without silent fallback or inappropriate exercise prescriptions.

</domain>

<decisions>
## Implementation Decisions

### Catalog Storage & Schema Architecture
- **D-01:** Curated JSON asset (`assets/data/exercise_programming_metadata.json`) serves as the authoring source of truth. At import time, `ExerciseImporter` populates first-class columns on Drift `ExerciseCatalog` via schema v41 migration (`programmingDifficulty`, `programmingCommonness`, `disciplines`, `prerequisiteSlugs`, `scalingGroup`, `scalingOrder`, `competitionAnchor`, `specializationTags`).
- **D-02:** Array/list attributes (`disciplines`, `prerequisiteSlugs`, `specializationTags`) are stored as JSON-encoded text columns on `ExerciseCatalog`, maintaining consistency with existing `allowedTrainingStyles` and `requiredEquipmentKeys`.
- **D-03:** Scaling ladders use dedicated columns `scalingGroup` (TEXT, nullable) and `scalingOrder` (INTEGER, nullable) on `ExerciseCatalog` for fast indexed SQL ordering and traversal.
- **D-04:** `programmingCommonness` is expanded to the 4 explicit tiers: `basic`, `common`, `specialty`, and `manualOnly`. Existing uncurated and custom rows default conservatively to `manualOnly`.

### Prerequisite Verification Model
- **D-05:** Prerequisite checks follow a dual-check model: a prerequisite is met if either (a) the user's `experienceLevel` equals or exceeds the movement's difficulty, OR (b) the user has verified logged completion of the prerequisite movement in `workout_exercises` history.
- **D-06:** Strict hard gate: If any `prerequisiteSlug` is unverified, the movement is disqualified from automatic candidate pools before scoring. Hard filters are never relaxed.
- **D-07:** Prerequisite pairings focus on foundational compound movements (e.g., muscle-up requires pull-up and dips; clean & jerk requires front squat and overhead press; planche requires push-up and dips).
- **D-08:** Movement-family resolution: Prerequisite satisfaction accepts either the exact exercise slug OR any variant sharing the canonical `movementSlug` (e.g. wide-grip pull-up satisfies pull-up).

### Discipline Taxonomy & Commonness Tiers
- **D-09:** Exactly 5 canonical disciplines are defined: `weights`, `calisthenics`, `crossfit`, `olympic`, `gpp`. Exercises can carry multiple discipline tags.
- **D-10:** `basicWeights` training style enforces a two-layer hard filter: modality must be standard gym equipment (`barbell`, `dumbbell`, `cable`, `machine_plate`, `machine_selectorized`, `bodyweight`) AND `programmingCommonness` must be `basic` or `common`, barring specialty bars (SSB, Swiss bar, axle, trap bar, cambered), boards, pins, and chains.
- **D-11:** Strict difficulty ceiling: Novice athletes receive only `novice`-difficulty movements across all slots, with zero silent relaxation for compound or accessory work.
- **D-12:** `competitionAnchor` and `specializationTags` (e.g., `squat-bottom`, `bench-lockout`) are modeled in schema v41 and curated for primary movements in Phase 16 to support downstream Phase 22.

### Scaling Groups & Progressive Regression
- **D-13:** Ascending difficulty numbering: `scalingOrder = 1` represents the easiest/entry-level regression (e.g. assisted pull-up = 1, negative = 2, strict pull-up = 3, muscle-up = 4); automated regression steps downwards.
- **D-14:** Comprehensive scaling chains are curated for both gymnastics/calisthenics progressions (`vertical_pull`, `horizontal_push`, `dips`, `handstand_pushup`, `pistol_squat`) and foundational weight ladders (`squat`, `hinge`).
- **D-15:** Dedicated `ExerciseScalingResolver` domain service encapsulates scaling ladder traversal, returning the highest safe candidate or null with an explainable rationale.
- **D-16:** Strict group boundary: If no movement on a scaling ladder matches available gym equipment, return null / no safe candidate rather than silently crossing modalities or movement patterns.

### the agent's Discretion
- Python tooling updates in `tool/build_exercises.py` and `tool/derive_movements.py` to keep json assets in sync.
- Specific default fallback values in Drift table definition for uncurated legacy rows (`manualOnly`, `advanced`, empty lists).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & Blueprint Specs
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` §5 (Faza 1 — katalog zahtevnosti, običajnosti in disciplin) — Architecture blueprint defining difficulty, commonness, disciplines, and prerequisites.
- `.planning/REQUIREMENTS.md` §2 (META-01–04) — Authoritative requirements for Phase 16.
- `.planning/ROADMAP.md` (Phase 16) — Milestone phase goal and success criteria.

### Database & Schema
- `lib/data/local/tables.dart` (lines 28–152) — `ExerciseCatalog` Drift table definition and metadata columns.
- `lib/data/local/database.dart` (lines 90–190, 918–1085) — Schema versions and `onUpgrade` migrations up to v40.
- `lib/data/local/exercise_importer.dart` — JSON import logic, movement alias resolution, and metadata mapping.

### Programming Domain & Eligibility
- `lib/features/programs/domain/exercise_programming_eligibility.dart` — Hard filtering rules for experience, commonness, and style.
- `lib/features/programs/domain/programming_models.dart` — `ExperienceLevel`, `TrainingStyle`, and program generation parameters.

### Data Assets
- `assets/data/exercise_programming_metadata.json` — Hand-curated programming metadata overlay.
- `assets/data/movements.json` — Canonical movement families and equipment options.
- `assets/data/exercises.json` — Bundled exercise catalogue.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ExerciseProgrammingEligibility`: Static eligibility evaluator, already hardened in Phase 15 with difficulty rank and style filtering.
- `ExerciseBiomechanics`: Biomechanical force and plane derivation.
- `_requiredEquipmentKeys` in `exercise_importer.dart`: Pattern matcher identifying specialty bars (`safety_squat_bar`, `swiss_bar`, `cambered_bar`, `axle_bar`, `trap_bar`, etc.).
- `ExerciseCatalogCompanion`: Drift companion used for idempotent inserts/updates.

### Established Patterns
- Conservative table defaults: Uncurated rows default to `manualOnly` and `advanced`, ensuring old exercises never enter automated generation accidentally.
- Migration idempotency: `addIfMissing` checks table and column existence via `pragma_table_info` before executing `m.addColumn`.
- In-memory test database: `openTestDatabase()` in `test/support/test_database.dart` builds an in-memory SQLite instance for fast unit testing.

### Integration Points
- `ExerciseImporter.runFromJson`: Reads `exercise_programming_metadata.json` and updates `ExerciseCatalog`.
- `ExerciseCatalog`: SQLite table storing metadata queried by `SmartProgramPlanner`.
- `ExerciseScalingResolver`: New domain component in `lib/features/programs/domain/` to be called during candidate filtering and regression.

</code_context>

<specifics>
## Specific Ideas

- Muscle-up progression ladder: `band-assisted-pull-up` (1) → `negative-pull-up` (2) → `pull-up` (3) → `chest-to-bar-pull-up` (4) → `bar-muscle-up` (5) → `ring-muscle-up` (6).
- Planche progression ladder: `incline-push-up` (1) → `standard-push-up` (2) → `decline-push-up` (3) → `pseudo-planche-push-up` (4) → `tuck-planche` (5) → `full-planche` (6).
- Specialty bars: Safety Squat Bar, Swiss/Football bar, Cambered bar, Duffalo bar, Axle bar, and Trap bar must be completely excluded from `basicWeights`.

</specifics>

<deferred>
## Deferred Ideas

- Phase 17: Unified `ProgramGenerationRequest`, deterministic candidate scoring, and selection rationales (`SelectionExplanation`).
- Phase 18: `SlotPrescriptionCodec`, `WorkoutDurationEstimator`, and `WarmupResolver`.
- Phase 21: Dedicated CrossFit blueprints (warmup, skill, metcon, cooldown).
- Phase 22: Primary lift specialization engine leveraging `competitionAnchor` and `specializationTags`.

</deferred>

---

*Phase: 16-exercise-programming-metadata-discipline-taxonomy*
*Context gathered: 2026-09-13*
