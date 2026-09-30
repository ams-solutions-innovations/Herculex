---
phase: 27-herculex-ai-program-generation
plan: 09
subsystem: programs
tags: [dart, drift, riverpod, ai, gemini, program-brief, exception-translation]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation (plan 03)
    provides: "ProgramBrief.fromJson()/toJson() — the strict domain parser this service calls and persists"
  - phase: 27-herculex-ai-program-generation (plan 04)
    provides: "HerculexAiProgramBriefs drift table (schema v46) this service is the sole read/write path for"
  - phase: 27-herculex-ai-program-generation (plan 05)
    provides: "GeminiBackend.generateProgramBrief() — the (result, provenance) record this service calls"
provides:
  - "HerculexAiBriefService: generateBrief() (network + strict parse + AIP-05 exception translation), persistBrief() (sole write path to HerculexAiProgramBriefs, Clock-injected confirmedAt), watchBriefForProgram(programId) (live drift read)"
  - "HerculexAiBriefException(message, recoverable, isQuotaExhausted) — the failure-category contract downstream UI plans consume"
  - "herculexAiBriefServiceProvider (Riverpod Provider<HerculexAiBriefService>)"
affects: [27-11 (block_builder_view.dart calls generateBrief()/persistBrief() instead of touching drift directly), 27-12 (program_review_view.dart calls watchBriefForProgram()), 27-13]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Failure-category signal on a translated exception (isQuotaExhausted bool) instead of embedding final UI copy in the data-layer service — keeps AIP-05's two distinct degradation strings a UI-layer (plan 27-11) concern"
    - "Substring-based quota detection ('used up' / 'try again tomorrow') against the stripped error message, since there is no typed 429/quota exception class surfaced by GeminiBackend"

key-files:
  created:
    - lib/features/programs/data/herculex_ai_brief_service.dart
    - test/herculex_ai_brief_service_test.dart
  modified: []

key-decisions:
  - "HerculexAiBriefException carries message/recoverable/isQuotaExhausted (not final UI copy) — plan 27-11 picks the exact AIP-05 string from isQuotaExhausted, this service only classifies the failure"
  - "Quota detection substrings are 'used up' and 'try again tomorrow' (either alone is sufficient), matching the Edge Function's exact 429 message shape in supabase/functions/gemini-analyze/index.ts:283 verbatim"
  - "persistBrief()'s HerculexAiProgramBriefsCompanion.insert() takes programId/briefJson as plain required values (not Value(...)) — the plan's <action> pseudocode used Value(programId)/Value(briefJson), but the actual drift-generated Companion.insert constructor (verified by reading database.g.dart) makes required non-nullable, no-default columns plain required params, reserving Value<T> for optional/defaulted columns"

patterns-established:
  - "Data-layer AI services surface a failure-category enum/bool on their translated exception rather than embedding final UI copy, so the UI layer owns copywriting and the service stays UI-copy-agnostic"

requirements-completed: [AIP-02, AIP-03, AIP-05]

# Metrics
duration: ~45min
completed: 2026-09-30
---

# Phase 27 Plan 09: HerculexAiBriefService Summary

**HerculexAiBriefService — the sole generate/parse/persist/read seam for Herculex AI program briefs, modeled on DreamPhysiqueService's call-Gemini/parse-strictly/translate-failures shape, with an isQuotaExhausted failure-category signal so plan 27-11's UI can pick AIP-05's two distinct degradation messages without this service knowing UI copy.**

## Performance

- **Duration:** ~45 min
- **Completed:** 2026-09-30
- **Tasks:** 1/1 completed
- **Files modified:** 2 (1 new production file, 1 new test file)

## Accomplishments
- `HerculexAiBriefService.generateBrief({profileInputs, userNote})` calls `GeminiBackend.generateProgramBrief`, parses the result via `ProgramBrief.fromJson`, and translates every failure mode (unconfigured, network, quota-exhausted, malformed JSON) into a `HerculexAiBriefException` — never a raw technical exception string reaches the caller (T-27-13).
- Malformed-JSON failures get a distinct, dedicated message ("Herculex AI returned an incomplete brief. Try generating again.") mirroring `DreamPhysiqueService`'s exact precedent for the same failure class, so the UI can tell "backend unreachable" apart from "backend responded but the brief didn't parse."
- Quota-exhausted failures are detected by substring match (`'used up'` / `'try again tomorrow'`) against the stripped error text — the exact wording the Edge Function's real 429 response uses (`supabase/functions/gemini-analyze/index.ts:283`) — and set `isQuotaExhausted: true` on the thrown exception, distinguishing them from the generic offline/unconfigured case for plan 27-11's two-message AIP-05 UI contract.
- `HerculexAiBriefException` copies `DreamPhysiqueAnalysisException`'s exact shape (`message`, `recoverable` default `true`, `toString() => message`) plus one addition: `isQuotaExhausted` (default `false`) — the failure-category signal, not final UI copy, per the plan's explicit preference for that cleaner separation.
- `persistBrief({programId, brief, provenance})` is the only write path to `HerculexAiProgramBriefs` in this phase (confirmed by grep — zero other matches in `lib/features/programs/`), writing `brief.toJson()` as `briefJson`, `source: 'herculex_ai'`, `knowledgeVersion`/`modelVersion` from `provenance`, and `confirmedAt` from the injected `Clock` (never `DateTime.now()` directly, per CLAUDE.md's Clock rule).
- `watchBriefForProgram(programId)` returns a live `Stream<HerculexAiProgramBriefData?>` — `watchSingleOrNull()` on `programId == ? AND active == true`, ordered `confirmedAt DESC`, limited to 1 — mirroring `_loadDreamPhysiquePriorities()`'s existing query shape but as a stream, per the house rule preferring `StreamProvider` over `FutureProvider` for drift reads.
- `herculexAiBriefServiceProvider` wires `geminiBackendProvider` + `appDatabaseProvider` + `clockProvider` into the service, matching `dreamPhysiqueServiceProvider`'s existing pattern.

## Task Commits

1. **Task 1: HerculexAiBriefService - generate, parse, persist, read, and AIP-05 exception translation** - `77add23` (feat)

**Plan metadata:** this commit (docs: complete plan).

## Files Created/Modified
- `lib/features/programs/data/herculex_ai_brief_service.dart` - `HerculexAiBriefException`, `HerculexAiBriefService` (generateBrief/persistBrief/watchBriefForProgram), `herculexAiBriefServiceProvider`
- `test/herculex_ai_brief_service_test.dart` - 7 tests: valid parse, unconfigured-failure translation, quota-exhausted detection, malformed-JSON distinct message, persistBrief row/provenance/Clock assertions, watchBriefForProgram newest-first and null-when-absent

## Decisions Made
See `key-decisions` in frontmatter. The one implementation-detail deviation from the plan's literal `<action>` pseudocode: `HerculexAiProgramBriefsCompanion.insert()`'s generated constructor (verified by reading `database.g.dart`) takes `programId`/`briefJson` as plain required `int`/`String` params, not `Value(programId)`/`Value(briefJson)` as the plan's pseudocode suggested — drift only wraps optional/defaulted columns in `Value<T>` for `.insert()`. This is a mechanical correction to match the actual generated API, not a design change.

## Deviations from Plan

None requiring a deviation rule. The `Value(...)` vs plain-value correction above was resolved by reading the generated companion class directly (per the task's own `<read_first>` guidance implying checking generated shapes) rather than guessing from the plan's illustrative pseudocode — normal implementation-detail resolution, not a Rule 1-4 deviation.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **`HerculexAiBriefException` contract for plans 27-11/27-12/27-13:** fields `message` (String, non-technical), `recoverable` (bool, default `true`), `isQuotaExhausted` (bool, default `false`). Plan 27-11's UI picks between AIP-05's two degradation copy strings based on `isQuotaExhausted`; the malformed-JSON case always has `isQuotaExhausted: false` and the fixed message `'Herculex AI returned an incomplete brief. Try generating again.'`.
- **`watchBriefForProgram(int programId)` return type:** `Stream<HerculexAiProgramBriefData?>` (drift's generated row class for `HerculexAiProgramBriefs`, per its `@DataClassName` from plan 27-04) — emits `null` when no active brief exists for that program, otherwise the newest active row by `confirmedAt`.
- **`persistBrief` write contract:** `programId` (int, required), `brief` (ProgramBrief, required), `provenance` (Map<String, dynamic>, required — reads `knowledgeVersion`/`modelVersion` keys, both nullable/optional). Always sets `source: 'herculex_ai'` and `active: true`.
- Confirmed via grep: `lib/features/programs/data/herculex_ai_brief_service.dart` is the only production file in `lib/features/programs/` referencing `herculexAiProgramBriefs` — the "UI never touches drift directly" boundary holds for this table.
- No blockers for plans 27-10 (Supabase migration), 27-11, 27-12, or 27-13.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers (T-27-13, T-27-14) — no new trust boundary or surface introduced beyond the service itself.

## Known Stubs

None. Both write and read paths are fully wired to the real drift table; no placeholder/mock data.

## Self-Check: PASSED

- FOUND: lib/features/programs/data/herculex_ai_brief_service.dart
- FOUND: test/herculex_ai_brief_service_test.dart
- FOUND: 77add23 (Task 1 commit)

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*
