# Phase 26: Herculex AI Knowledge Base & Brand Unification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-27
**Phase:** 26-herculex-ai-knowledge-base-brand-unification
**Areas discussed:** Corpus injection & placeholder, knowledgeVersion/modelVersion scope, Per-kind quota numbers, Brand rename wording & data

---

## Corpus injection & placeholder

### Q: How should the corpus reach Gemini?

| Option | Description | Selected |
|--------|-------------|----------|
| Real systemInstruction field | Pass composed segment text via Gemini's systemInstruction, separate from promptText | ✓ |
| Prepend to promptText | Concatenate corpus onto existing promptText string | |
| You decide | | |

**User's choice:** Real systemInstruction field.

### Q: Should Phase 26 attach any corpus segment to today's 8 existing kinds?

| Option | Description | Selected |
|--------|-------------|----------|
| Contract only, no existing kind wired | Ship segments/versioning/composition helper, no existing kind changes | ✓ |
| Also ground dream_physique today | Wire it to programming/nutrition segment now | |
| You decide | | |

**User's choice:** Contract only, no existing kind wired.

### Q: What should the placeholder corpus content contain?

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal honest placeholder | A few sentences of generic, safe coaching mentality per segment | ✓ |
| Empty string per segment | Ship versioning with literally empty content | |
| You decide | | |

**User's choice:** Minimal honest placeholder.

### Q: How should the corpus be organized on disk?

| Option | Description | Selected |
|--------|-------------|----------|
| One knowledge_base.ts, 4 exported segments | Mirrors prompts.ts's pattern | ✓ |
| One file per segment | knowledge_base/core.ts, programming.ts, etc. | |
| You decide | | |

**User's choice:** One knowledge_base.ts, 4 exported segments.

---

## knowledgeVersion/modelVersion scope

### Q: Should modelVersion be added for all 8 existing kinds now, or only future knowledge-grounded kinds?

| Option | Description | Selected |
|--------|-------------|----------|
| All 8 kinds now | Cheap to add, already known per call | ✓ |
| Only future knowledge-grounded kinds | Scoped together with knowledgeVersion | |
| You decide | | |

**User's choice:** All 8 kinds now.

### Q: How should knowledgeVersion/modelVersion sit in the response JSON?

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level provenance object | `{ result, provenance: { modelVersion, knowledgeVersion? } }` | ✓ |
| Flat top-level fields | `{ result, modelVersion, knowledgeVersion? }` | |
| You decide | | |

**User's choice:** Top-level provenance object.

### Q: Should Phase 26 bump the schema now for client-side provenance persistence?

| Option | Description | Selected |
|--------|-------------|----------|
| Contract only, no schema bump | Server returns provenance, nothing persisted client-side yet | ✓ |
| Add provenance columns now | Bump drift/Supabase now on existing AI-touched tables | |
| You decide | | |

**User's choice:** Contract only, no schema bump.

### Q: Should knowledgeVersion be a real version string now, or visibly placeholder?

| Option | Description | Selected |
|--------|-------------|----------|
| Real semver-style now | "kb-2026.10-1" from day one | ✓ |
| Visibly placeholder value | "kb-placeholder-1" | |
| You decide | | |

**User's choice:** Real semver-style now.

---

## Per-kind quota numbers

### Q: Where should the 8 per-kind daily limits be configured?

| Option | Description | Selected |
|--------|-------------|----------|
| One env var per kind | GEMINI_LIMIT_FOOD_PHOTO etc., matches existing pattern | ✓ |
| Hardcoded map in index.ts | Single TS object literal | |
| You decide | | |

**User's choice:** One env var per kind.

### Q: What should the actual per-kind limits be?

| Option | Description | Selected |
|--------|-------------|----------|
| Tiered by cost/frequency | 30/15/10 split by kind category | ✓ |
| Keep 50/day, just per-kind | Same ceiling as today, now isolated | |
| I'll specify exact numbers | | |

**User's choice:** Tiered by cost/frequency (30/day cheap-frequent, 15/day occasional, 10/day dream_physique — starting values, not final).

### Q: Should fail-closed on RPC failure apply uniformly, or be nuanced?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail closed for all kinds | Any RPC failure → reject | |
| Fail closed, but only after a retry | One retry before rejecting | ✓ |
| You decide | | |

**User's choice:** Fail closed, but only after a retry.

### Q: What should the quota-exhausted error message tell the user?

| Option | Description | Selected |
|--------|-------------|----------|
| Kind-specific message | Names the specific capped feature + fallback action | ✓ |
| Generic message, per-kind numbers | Keeps today's generic phrasing structure | |
| You decide | | |

**User's choice:** Kind-specific message.

---

## Brand rename wording & data

### Q: What should the ~35 non-consent "Gemini AI" strings become?

| Option | Description | Selected |
|--------|-------------|----------|
| Plain "Herculex AI" everywhere else | Consent string is the only exception | ✓ |
| "Herculex AI (powered by Google Gemini)" everywhere | Processor named on every surface | |
| You decide | | |

**User's choice:** Plain "Herculex AI" everywhere else.

### Q: Should historical nutrition entries with brand='Gemini AI' be migrated?

| Option | Description | Selected |
|--------|-------------|----------|
| Leave historical rows as-is | Only new entries get the new brand | ✓ |
| Migrate existing rows | One-time UPDATE | |
| You decide | | |

**User's choice:** Leave historical rows as-is.

### Q: Should PRIVACY_POLICY.md / GDPR_ARTICLE_9_COMPLIANCE.md be updated in this phase?

| Option | Description | Selected |
|--------|-------------|----------|
| Out of scope for Phase 26 | Consent string still names Google Gemini, nothing contradicted | ✓ |
| Update legal docs too | Sweep both docs in the same phase | |
| You decide | | |

**User's choice:** Out of scope for Phase 26.

### Q: Should a regression guard prevent reintroducing "Gemini" user-visible strings?

| Option | Description | Selected |
|--------|-------------|----------|
| No guard, one-time sweep | Just fix the ~35 known strings | ✓ |
| Add a targeted test | Scan presentation/dialog files for literal 'Gemini' | |
| You decide | | |

**User's choice:** No guard, one-time sweep.

---

## Claude's Discretion

- Exact placeholder corpus wording per segment.
- Exact final per-kind quota numbers within the stated tiering shape.
- Exact retry/backoff shape for the `ai_usage_bump` retry.
- Exact final consent-string wording, after checking the legal docs.
- Full enumeration of all user-visible "Gemini" strings (the ~35/15-file count from this
  discussion's grep is a floor, not exhaustive).

## Deferred Ideas

- Wiring any existing kind (incl. `dream_physique`) to a corpus segment — Phase 27+.
- Adding provenance columns to any client-side table — each consuming phase's own schema bump.
- Updating `PRIVACY_POLICY.md` / `GDPR_ARTICLE_9_COMPLIANCE.md` — separate legal review.
- A regression-guard test against reintroducing "Gemini" strings — explicitly declined.
