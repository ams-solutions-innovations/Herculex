---
phase: 27-herculex-ai-program-generation
plan: 06
subsystem: ai
tags: [deno, typescript, supabase-edge-function, gemini, program-brief]

# Dependency graph
requires:
  - phase: 26-herculex-ai-knowledge-base-brand-unification
    provides: buildSystemInstruction()/knowledge_base.ts's programming segment and KNOWLEDGE_VERSION, unconsumed until this plan
  - phase: 27-herculex-ai-program-generation (plan 03)
    provides: ProgramBrief.fromJson's exact JSON shape (splitType/periodizationModel/dayRoles/musclePriorities/phaseIntent) this Edge Function's output must match
  - phase: 27-herculex-ai-program-generation (plan 05)
    provides: GeminiBackend.generateProgramBrief()'s 'kind':'program_brief' wire contract this case satisfies
provides:
  - "program_brief as a 9th GeminiKind with its own quota bucket, prompt, and normalizer"
  - "normalizeProgramBriefResult() — server-side first line of the D-02 two-tier defense"
  - "programBriefPrompt() — text-only, corpus-grounded prompt with the exercise-list/experienceLevel prohibitions"
affects: [27-09 (HerculexAiBriefService calls generateProgramBrief(), which invokes this kind end-to-end for the first time)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "First real consumer of buildSystemInstruction()/systemInstruction plumbing (built Phase 26, unused by all 8 prior kinds)"
    - "Reject-unknown-enum Set.has()-or-throw pattern extended to 3 new canonical id vocabularies (splitType, periodizationModel, dayRoles[].role), mirroring the existing canonicalProgrammingMuscleIds check"

key-files:
  created:
    - supabase/functions/gemini-analyze/program_brief_test.ts
  modified:
    - supabase/functions/gemini-analyze/index.ts
    - supabase/functions/gemini-analyze/prompts.ts

key-decisions:
  - "Quota tier: program_brief: 10/day (dream_physique tier), matching RESEARCH.md Open Question 1's recommendation for a text-only-but-token-heavy, low-frequency kind"
  - "normalizeProgramBriefResult() throws (never defaults) on any unknown splitType/periodizationModel/dayRoles[].role/muscleId — reuses the existing objectValue/requiredString/requiredNumber/confidenceValue/requiredPriority/stringArray helpers verbatim, adding only 3 new canonical id Sets"
  - "The prompt never asks for or accepts an experienceLevel field, copying dreamPhysiquePrompt's exact sidestep of the 5-tier/3-tier ExperienceLevel mapping question (Pitfall 5) rather than building collapse logic"
  - "case \"program_brief\" is text-only (images: []), combining rambler_food's no-image simplicity with dream_physique's normalize-before-return structure, per the plan's explicit interface guidance"

patterns-established:
  - "Any future text-only, corpus-grounded GeminiKind should pass systemInstruction: <segment> to generateJson() the same way — the plumbing was unused for 8 kinds; this is the reference example now"

requirements-completed: []  # AIP-02/AIP-03/AIP-05 remain partial — see Deviations; this plan delivers only the server-side half, matching the KB-02/KB-04/TDEE-05/27-03/27-04/27-05 partial-completion convention

# Metrics
duration: 40min
completed: 2026-09-30
---

# Phase 27 Plan 06: gemini-analyze `program_brief` Kind Summary

**Added `program_brief` as a 9th GeminiKind to the `gemini-analyze` Edge Function: a text-only, corpus-grounded prompt (first real consumer of Phase 26's `buildSystemInstruction()`), its own 10/day quota bucket, and a strict server-side normalizer that rejects any unknown enum value rather than defaulting.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 1 completed (single TDD task per the plan)
- **Files modified:** 3 (2 modified, 1 new test file)

## Accomplishments

- `programBriefPrompt(profileInputs, userNote)` added to `prompts.ts`: states the
  program-design-brief role, embeds `profileInputs` as JSON and `userNote` if present,
  reuses `dreamPhysiquePrompt`'s exact safety-prose sentence ("Do not choose a final
  exercise list or silently prescribe/change a program...") extended explicitly to
  forbid sets/reps/load/RPE/tempo/metcon-time-caps by name, copies the verbatim "Do not
  include an experienceLevel field anywhere" rule (Pitfall 5's resolution), and lists
  every canonical id for `splitType` (12 values), `periodizationModel` (5 values), and
  `dayRoles[].role` (4 values) plus the existing 19-value `musclePriorities` muscleId
  vocabulary.
- `index.ts`: `"program_brief"` added as the 9th `GeminiKind`; `profileInputs?:
  Record<string, unknown>` added to `GeminiRequest`; `program_brief: 10` added to
  `kindLimits` (env-overridable via `GEMINI_LIMIT_PROGRAM_BRIEF`); `"Program design
  briefs"` added to `kindDisplayNames` (flows automatically into the existing 429 quota
  message builder, no new code needed there); three new canonical id `Set`s
  (`canonicalSplitTypeIds`, `canonicalPeriodizationModelIds`,
  `canonicalDayStressRoleIds`) added near `canonicalProgrammingMuscleIds`, populated
  byte-for-byte from the Dart enums (see below); a new `case "program_brief":` block in
  the main switch — text-only (`images: []`), requires `payload.profileInputs` (400 if
  absent), calls `generateJson({ ..., systemInstruction: programming })` (the corpus
  injection Phase 26 built and no kind had used until now), normalizes the result, and
  returns `{ result, provenance: { modelVersion, knowledgeVersion: KNOWLEDGE_VERSION } }`.
- `normalizeProgramBriefResult(raw)` (exported for the test file) added near
  `normalizeProgrammingProfile`: validates `splitType`/`periodizationModel` via
  `requiredString` + `Set.has()`-or-throw, `dayRoles[]` (each entry via `objectValue` +
  `requiredNumber` for `dayIndex` + `Set.has()`-or-throw for `role` + `requiredString`
  for `focus`/`rationale`), `musclePriorities[]` reusing the exact
  `normalizeProgrammingProfile`-style mapping (byte-identical `canonicalProgrammingMuscleIds`
  check, `requiredPriority`/`confidenceValue`/`stringArray`), and `phaseIntent` via
  `requiredString`. Throws — never defaults — on any missing/unknown/malformed field.
- `program_brief_test.ts` (new, 6 Deno tests, follows `usage_test.ts`'s
  `assertEquals`/`Deno.test()` conventions plus `assertThrows`): valid-object round-trip,
  unknown `splitType` rejection, unknown `dayRoles[].role` rejection, unknown `muscleId`
  rejection, missing-`dayRoles` rejection, missing-`musclePriorities` rejection.

## Task Commits

1. **Task 1: programBriefPrompt() and normalizeProgramBriefResult()** — `2996747` (feat)

**Plan metadata:** this commit (docs: complete plan).

## Files Created/Modified
- `supabase/functions/gemini-analyze/prompts.ts` - added `programBriefPrompt()`
- `supabase/functions/gemini-analyze/index.ts` - `program_brief` GeminiKind, `profileInputs`
  request field, `kindLimits`/`kindDisplayNames` entries, 3 canonical id `Set`s, the
  `case "program_brief":` switch block, `normalizeProgramBriefResult()` (exported)
- `supabase/functions/gemini-analyze/program_brief_test.ts` (new) - 6 Deno unit tests for
  `normalizeProgramBriefResult()`'s reject-unknown-enum behavior

## Canonical id lists used (for 27-03's Dart parser parity cross-check)

**canonicalSplitTypeIds** (from `lib/features/programs/domain/split_template.dart`
`SplitType.id`):
```
full_body, full_body_linear, full_body_ab, full_body_ab_gpp, crossfit, upper_lower,
upper_lower_full_body, ppl, ab, abc, bro, custom
```

**canonicalPeriodizationModelIds** (from
`lib/features/programs/domain/periodization.dart` `PeriodizationModel.id`):
```
none, linear, concurrent, block, max_effort
```

**canonicalDayStressRoleIds** (from
`lib/features/programs/domain/programming_models.dart` `DayStressRole.id`):
```
intensity, volume, dynamic_technique, mixed
```

These were read directly from the current Dart enum source this session (not
re-derived from memory) and match plan 27-03's `SplitType.values`/
`PeriodizationModel.values`/`DayStressRole.values` iteration exactly, since both
sides enumerate the same enum's `.id` field. `canonicalProgrammingMuscleIds` (19
values) was reused unchanged from the existing Dream Physique code — no new list
needed there.

## Decisions Made
See `key-decisions` in frontmatter. No decisions required deviating from the plan's
`<interfaces>`/`<action>` guidance — the plan's prescribed shape (mirror
`normalizeProgrammingProfile`'s reject pattern, text-only case combining
`rambler_food`'s simplicity with `dream_physique`'s normalize-before-return structure,
10/day quota) was implemented as specified.

## Deviations from Plan

None — plan executed exactly as written.

## Verification

- `deno test supabase/functions/gemini-analyze/program_brief_test.ts` — 6/6 passing.
- `deno test supabase/functions/gemini-analyze/` (full directory: `index_test.ts`,
  `knowledge_base_test.ts`, `program_brief_test.ts`, `prompts_test.ts`, `usage_test.ts`)
  — 17/17 passing, 0 regressions in the 8 pre-existing kinds' tests.
- `deno check supabase/functions/gemini-analyze/index.ts
  supabase/functions/gemini-analyze/prompts.ts` — 0 type errors.
- `git diff --stat` confirms only additive changes to `index.ts`/`prompts.ts`: the one
  `-` line is the `GeminiKind` union's trailing `;` moving from `"rambler_food";` to
  `"rambler_food"` + a new `| "program_brief";` line — the 8 pre-existing kinds' cases,
  prompts, and normalizers are textually unchanged, confirming the acceptance
  criterion's grep check.

This plan is server-side only (TypeScript/Deno, `supabase/functions/gemini-analyze/`)
and touches no Dart/Flutter file — `flutter analyze`/`flutter test` were not run for
this plan's scope, consistent with the plan's own note that it is independent of the
other Wave 1 plans.

## Known Stubs

None. `program_brief` is a fully wired kind end-to-end on the server side — prompt,
quota, dispatch, and normalizer. The client-side caller (`HerculexAiBriefService`,
plan 27-09) does not exist yet, so this kind has no production traffic until then, but
that is expected sequencing, not a stub.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers (T-27-08 prompt
injection mitigation, T-27-09 tampering/reject-unknown-enum, T-27-10 quota DoS
isolation) — no new trust boundary or surface was introduced beyond what the plan
anticipated.

## Self-Check: PASSED

- FOUND: supabase/functions/gemini-analyze/index.ts
- FOUND: supabase/functions/gemini-analyze/prompts.ts
- FOUND: supabase/functions/gemini-analyze/program_brief_test.ts
- FOUND: 2996747 (Task 1 commit)
