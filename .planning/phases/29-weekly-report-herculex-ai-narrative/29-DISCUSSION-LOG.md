# Phase 29: Weekly Report & Herculex AI Narrative - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-03
**Phase:** 29-weekly-report-herculex-ai-narrative
**Areas discussed:** Freeze & AI failure, Week window & timing, Opt-in & entry points, Report layout & actions

---

## Freeze & AI failure

| Question | Options | Selected |
|---|---|---|
| Freezing measured numbers | Snapshot JSON in row / Store refs, recompute live / You decide | Snapshot JSON in row |
| AI failure behaviour | Save numbers, retry narrative / Numbers-only no retry / Don't persist until AI succeeds | Save numbers, retry narrative |
| AI trigger | Auto on first open / Explicit Generate button | Auto on first open |

## Week window & timing

| Question | Options | Selected |
|---|---|---|
| Week covered | Current ISO week to date / Last completed week / Rolling 7 days | Current ISO week to date |
| Missed week | Generate on first open any time / Only within its week / Backfill all | Generate on first open any time |
| Minimum data | Any one logged signal / Per-section threshold / Empty week still creates row | Any one logged signal |

## Opt-in & entry points

| Question | Options | Selected |
|---|---|---|
| Opt-in | One toggle in notification settings / Separate opt-in from notification / Opt-in via card | One toggle in notification settings |
| Notification time | Sunday 18:00 editable / Sunday 20:00 editable / Fixed | Sunday 18:00 editable |
| Entry points | Analytics tab + dashboard card / Analytics only / Progress screen | Analytics tab + dashboard card |

## Report layout & actions

| Question | Options | Selected |
|---|---|---|
| Measured vs AI separation | Measured then AI card / AI summary on top / Inline AI notes | Measured sections, then AI card |
| TDEE shift | Actionable card / Informational only / Always show | Actionable card in measured part |
| Narrative content | Summary + 2-3 suggestions / Summary only / With apply buttons | Summary + 2-3 suggestions |
| KB-04 Hercul channel | Defer again / Take it in Phase 29 | Defer again |

## Claude's Discretion

Table columns, JSON payload shape, section order, copy, corpus segments, quota number, causal-wording post-check, unread-state storage.

## Deferred Ideas

KB-04 Hercul AI channel; apply buttons; multi-week backfill; per-section minimums.
