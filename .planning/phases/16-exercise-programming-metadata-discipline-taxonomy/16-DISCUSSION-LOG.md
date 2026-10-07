# Phase 16: Exercise Programming Metadata & Discipline Taxonomy - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-13
**Phase:** 16-exercise-programming-metadata-discipline-taxonomy
**Areas discussed:** Catalog Storage & Schema Architecture, Prerequisite Verification Model, Discipline Taxonomy & Commonness Tiers, Scaling Groups & Regression Strategy

---

## Catalog Storage & Schema Architecture

### Question 1: Storage and Query Architecture
| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid | Curated JSON asset as source of truth, imported into Drift ExerciseCatalog table columns via schema v41 migration for high-performance SQL filtering. | ✓ |
| Movements layer | Add programming metadata to assets/data/movements.json and denormalize down to exercises at import time. | |
| In-Memory / JSON-Only | Keep metadata purely in assets/data/exercise_programming_metadata.json loaded into an in-memory service at runtime without altering Drift schema. | |
| You decide | Agent chooses implementation | |

**User's choice:** Hybrid: Curated JSON asset as source of truth, imported into Drift ExerciseCatalog table columns via schema v41 migration for high-performance SQL filtering.

### Question 2: List/Array Attributes Storage in SQLite
| Option | Description | Selected |
|--------|-------------|----------|
| JSON-encoded text columns | disciplines, prerequisiteSlugs stored as JSON-encoded text columns on ExerciseCatalog — aligns with existing allowedTrainingStyles and requiredEquipmentKeys patterns. | ✓ |
| Normalized relation tables | exercise_disciplines, exercise_prerequisites referencing ExerciseCatalog.id with foreign keys. | |
| You decide | Agent chooses implementation | |

**User's choice:** JSON-encoded text columns (disciplines, prerequisiteSlugs) on ExerciseCatalog — aligns with existing allowedTrainingStyles and requiredEquipmentKeys patterns.

### Question 3: Scaling Groups and Progression Modeling
| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated columns on ExerciseCatalog | scalingGroup TEXT, scalingOrder INT — enables direct SQL ordering and instant regression ladder traversal. | ✓ |
| Separate JSON dictionary | Defined in exercise_programming_metadata.json as named scaling chains. | |
| You decide | Agent chooses implementation | |

**User's choice:** Dedicated columns on ExerciseCatalog (scalingGroup TEXT, scalingOrder INT) — enables direct SQL ordering and instant regression ladder traversal.

### Question 4: Commonness Tier Schema Mapping
| Option | Description | Selected |
|--------|-------------|----------|
| Expand programmingCommonness | Support 4 explicit tiers: 'basic', 'common', 'specialty', 'manualOnly' (with uncurated rows defaulting conservatively to 'manualOnly'). | ✓ |
| Distinct commonnessTier column | Preserve legacy programmingCommonness for backward compatibility. | |
| You decide | Agent chooses implementation | |

**User's choice:** Expand programmingCommonness to the 4 explicit tiers: 'basic', 'common', 'specialty', 'manualOnly' (with uncurated rows defaulting conservatively to 'manualOnly').

---

## Prerequisite Verification Model

### Question 1: Prerequisite Verification Definition
| Option | Description | Selected |
|--------|-------------|----------|
| Dual-check | Met if user's experience level satisfies difficulty OR user has verified logged completion of the prerequisite slugs in workout history. | ✓ |
| Strict workout history only | Prerequisite movement must exist with completed sets in user's logged workout sessions. | |
| User Profile declaration | User explicitly marks mastered skills/prerequisites in their training profile settings. | |
| You decide | Agent chooses implementation | |

**User's choice:** Dual-check: Met if user's experience level satisfies difficulty OR user has verified logged completion of the prerequisite slugs in workout history.

### Question 2: Hard Gate vs Soft Penalty for Prerequisite Failures
| Option | Description | Selected |
|--------|-------------|----------|
| Strict Hard Gate | If any prerequisiteSlug is unverified, movement is completely disqualified from candidate pools before scoring. | ✓ |
| Soft scoring penalty | Movement remains eligible but receives severe negative score penalty. | |
| You decide | Agent chooses implementation | |

**User's choice:** Strict Hard Gate: If any prerequisiteSlug is unverified, movement is completely disqualified from candidate pools before scoring.

### Question 3: Prerequisite Pairings Structure
| Option | Description | Selected |
|--------|-------------|----------|
| Standard functional compound movements | Base foundational compound movements (e.g., Muscle-Up requires pull-up and dips; Clean & Jerk requires front squat and overhead press). | ✓ |
| Strict ladder progression | Each advanced movement requires its immediate prior step on the scaling ladder. | |
| You decide | Agent chooses implementation | |

**User's choice:** Standard functional strength prerequisites: Base foundational compound movements (e.g., Muscle-Up requires pull-up and dips; Clean & Jerk requires front squat and overhead press).

### Question 4: Movement-Family Variant Resolution
| Option | Description | Selected |
|--------|-------------|----------|
| Movement-family resolution | Satisfied by either the exact exercise slug OR any variant sharing the canonical movementSlug (e.g. wide-grip pull-up satisfies pull-up). | ✓ |
| Exact slug matching only | Only the precise prerequisiteSlug counts toward verification. | |
| You decide | Agent chooses implementation | |

**User's choice:** Movement-family resolution: Satisfied by either the exact exercise slug OR any variant sharing the canonical movementSlug (e.g. wide-grip pull-up satisfies pull-up).

---

## Discipline Taxonomy & Commonness Tiers

### Question 1: Canonical Disciplines Values
| Option | Description | Selected |
|--------|-------------|----------|
| Exact 5 canonical disciplines | 'weights', 'calisthenics', 'crossfit', 'olympic', 'gpp' (exercises can carry multiple disciplines). | ✓ |
| Expanded sub-disciplines | 'powerlifting', 'bodybuilding', 'strongman', 'mobility'. | |
| You decide | Agent chooses implementation | |

**User's choice:** Exact 5 canonical disciplines: 'weights', 'calisthenics', 'crossfit', 'olympic', 'gpp' (exercises can carry multiple disciplines).

### Question 2: basicWeights Training Style Boundaries
| Option | Description | Selected |
|--------|-------------|----------|
| Two-layer hard filter | Modality must be standard gym equipment AND commonnessTier must be 'basic' or 'common' (barring specialty bars, boards, pins, and chains). | ✓ |
| Equipment-only filter | Allow any commonness tier as long as equipment matches standard barbell, dumbbell, cable, or machine. | |
| You decide | Agent chooses implementation | |

**User's choice:** Two-layer hard filter: Modality must be standard gym equipment AND commonnessTier must be 'basic' or 'common' (barring specialty bars, boards, pins, and chains).

### Question 3: difficultyLevel Ceiling Interaction
| Option | Description | Selected |
|--------|-------------|----------|
| Strict ceiling | Novices receive only novice-difficulty movements across all slots, with zero silent relaxation for compound or accessory work. | ✓ |
| Compound-only ceiling | Enforce strict difficulty ceiling for primary/compound slots, but permit intermediate isolation accessories. | |
| You decide | Agent chooses implementation | |

**User's choice:** Strict ceiling: Novices receive only novice-difficulty movements across all slots, with zero silent relaxation for compound or accessory work.

### Question 4: Specialization & Competition Anchor Modeling
| Option | Description | Selected |
|--------|-------------|----------|
| Include in Phase 16 | Model competitionAnchor and specializationTags now so the catalog taxonomy is complete for downstream specialization. | ✓ |
| Defer to Phase 22 | Keep Phase 16 strictly focused on META-01–04. | |
| You decide | Agent chooses implementation | |

**User's choice:** Include in Phase 16 schema & curation: Model competitionAnchor and specializationTags now so the catalog taxonomy is complete for downstream specialization.

---

## Scaling Groups & Regression Strategy

### Question 1: scalingOrder Numbering Convention
| Option | Description | Selected |
|--------|-------------|----------|
| Ascending difficulty | 1 = entry-level/easiest (e.g. assisted pull-up = 1, negative = 2, strict pull-up = 3, muscle-up = 4); regression steps downwards. | ✓ |
| Descending difficulty | 1 = apex/hardest movement, larger integers represent easier regressions. | |
| You decide | Agent chooses implementation | |

**User's choice:** Ascending difficulty: 1 = entry-level/easiest (e.g. assisted pull-up = 1, negative = 2, strict pull-up = 3, muscle-up = 4); regression steps downwards.

### Question 2: Scaling Groups Scope
| Option | Description | Selected |
|--------|-------------|----------|
| Comprehensive set | Curate both calisthenics skill progressions (vertical pull, horizontal push, dips, handstand push-up) and foundational weight ladders (squat, hinge). | ✓ |
| Calisthenics skill progressions only | Focus scaling groups strictly on gymnastics/bodyweight movements where beginners fail prerequisites. | |
| You decide | Agent chooses implementation | |

**User's choice:** Comprehensive set: Curate both calisthenics skill progressions (vertical pull, horizontal push, dips, handstand push-up) and foundational weight ladders (squat, hinge).

### Question 3: Architecture for Progressive Regression Resolution
| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated ExerciseScalingResolver | Independent domain resolver that steps down the scaling ladder and returns the highest safe candidate, or null with explanation. | ✓ |
| Inline in SmartProgramPlanner | Keep regression traversal embedded inside the generator planning loop. | |
| You decide | Agent chooses implementation | |

**User's choice:** Dedicated ExerciseScalingResolver: Independent domain resolver that steps down the scaling ladder and returns the highest safe candidate, or null with explanation.

### Question 4: Equipment Exhaustion on Scaling Ladders
| Option | Description | Selected |
|--------|-------------|----------|
| Strict group boundary | If no movement on the scaling ladder fits available equipment, return null / no safe candidate (never silently cross modalities). | ✓ |
| Pattern fallback | Fall back to matching movementPattern if all scaling ladder items lack equipment. | |
| You decide | Agent chooses implementation | |

**User's choice:** Strict group boundary: If no movement on the scaling ladder fits available equipment, return null / no safe candidate (never silently cross modalities).

---

## the agent's Discretion
- Python tooling updates in tool/build_exercises.py and tool/derive_movements.py to keep json assets in sync.
- Conservative defaults in SQLite schema for uncurated legacy rows.

## Deferred Ideas
- Phase 17: Unified ProgramGenerationRequest, candidate scoring, and selection rationales.
- Phase 18: SlotPrescriptionCodec, duration estimation, and warmup scaling.
- Phase 21: Dedicated CrossFit blueprints.
- Phase 22: Primary lift specialization engine.
