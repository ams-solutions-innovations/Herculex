# Phase 29: Weekly Report & Herculex AI Narrative - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver an opt-in weekly report: one persisted row per ISO week that snapshots nutrition adherence and
frequent foods, training volume and strength, recovery/sleep/activity, physique progress, and TDEE
drift. Measured sections are computed locally from existing analytics; Herculex AI adds a
knowledge-grounded narrative visually separated from the numbers. A Sunday
`DateTimeComponents.dayOfWeekAndTime` notification deep-links into the report, which is generated on
open, never in the notification callback. Past weeks are browsable and never regenerate differently.
Recovery/sleep/activity relationships are stated as correlation, never causation.

Requirements: RPT-01–05. Design detail: `docs/herculex-ai-plan-2026-09-27.md` §5.

</domain>

<decisions>
## Implementation Decisions

### Freeze & AI failure
- **D-01:** The `weekly_reports` row stores the full **measured payload as a JSON snapshot** at
  generation time (same blob pattern as `HerculexAiProgramBriefs` / `PhysiqueProgrammingProfiles`).
  Past weeks render from the row only and are never recomputed, so a back-edited food log cannot
  change a past report (RPT-04).
- **D-02:** The measured snapshot is persisted **immediately** on first open. If the AI narrative
  fails (offline, unconfigured, over quota, validation reject), the row exists with an empty
  narrative, the UI shows a "Narrative pending" state, and a **user-initiated retry** button
  re-fires the call (consistent with Phase 27 D-04/D-05). Once a narrative is saved it is never
  regenerated or overwritten.
- **D-03:** The narrative is **fired automatically on first open** of a given week's report (one
  `weekly_report` quota unit per week; RPT-03 "generated on open"). Only retry after failure is
  manual. Quota exhaustion fails closed per Phase 26 D-13/D-14 with a kind-specific message.

### Week window & timing
- **D-04:** A report covers the **current ISO week to date** (Mon through the moment of generation,
  including Sunday's logs when opened Sunday). The ISO week is the row key (RPT-01). Data logged
  after generation is not included — frozen by design.
- **D-05:** A missed week can be **generated on first open at any time**; it snapshots whatever data
  exists when generated, then freezes. No backfill of multiple missed weeks in one go.
- **D-06:** Minimum data: a report is generated if **at least one signal** (food, workout,
  bodyweight, or health sample) exists in that week. Sections without data show a short "No data
  this week" state. The AI call is **skipped** when nothing measurable exists.

### Opt-in & entry points
- **D-07:** Opt-in is **one "Weekly report" toggle in notification settings**, beside the daily-log
  reminder. On = Sunday notification scheduled and reports generate/browsable. Off = no
  notification and no new generation; existing history stays visible.
- **D-08:** Default notification time is **Sunday 18:00 local, editable** via a time picker (like
  `dailyLogTimeHHMM`). Implemented as a new scheduler alongside `DailyLogNotificationScheduler`,
  using `DateTimeComponents.dayOfWeekAndTime` and a stable notification id. The callback only
  deep-links (no Dart work; the project has no `workmanager`/alarm manager).
- **D-09:** Reports are reached from the **Analytics area** (history list reusing analytics
  providers) plus a **dashboard card** that appears when a report is ready/unread. The notification
  deep-links to the current week's report route (route constants in `app/router/routes.dart`,
  parameterised path via `AppPaths`).

### Report layout & actions
- **D-10:** Layout is **measured section cards first, then one distinct "Herculex AI" narrative
  card** with its own tint/heading and a note that it interprets the numbers above and does not
  change them (RPT-02). The model receives the numbers as facts and may not correct them.
- **D-11:** A **material TDEE shift** appears as an actionable card in the measured part, only when
  the shift exceeds `max(100 kcal, 5%)` (Phase 28 D-09). Phase 29 diffs `tdee_estimates` itself
  (Phase 28 D-11). The card offers "Update my target to X" / "Keep current target"; the decision is
  persisted on the report row, and past reports show the outcome **read-only**, never an active
  prompt. Nothing is silently rewritten (TDEE-05).
- **D-12:** The AI narrative is a **short summary plus 2–3 knowledge-grounded improvement
  suggestions**, advisory only — no "apply" buttons, AI never writes to the database or changes
  targets. Correlation language ("tended to go with"), never causal ("because") — enforced by the
  prompt and a client-side post-check that rejects causal wording (RPT-05).

### Claude's Discretion
- Exact `weekly_reports` columns beyond: ISO week key, measured payload JSON, narrative (nullable),
  `knowledgeVersion`/`modelVersion`, TDEE-decision outcome, generated-at timestamp. Standard 5-chore
  schema-bump latitude (sync columns, unique `(iso_year, iso_week)` per user, Supabase migration).
- Exact JSON shape of the measured payload and its versioning field.
- Exact section order within the measured part, copy, and empty-state wording.
- Which `knowledge_base.ts` segments `weekly_report` consumes (design doc §2.2 maps `nutrition` and
  `recovery`), the `weekly_report` quota number within the Phase 26 tiering, and `KNOWLEDGE_VERSION`
  handling.
- Wording of the post-check that rejects causal phrasing, and what happens on rejection (treated
  like any narrative failure per D-02).
- Whether the "unread" dashboard card state is a column on the row or local-only.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design & requirements
- `docs/herculex-ai-plan-2026-09-27.md` §5 — Phase 29 design (persisted row, measured sources, AI part, Sunday notification); §2.2 corpus→kind mapping; §7 risks (schema bump, long files)
- `.planning/REQUIREMENTS.md` §15 — RPT-01–05; §14 TDEE-05 handoff
- `.planning/ROADMAP.md` — Phase 29 entry and success criteria
- `CLAUDE.md` — five-chore schema bump, 600-line limit, `Clock`, route constants, `package:` imports

### Prior phase decisions that bind this phase
- `.planning/phases/26-herculex-ai-knowledge-base-brand-unification/26-CONTEXT.md` — D-01–D-04 corpus injection, D-05–D-09 provenance envelope, D-10–D-14 per-kind quotas and fail-closed, D-16 "Herculex AI" naming; `26-VERIFICATION.md` for the deferred KB-04
- `.planning/phases/27-herculex-ai-program-generation/27-CONTEXT.md` — D-04/D-05 explicit-action and visible fallback pattern, D-08/D-09 persisted-blob table pattern, AI card styling
- `.planning/phases/28-adaptive-tdee-activity-calibration/28-CONTEXT.md` — D-09 materiality rule, D-10 accept/dismiss prompt, D-11 history-only handoff

### Server side
- `supabase/functions/gemini-analyze/` (`index.ts`, `prompts.ts`, `knowledge_base.ts`) — add a `weekly_report` kind, per-kind quota, corpus injection

No other external specs — requirements fully captured above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/features/analytics/application/analytics_providers.dart`: `weeklyTonnageProvider`, `topOneRmsProvider`, `recoveryWarningsProvider` (computed today and shown nowhere), `cnsTrendsProvider`, `sleepVsRpeProvider`, `hrVsTonnageProvider`, `trainingSnapshotProvider`
- `lib/features/analytics/domain/biometric_correlations.dart`: `BiometricCorrelationResult` (r², sampleSize); its `interpretation` text hints at causation ("shifts targets positively") and must not be reused verbatim for RPT-05
- `lib/features/physique/domain/` (`check_in_verdict.dart`, `physique_series.dart`, `physique_roadmap.dart`): Phase 23 physique progress sources
- `lib/features/nutrition/domain/tdee_estimate.dart` and the `tdee_estimates` table (Phase 28): drift history input
- `lib/features/notifications/data/daily_log_notification_scheduler.dart`: pattern for the new weekly scheduler (`zonedSchedule`, channel id, notif id)
- `lib/features/notifications/domain/notification_settings.dart` + `notification_settings_view.dart`: where the toggle and time field go
- `lib/services/ai/` (`gemini_backend_service.dart`) and Phase 27's `HerculexAiBriefService`: model for the narrative service

### Established Patterns
- Persisted AI result as a JSON blob table with `source`/`modelVersion`/`knowledgeVersion`, sync columns, owner-only RLS (`HerculexAiProgramBriefs`)
- UI never touches drift directly — add a `weekly_report_repository.dart`
- `StreamProvider` for drift reads; all time math via `Clock` (ISO-week computation must go through it)
- Route paths via `AppRoutes`/`AppPaths`; parts-based splits for files over 600 lines

### Integration Points
- New drift table + schemaVersion bump (read `database.dart` for the current version) and a matching `supabase/migrations/NNNN_*.sql`; migrations 0015/0016 outstanding per CLAUDE.md
- Edge Function `gemini-analyze`: new `weekly_report` kind, quota, corpus segments
- `app/router/routes.dart`: report route + history route; notification tap handler in `lib/main.dart`
- Nutrition targets save path for the D-11 "Update my target" action (user-confirmed write through the existing repository, never by AI)

</code_context>

<specifics>
## Specific Ideas

- Narrative card note: it interprets the measured numbers and does not change them.
- Suggested correlation phrasing: "tended to go with", never "because".

</specifics>

<deferred>
## Deferred Ideas

- **KB-04 labelled AI advice channel in Hercul** — deferred again by user decision (2026-10-03); unclaimed by any current phase. Candidate for a future phase that adds a `hercul_advice` kind reading from persisted reports.
- One-tap "apply" for AI suggestions — violates "AI never writes"; not in scope.
- Backfilling multiple missed weeks and per-section minimum-data thresholds — rejected for now.

</deferred>

---

*Phase: 29-Weekly Report & Herculex AI Narrative*
*Context gathered: 2026-10-03*
