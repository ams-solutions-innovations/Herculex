# Phase 26: Herculex AI Knowledge Base & Brand Unification - Context

**Gathered:** 2026-09-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish the server-side coaching knowledge base that will ground every future Herculex AI
output (Phases 27/28/29/PHYS-07), make provenance traceable via `knowledgeVersion`/`modelVersion`,
unify the user-facing brand on "Herculex AI", and replace the single shared daily AI cap with
per-kind quotas that fail closed instead of open. Requirements: KB-01–05.

This phase ships the **contract and plumbing**, not new AI-driven features. None of today's 8
existing Gemini kinds (`food_photo`, `nutrition_label`, `exercise_identification`,
`supplement_photo`, `barcode_product`, `body_fat_estimate`, `dream_physique`, `rambler_food`)
change their analysis behavior — they are pure analysis, not coaching advice, and none consume
the knowledge corpus. Phase 27 (program briefs), Phase 28/29, and PHYS-07 are the first real
consumers of the corpus segments.

</domain>

<decisions>
## Implementation Decisions

### Corpus injection mechanism
- **D-01:** Corpus segments are passed to Gemini via the API's real `systemInstruction` field,
  separate from the per-kind `promptText` built in `prompts.ts`'s `contents[].parts`. This is a
  new field in `index.ts`'s `generate()` — today it only ever builds `contents`.
- **D-02:** Corpus lives in one new file beside `prompts.ts` — `knowledge_base.ts` — exporting
  the four named segments (`core`, `programming`, `nutrition`, `recovery`) as string constants
  plus a `KNOWLEDGE_VERSION` constant, mirroring `prompts.ts`'s existing one-file/named-export
  pattern.
- **D-03:** The real textbook is not delivered yet. Ship a **minimal, honest placeholder** per
  segment — a few sentences of generic, safe coaching mentality (e.g. favor compound movements,
  progressive overload, avoid injury-provoking cues) — enough to prove the injection path works
  end-to-end. Not an empty string, not elaborate content to be thrown away.
- **D-04:** No existing kind is wired to any corpus segment in this phase. The
  `core`/`programming`/`nutrition`/`recovery` → `kind` mapping table in
  `docs/herculex-ai-plan-2026-09-27.md` §2.2 describes future consumers (`program_brief`,
  `weekly_report`, `hercul_advice`, `physique_checkin`) that don't exist yet. `dream_physique`
  stays un-grounded in Phase 26 even though it already returns a `programmingProfile` —
  explicitly deferred to when Phase 27's contract exists, not retrofitted here.

### knowledgeVersion / modelVersion provenance
- **D-05:** `modelVersion` (which Gemini model actually answered — primary `geminiModel` vs. the
  429/503 `geminiFallbackModel`) is added to the response envelope for **all 8 existing kinds**
  now — it's orthogonal to the knowledge corpus and `index.ts` already knows this value per call.
- **D-06:** `knowledgeVersion` is only present when a corpus segment was actually injected — i.e.
  never on any of today's 8 kinds in this phase, since none are wired (see D-04).
- **D-07:** Both fields sit in a top-level `provenance` object in the JSON response:
  `{ result, provenance: { modelVersion, knowledgeVersion? }, ... }` (alongside whatever
  per-kind fields already exist, e.g. `groundingSources`, `privacy`).
- **D-08:** No drift/Supabase schema bump in this phase. Provenance is a server-response contract
  only — nothing is persisted client-side yet, since no existing table has a slot for it and each
  future consumer phase (23/27/28/29) already does its own 5-chore schema bump when it adds its
  own table (`tdee_estimates`, `weekly_reports`, program brief storage, etc.). Adding provenance
  columns is each of those phases' job, not Phase 26's.
- **D-09:** `knowledgeVersion` uses a real semver-style string from day one —
  `kb-2026.10-1` (or similar `kb-YYYY.MM-N`) — even though segment content is placeholder. When
  the real textbook lands it's the next version bump, not a format migration.

### Per-kind quotas
- **D-10:** Per-kind limits are configured as **one env var per kind**
  (`GEMINI_LIMIT_FOOD_PHOTO`, `GEMINI_LIMIT_DREAM_PHYSIQUE`, etc.), matching the existing
  `GEMINI_DAILY_LIMIT` pattern exactly — redeployable via project secrets, no code change.
- **D-11:** Limits are **tiered by cost/frequency**, not uniform:
  - Cheap/frequent (`food_photo`, `rambler_food`, `nutrition_label`, `barcode_product`): 30/day
  - Expensive/occasional (`exercise_identification`, `supplement_photo`, `body_fat_estimate`):
    15/day
  - Highest-value/multi-image (`dream_physique`): 10/day

  These are starting values for planning/research to refine, not exact numbers to defend —
  the point is the tiering shape (cheap-frequent > occasional > expensive-multi-image), not the
  precise digit.
- **D-12:** `ai_usage_bump`'s SQL (migration 0018) currently sums `calls` **across all kinds**
  for the day before comparing to `p_daily_limit`, even though the `ai_usage` table already keys
  on `(user_id, day, kind)`. This must change to sum **per kind**, and `index.ts` must pass the
  kind-specific limit instead of the single `dailyLimit` constant.
- **D-13:** The existing fail-open bug (`bumpUsage()` in `index.ts`: any RPC failure —
  unreachable DB, missing RPC — currently lets the request through) becomes **fail-closed for
  all 8 kinds uniformly**, with **one retry** of `ai_usage_bump` before rejecting, to avoid
  rejecting a real request on a single transient blip. No kind gets an exception.
- **D-14:** Quota-exhausted error messages become **kind-specific**: name the specific feature
  that's capped and its limit (e.g. "Today's photo food scans (30/day) are used up — try again
  tomorrow, or log this meal manually"), including a concrete fallback action where one exists,
  not the current generic shared-number message.

### Brand rename wording & data
- **D-15:** The consent string at `dream_physique_view.dart` (currently around line 819/842,
  "I agree to send these photos to Google Gemini") **keeps naming the real processor explicitly**
  — GDPR Article 9 consent for physique photos requires naming who actually processes the data,
  not a rebrand. Update to something like "Herculex AI (powered by Google Gemini)" — verify
  exact wording against `PRIVACY_POLICY.md` / `GDPR_ARTICLE_9_COMPLIANCE.md` before finalizing.
- **D-16:** Every other user-visible "Gemini AI" string (~35 strings across ~15 files —
  tooltips, dialog titles, loading text, button labels) becomes **plain "Herculex AI"**, no
  processor mention. This is the only surface that gets the "(powered by Google Gemini)"
  suffix; everywhere else is fully rebranded.
- **D-17:** Class names (`GeminiBackend`, `SupabaseGeminiBackendService`,
  `GeminiFoodAnalyzerService`), `kind` string values, the Edge Function name
  (`gemini-analyze`), and code comments/docs are **untouched** — only literal user-visible
  string content changes. This includes `prompts.ts`'s `foodPhotoPrompt` JSON-schema
  instruction, which currently tells Gemini to return `"brand": "Gemini AI"` — that instructed
  value becomes `"Herculex AI"` so newly-created entries carry the new brand.
- **D-18:** Historical nutrition entries already stored with `brand: 'Gemini AI'` are **left
  as-is** — no data migration/backfill UPDATE. Only new entries (via the D-17 prompt change and
  `gemini_food_analyzer_service.dart`'s default) get `brand: 'Herculex AI'`. A diary entry is a
  historical record of what happened at logging time, not a live label.
- **D-19:** `PRIVACY_POLICY.md` and `GDPR_ARTICLE_9_COMPLIANCE.md` are **out of scope** for this
  phase. Since D-15 keeps the consent string naming Google Gemini explicitly, nothing in those
  legal docs is actually contradicted by the rename — no edit forced. Flagged as a deferred
  check, not touched as a side effect of a UI-string phase.
- **D-20:** No regression-guard test is added to prevent a future PR from reintroducing a
  user-visible "Gemini" string. A precise guard would need to distinguish string-literal UI text
  from legitimate identifiers/kind-values/docs (D-17) — a non-trivial classification problem not
  worth building for a one-time sweep. Just fix the ~35 known strings.

### Claude's Discretion
- Exact placeholder corpus wording per segment (D-03).
- Exact final per-kind quota numbers within the tiering shape described in D-11.
- Exact retry/backoff shape for the `ai_usage_bump` retry in D-13.
- Exact final consent-string wording in D-15, after checking the legal docs.
- Which of the ~35 identified strings need touch-up vs. any additional ones discovered during
  implementation (the grep in this discussion was not exhaustive — treat the count as a floor).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Herculex AI amendment & house rules
- `docs/herculex-ai-plan-2026-09-27.md` §2 — full Phase 26 design: corpus location, segment
  table, quota rationale, rename scope and the two named traps (consent string, stored brand
  data value). This discussion refines several of its open points (see Decisions above).
- `.planning/ROADMAP.md` (Phase 26 section, "Execution order — not numeric" note) — goal,
  requirements, success criteria; confirms Phase 26 is foundational with no upstream dependency.
- `.planning/REQUIREMENTS.md` §12 (KB-01–05) — the five locked requirements this phase satisfies.
- `.planning/phases/06-label-ocr-and-photo-assist/06-AI-SPEC.md` — origin of the house rule
  ("deterministic primary, AI bounded, AI never writes to the database, user confirms") that
  governs every AI phase, cited by the amendment doc as still binding.
- `docs/rb01-gemini-secret-remediation.md` — why `GEMINI_API_KEY` must never reach the client;
  why the Edge Function proxy pattern exists at all.
- `docs/edge-functions-prod-arhitektura.md` — referenced in `index.ts`'s header comment for why
  AI proxying and the `product_catalogue` write path must stay separate.

### Legal (read before touching the consent string, D-15/D-19)
- `PRIVACY_POLICY.md` — check current Google Gemini wording before changing the consent string.
- `GDPR_ARTICLE_9_COMPLIANCE.md` — physique photos are Article 9 special-category data; the
  consent string's processor-naming requirement traces here.

### CLAUDE.md house rules that apply
- `CLAUDE.md` "Schema changes are five chores, not one" — relevant only if a future phase (not
  this one, per D-08) adds provenance columns.
- `CLAUDE.md` "No hand-written file over 600 lines" — not directly triggered by this phase's
  edits, but `knowledge_base.ts` and any `index.ts`/`prompts.ts` growth should stay mindful of it.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `supabase/functions/gemini-analyze/prompts.ts`: existing one-file/named-export-function
  pattern for prompt text — `knowledge_base.ts` (D-02) mirrors this exactly.
- `PhysiqueProgrammingProfiles`: already has `modelVersion` + `source` fields — the vetted
  precedent for what a future phase's provenance persistence should look like once it does its
  own schema bump (see D-08).
- `ai_usage` table (migration `0018_shared_data_hardening.sql`): already keyed on
  `(user_id, day, kind)` with RLS (`ai_usage_select_own`) and a `security definer` bump function
  — the per-kind column already exists, only the SQL aggregation in `ai_usage_bump` needs to
  change from "sum across all kinds" to "sum for this kind" (D-12).

### Established Patterns
- `generate()` in `index.ts` builds one `contents[].parts` array per call and has no
  `systemInstruction` usage anywhere today — D-01 is a genuinely new field, not an extension of
  an existing one.
- `GeminiKind` union in `index.ts` (8 values) is the complete list of what needs per-kind
  handling for both quotas (D-11) and provenance (D-05/D-06).
- Fallback-model retry pattern already exists in `generate()` for 429/503 (primary →
  `geminiFallbackModel`) — same file, same function, where `modelVersion` (D-05) needs to be
  captured (which of the two models actually answered).
- `bumpUsage()`'s existing fail-open comment block in `index.ts` explicitly says "if this ever
  becomes fail-closed, make it a deliberate decision, not a side effect of a refactor" — D-13 is
  that deliberate decision, made in this discussion.

### Integration Points
- `index.ts` `Deno.serve` handler: quota check (`bumpUsage`) happens before the `switch
  (payload.kind)` dispatch — per-kind limit lookup (D-10/D-11) and per-kind error message (D-14)
  both need to happen at or before that call site.
- `gemini_food_analyzer_service.dart:24,40,52` and `prompts.ts`'s `foodPhotoPrompt`: the two
  places `brand: 'Gemini AI'` is written as stored data, not display text (D-17).
- `dream_physique_view.dart` (~line 819/842): the one protected consent string (D-15); the
  surrounding ~10 other "Gemini AI" strings in the same file are NOT protected (D-16).

</code_context>

<specifics>
## Specific Ideas

No specific visual/UX requirements beyond the wording decisions captured above — this phase is
backend contract + string sweep, not new UI.

</specifics>

<deferred>
## Deferred Ideas

- Wiring `dream_physique` (or any other existing kind) to a corpus segment — explicitly Phase 27+
  territory (D-04).
- Adding provenance columns to any client-side table — each consuming phase's own job (D-08).
- Updating `PRIVACY_POLICY.md` / `GDPR_ARTICLE_9_COMPLIANCE.md` wording — deferred as a separate,
  deliberate legal review (D-19), not bundled into this phase.
- A regression-guard test against reintroducing "Gemini" user-visible strings — considered and
  explicitly declined for this phase (D-20).

None — no scope-creep suggestions came up during discussion; all four areas stayed within the
KB-01–05 boundary.

</deferred>

---

*Phase: 26-herculex-ai-knowledge-base-brand-unification*
*Context gathered: 2026-09-27*
