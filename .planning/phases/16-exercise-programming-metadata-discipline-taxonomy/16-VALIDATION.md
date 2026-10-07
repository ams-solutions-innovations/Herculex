---
phase: 16
slug: exercise-programming-metadata-discipline-taxonomy
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-13
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test (`flutter_test`) with in-memory SQLite (`openTestDatabase()`) and Drift `SchemaVerifier` |
| **Config file** | `pubspec.yaml` |
| **Quick run command** | `flutter test test/exercise_programming_metadata_test.dart test/exercise_programming_eligibility_test.dart` |
| **Full suite command** | `flutter test test/migration_test.dart test/exercise_programming_metadata_supabase_migration_test.dart test/exercise_programming_metadata_test.dart test/exercise_programming_eligibility_test.dart test/exercise_scaling_resolver_test.dart test/smart_program_planner_test.dart` |
| **Estimated runtime** | ~20 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/exercise_programming_metadata_test.dart test/exercise_programming_eligibility_test.dart`
- **After every plan wave:** Run `flutter test test/migration_test.dart test/exercise_programming_metadata_supabase_migration_test.dart test/exercise_programming_metadata_test.dart test/exercise_programming_eligibility_test.dart test/exercise_scaling_resolver_test.dart test/smart_program_planner_test.dart`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 25 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | META-01 | — | Schema v41 columns and scaling index exist with conservative defaults | unit / migration | `flutter test test/migration_test.dart` | ✅ | ⬜ pending |
| 16-01-02 | 01 | 1 | META-01 | — | Supabase migration mirrors v41 columns and commonness check constraint | contract | `flutter test test/exercise_programming_metadata_supabase_migration_test.dart` | ❌ W0 | ⬜ pending |
| 16-01-03 | 01 | 1 | META-01 | — | Metadata JSON asset packaged in `pubspec.yaml` flutter.assets | asset test | `flutter test test/exercise_programming_metadata_test.dart` | ✅ | ⬜ pending |
| 16-02-01 | 02 | 2 | META-01 | — | Ingests 5 canonical disciplines, 4 commonness tiers, and specialization anchors | integration | `flutter test test/exercise_programming_metadata_test.dart` | ✅ | ⬜ pending |
| 16-02-02 | 02 | 2 | META-03 | — | `basicWeights` strictly bars specialty bars, boards, pins, chains, and uncurated rows | unit | `flutter test test/exercise_programming_eligibility_test.dart` | ❌ W0 | ⬜ pending |
| 16-03-01 | 03 | 3 | META-02 | — | Dual-check prerequisite gate disqualifies unverified movements before scoring | unit | `flutter test test/exercise_programming_eligibility_test.dart` | ❌ W0 | ⬜ pending |
| 16-03-02 | 03 | 3 | META-04 | — | `ExerciseScalingResolver` steps down ladder and returns `noSafeCandidate` on exhaustion | unit | `flutter test test/exercise_scaling_resolver_test.dart` | ❌ W0 | ⬜ pending |
| 16-03-03 | 03 | 3 | META-01..04 | — | Full generator regression suite passes with zero unexpected regressions | regression | `flutter test test/smart_program_planner_test.dart` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/exercise_programming_metadata_supabase_migration_test.dart` — verifies Supabase migration parity for v41
- [ ] `test/exercise_programming_eligibility_test.dart` — tests for `basicWeights` two-layer hard gate, novice difficulty ceiling, and prerequisite dual-check
- [ ] `test/exercise_scaling_resolver_test.dart` — tests for `ExerciseScalingResolver` ladder traversal and strict boundary enforcement

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | META-01..04 | N/A | All phase behaviors have automated test suite verification. |

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 25s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** verified 2026-09-13
