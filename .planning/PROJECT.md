# Herculex

## What This Is

Herculex is a Flutter fitness application with offline-first architecture, local-authoritative SQLite/Drift databases, Supabase cloud synchronization, nutrition tracking, workout execution, live buddy training, deterministic coaching, and anthropometric ergonomics.

## Current State (Shipped: Milestone v1.0)

**Version Shipped:** `v1.0` (2026-09-13)  
**Archive:** [.planning/milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) | [.planning/milestones/v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) | [Audit Report](v1.0-MILESTONE-AUDIT.md)

### Shipped Capabilities
- **Local-First Nutrition & Catalogue:** Curated 44,913-food EU database in SQLite/FTS with exact string barcode matching and reference basis preservation.
- **Portions & Meal Slots:** Grams, ml, and labelled serving scalers; user-configurable meal slot CRUD with daily micronutrient ledger.
- **Capture Hardening & OCR:** GTIN/EAN/UPC check-digit validation, manual fallback, on-device Latin label OCR with Gemini fallback and confirmation review.
- **Analytics Correctness:** Consolidated `TrainingSnapshot.load` effective load; soft-deleted records (`deletedAt`) excluded across all 8 tables.
- **Gym Buddy Protocol:** Real-time two-device workout collaboration via Supabase Realtime broadcast + durable event log; strict participant data isolation and cold restart session resumption.
- **Taxonomy & Logging Metrics:** Movement hierarchy collapsing equipment variants; 51 new exercises (cardio, Olympic, CrossFit, mobility); unit-preserving metrics (`durationSeconds`, `distanceM`, `calories`) excluded from tonnage distortion.
- **Hercul Coaching Engine:** Deterministic rule engine over user signals, JSON rule corpus, dual tone (Normal / Honest 18+), dashboard insights card.
- **Anthropometric Ergonomics:** Limb proportion calculator (inseam, arm span, torso) with movement-specific variant guidance keyed to proportion ratios.

---

## Next Milestone Goals (v2.0 / v1.1)

**Focus:** Training Programs Revamp, Dream Physique, and Gamification System (see `docs/training-programs-physique-gamification-plan-2026-09-10.md`).

1. **Exercise Programming Metadata:** Add catalog difficulty, technical prerequisites, discipline tags, and user scaling levels.
2. **Safe Program Generator:** Single entry point with hard guardrails preventing unsuitable exercise prescriptions for beginners.
3. **Program & Block Editor:** Week/wave editor, explainable periodization, warmups, and advanced set methods (AMRAP, EMOM, dropsets, myo-reps).
4. **Specialization Tracks:** CrossFit/GPP engine, primary lift specialization (e.g. Squat Specialization).
5. **Dream Physique Integration:** Long-term physique goal tracking with multi-phase nutrition recommendations and muscle prioritization.
6. **XP & Gamification System:** 15-tier Herculex ranking system driven by verified workout and nutrition data.

---

<details>
<summary>Historical Context: Milestone v1.0 (Nutrition Completion)</summary>

### Core Value
A user can find or capture the correct food, choose a realistic portion, and log it with trustworthy nutrient totals in a few seconds.

### Constraints & Decisions
- **Stack:** Flutter + Drift/SQLite; preserve all existing diary records.
- **Data integrity:** Source workbook is source-of-truth input; no fabricated 100 g conversion for legacy servings.
- **Privacy:** On-device OCR/barcode where feasible; user confirmation on all captured data.
- **No API dependence:** Offline-first catalogue is authoritative.

</details>

---
*Last updated: 2026-09-13 after milestone v1.0 completion*
