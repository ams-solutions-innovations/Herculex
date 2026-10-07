---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 17
subsystem: docs
tags: [gdpr, privacy, supabase, migration, gemini-analyze, verification-gate]

requires:
  - phase: 23-01..23-16
    provides: physique schema v47, sync, blur/EXIF pipeline, check-in flow, progress view
provides:
  - Privacy docs (GDPR memo, public policy, data truth table) matching shipped physique behaviour
  - Recorded green verification gate
  - v47 Supabase migration applied and gemini-analyze deployed (user-reported)
affects: [phase-23 verification]

tech-stack:
  added: []
  patterns:
    - "Human-gated remote changes: executor writes, user applies, docs row updated after approval"

key-files:
  created: []
  modified:
    - docs/GDPR_ARTICLE_9_COMPLIANCE.md
    - docs/PRIVACY_POLICY.md
    - docs/DATA_TRUTH_TABLE.md
    - docs/supabase-migrations.md

key-decisions:
  - "Docs state EXIF removal applies to stored copies only; the existing Dream Physique analysis still uploads original picker bytes (I1)"
  - "Under-18 consent, consent-copy legal review and iCloud exclusion recorded as open items, not resolved"

patterns-established: []

requirements-completed: []

duration: n/a
completed: 2026-10-03
---

# Phase 23 Plan 17: Phase Close Summary

Privacy documentation rewritten to match the shipped physique behaviour (files local, metadata synced, Gemini analysis after consent), full gate recorded green, and the v47 migration plus gemini-analyze deploy approved by the user.

## Task Outcomes

| Task | Name | Result | Commit |
| ---- | ---- | ------ | ------ |
| 1 | Docs update and verification gate | Done | 6daf846 |
| 2 | Real-device verification (blur, EXIF, migration, camera resume, under-18, visual) | User replied "approved"; no detailed results supplied | n/a (human) |
| 3 | Apply v47 migration and deploy gemini-analyze | User replied "approved"; no verification counts supplied | n/a (human) |

## Gate Results (Task 1)

- `flutter analyze`: 0 errors, 43 pre-existing issues (warnings/infos, none from this plan).
- `flutter test`: all passed (+2253, ~9 skipped).
- Deno (`gemini-analyze`): 27 passed.
- `dart run tool/check_structure.dart`: 57 violations, unchanged from the count recorded at planning; no `features/physique` line and no `local_data_wipe.dart` line.
- `dart format --set-exit-if-changed`: exits 1 on 62 pre-existing files, none introduced by this plan.

## Human Checkpoints

- **Task 2 (real device):** User replied "approved". No per-step results were supplied. The iOS result (built / pod error / not tested) was not reported, so it is recorded as **unreported**. Steps 1 to 8 are accepted on the user's word only.
- **Task 3 (Supabase):** User replied "approved". The four verification counts (4 tables, 16 policies, 4 realtime rows, 4 pull indexes), the function deploy, and the sync smoke test were not itemised in the reply; they are recorded as **approved by the user, counts not supplied**. The executor did not run `db push`, `functions deploy` or `secrets set`. `docs/supabase-migrations.md` now shows `20261002000000_physique_v47` as applied on 2026-10-03 on the strength of that approval.

## Known limitations

Not fixed by this phase:

1. The Measurements screen still writes the legacy `progress_photos` table with picker cache paths. The migrator appends such rows to the legacy_import goal on the next launch, so they are not left behind, but capture is not sanitised at capture time, and a cache file already gone by then is reported once as "older photos couldn't be recovered". Routing it through the new pipeline was declined by the user on 2026-10-02.
2. A user with progress photos but no Dream Physique summary history gets a synthesized legacy_import goal with no target and a maintain-only roadmap proposal (replaces the earlier "not migrated" limitation, D-08).
3. The training-level chart is capped at Intermediate because `understandsRirRpe` and `hasRunStructuredBlocks` have no history (RESEARCH Open Question 2, accepted by the user 2026-10-02).
4. Low assessment confidence gates roadmap generation and the deep-link preset only; the manual nutrition editor is gated by age only (RESEARCH Open Question 1, user decision 2026-10-02).
5. `dream_physique_view.dart` and `nutrition_targets_view.dart` stay over the 600-line cap because minimal line-budgeted edits were accepted instead of a split (CONTEXT).
6. iCloud backup exclusion for the physique folder is untested (needs macOS).
7. iOS deployment target 13.0 versus ML Kit's published 15.5 minimum is unverified.
8. The consent copy is a DRAFT pending legal review.
9. `PhysiqueTuning.unknownConfidenceRestricts` stays `false` (migrated legacy analyses legitimately carry unknown confidence; flipping it would restrict them; revisit only with an explicit product decision).
10. **(W1)** After migration the original picker files and the legacy `progress_photos` rows are removed, so baseline photos exist only as `physique_photos` rows and sandbox copies and are used only as AI baselines. The Measurements gallery, `body_fat_ai_dialog` and the `dream_physique_view._loadUserContext` photo auto-select no longer see migrated photos, and the new UI shows only check-in thumbnails (baseline photos are not displayed anywhere).
11. **(I1)** The existing Dream Physique analysis still uploads the original picker bytes with EXIF intact; only the check-in path uses sanitised bytes. "EXIF and GPS removed" is true of stored copies, not of what is transmitted in that analysis (the docs are worded accordingly).
12. **(I2)** On a second device photo metadata syncs but the files do not (D-09), so thumbnails show the "Photo unavailable" placeholder and the AI baseline degrades: "Add check-in" on a device with no baseline file shows the baseline error instead of comparing.

## Open GDPR Items

All three are listed in `docs/GDPR_ARTICLE_9_COMPLIANCE.md` as unchecked with `Owner: TBD (needs a human decision)`:

- Parental consent / minimum age for processing special-category data of under-18 users (Art. 8, RESEARCH A10).
- Review of the DRAFT consent copy.
- iCloud backup exclusion of `<Documents>/physique` on iOS (A11).

## Stale note in CLAUDE.md

CLAUDE.md still says "`0015` and `0016` are both outstanding"; both are already applied remotely (STATE.md 27-10). Not edited here (flagged only, per plan). The sole migration pending before this plan was `20261002000000_physique_v47`, now reported applied.

## Deviations from Plan

None to the plan's tasks. Process note: STATE.md `state.*` verbs may not parse this file format; STATE.md was handled minimally by hand.

## Known Stubs

None.

## Self-Check: PASSED

- Task 1 commit 6daf846 exists in git history (HEAD at plan resume).
- `docs/supabase-migrations.md` updated with the applied row.
