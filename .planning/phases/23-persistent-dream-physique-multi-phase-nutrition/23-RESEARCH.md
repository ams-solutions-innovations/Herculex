# Phase 23: Persistent Dream Physique & Multi-Phase Nutrition - Research

**Researched:** 2026-10-02
**Domain:** Flutter/drift persistence + sync, on-device image sanitising (EXIF strip, face blur), deterministic nutrition-roadmap domain logic, one new Herculex AI edge-function kind, fl_chart progress screen
**Confidence:** HIGH on codebase integration points and schema mechanics; MEDIUM on tempo ceilings and ML Kit behaviour (cited but not device-tested); LOW on iOS deployment-target and iCloud-backup specifics (could not test on this Windows host)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Roadmap shape & phase transitions**
- **D-01:** The multi-phase roadmap is **generated deterministically, then editable**. The planner proposes phases from BF gap, weight and age (extending `DreamPhysiqueNutritionRecommender`). The user may reorder, resize or delete phases before accepting.
- **D-02:** Phase advancement is **prompt + user confirms**. When exit criteria are met (target weight/BF reached or planned duration elapsed) the app offers "move to next phase" with accept/postpone. Nothing changes calorie targets silently; consistent with the house rule and Phase 28 D-10.
- **D-03:** **One active goal at a time, history kept.** Starting a new goal archives the previous one with its assessments and photos. The 7-day check-in cap (PHYS-06) is per goal.
- **D-04:** Tempo comes from the **existing `DietPhaseCalculator` presets** (cut 20%, bulk 10%, maingain +150 kcal), **capped by a % bodyweight/week ceiling**. Tempo realism is derived from that. No new training-level tempo model this phase.

**Minor & low-confidence guardrails (PHYS-04)**
- **D-05:** **Under 18 cannot cut or bulk.** Only maintain, recomp and small-surplus maingain are offered; the UI explains why and suggests maintenance. Profile has only `ageYears` (no DOB), so a **missing age is treated as restricted** until entered.
- **D-06:** A visual assessment is **low-confidence when the AI returns a low label or a wide confidence band**. Low confidence restricts to maintain/recomp and shows a "log measurements to refine" hint. The guardrail lives in the deterministic domain layer, not the UI. Aligns with Phase 28's PHYS-04 stance.

**Photo storage, privacy & migration (PHYS-01, PHYS-02)**
- **D-07:** Optional facial blur is **on-device via `google_mlkit_face_detection`** (new dependency; the repo already uses mlkit text recognition). Blur is applied on save and the unblurred face is never stored. EXIF is always stripped.
- **D-08:** Existing `ProgressPhotos` rows and the SharedPreferences summary are **migrated into an initial goal**, stripping EXIF on copy; originals are removed only after a successful copy. The 20-entry summary history becomes real rows.
- **D-09:** Sync is **metadata only, never image bytes**: goals, assessments, roadmap phases and photo rows (path, pose, date) sync; files stay in the app sandbox.

**Progress screen & check-in UX (PHYS-05-08)**
- **D-10:** The progress screen is a **new route** (`AppRoutes`/`AppPaths` constant) linked from the existing Dream Physique summary card in Profile. It does not grow `dream_physique_view.dart` (1780 lines).
- **D-11:** The PHYS-07 verdict is a **three-state chip (on track / off track / inconclusive) + confidence range bar + one-line reason**, never a percentage. Any calorie action is a deep-link to the nutrition editor, never an automatic write.
- **D-12:** PHYS-08 charts are **stacked over the goal horizon with a 1M/3M/All toggle**, using `fl_chart`: bodyweight with the phase-target band, e1RM on canonical lifts, and training level (`ExperienceLevel` / strength standards, **not** the Phase 24 XP rank).
- **D-13:** When the 7-day cap blocks a check-in, the button is **disabled with "Next check-in available <date>"**. The repository still enforces the cap with a typed error as the real gate (PHYS-06).

### Claude's Discretion
- Exact % bodyweight/week ceilings, confidence-band width threshold, and the precise exit-criteria definitions per phase type.
- Table and column design (goals, assessments, roadmap phases, photo metadata), within the 5-chore schema checklist.
- Chart axis/styling details and the number of canonical lifts shown.

### Deferred Ideas (OUT OF SCOPE)
- Concurrent multiple goals: rejected for this phase (D-03).
- Training-level-based tempo model (beginner vs advanced gain rates): possible future refinement of D-04.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PHYS-01 | Goals, assessments, check-in history persist in synchronized local/remote tables | New synced drift tables `physique_goals`, `physique_assessments`, `physique_roadmap_phases`, `physique_photos` in ONE schema bump (v46 -> v47); the five-chore recipe is concretely enumerated below, copied from the v45/v46 precedent (`tdee_estimates`, `herculex_ai_program_briefs`) |
| PHYS-02 | Photos in app-sandboxed documents, EXIF stripped, optional facial blur | `image` (move dev -> main dep) re-encode with `bakeOrientation` then fresh `ExifData`, `google_mlkit_face_detection ^0.14.0` for boxes, pixelate crop; all in an isolate behind a `PhysiquePhotoSanitizer` port |
| PHYS-03 | Multi-phase roadmaps (`cut`/`maintain`/`recomp`/`maingain`/`bulk`) compute realistic pacing | Pure-Dart `PhysiqueTempoPolicy` + `PhysiqueRoadmapGenerator` over existing `DietPhase`/`DietPhaseCalculator`; % bodyweight/week ceilings cited from Helms 2014 and Iraki 2019 |
| PHYS-04 | Underage and low-confidence barred from aggressive deficit/surplus | `PhaseEligibility` domain object; single choke point = optional parameter on `DietPhaseCalculator.apply` + the two pre-marked gate sites in `nutrition_targets_view.dart` (lines ~204 and ~1447) + roadmap generator |
| PHYS-05 | Progress screen shows active phase, roadmap position, time in phase, exit criteria | New route + `physique` feature; reads persisted `physique_roadmap_phases`; exit-criteria evaluator is pure domain, uses `Clock` |
| PHYS-06 | Max one check-in photo / 7 days / goal, enforced in repository, next date in UI | `PhysiqueAssessmentRepository.recordCheckIn` re-checks inside a drift transaction, throws typed `CheckInTooSoonException(nextEligibleDate)`; the only code path that can create a `checkin` photo |
| PHYS-07 | AI directional verdict as a confidence-banded range, never a %, never auto-changes calories | New `physique_checkin` edge-function kind (quota, consent gate, normaliser, provenance); AI returns a band + label + reason, **Dart derives the three-state verdict deterministically** |
| PHYS-08 | Charts: bodyweight trend, e1RM on canonical lifts, training level, phase-target band | `fl_chart 0.69.2` (`RangeAnnotations` / `BetweenBarsData`); new e1RM time-series query (none exists today); training level derived from `ExperienceLevel`, NOT `levelProgressProvider` (that is XP) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Actionable directives the planner must verify; treated as locked.

- `flutter analyze` must report 0 errors (exit code is 1 on warnings too, so read the error count); redirect `flutter analyze`/`flutter test` output to a file, never pipe to `tail` (loses the exit code); `tr '' '
'` before grepping test output.
- Run `dart run tool/check_structure.dart` and `dart format lib test tool`; drift codegen via `tool/codegen.ps1`.
- Layout: feature-first (`data/ domain/ application/ presentation/`); `domain/` is plain Dart (no Flutter); `presentation/` splits into `views/ sheets/ dialogs/ widgets/` at 8 files (suffix decides); **`core/` and `design_system/` never import `features/`**.
- Imports always `package:herculex/...`; cross-directory `export` must be spelled with `package:` by hand.
- **No hand-written file over 600 lines**; split with `part`/`part of` in a subfolder named after the file (parts cannot carry imports). `dream_physique_view.dart` (1780), `dream_physique_priorities_view.dart` (608) and `nutrition_targets_view.dart` (2618) are already over: split first if touched, otherwise keep edits minimal.
- Route paths are constants in `app/router/routes.dart` (`AppRoutes.x` / `AppPaths.x(id)`), never string literals at call sites.
- The UI never touches drift directly; add repository methods instead.
- All time-of-day math through `Clock` (`core/utils/clock.dart`); tests override it.
- Prefer `StreamProvider` over `FutureProvider` for drift reads.
- `@DataClassName` mandatory on new tables (avoid `SetEntrie`-style names).
- Schema changes are five chores: `schemaVersion` + `onUpgrade` branch; `drift_dev schema dump`; `schema generate`; retarget `migration_test.dart` and `schema_v2*.dart`; matching `supabase/migrations/NNNN_*.sql` for synced tables. Guard `addColumn` with `pragma_table_info`; guard `createTable` with `sqlite_master`. Migrations are written but not applied; applying is human-gated. (CLAUDE.md's "0015/0016 outstanding" note is stale, see Pitfall 3.)
- Supabase project ref is `ldzgyzigvbwofbswitrv` (never `jioesomepkauponjrena`).
- Line endings: repo stores LF, checkout is CRLF; use `git diff --ignore-all-space` to judge real changes; verify every `git mv` landed.
- Herculex AI house rule: deterministic primary, AI bounded, AI never writes to the database, user confirms.
- Direct `gradlew` calls need Android Studio's JBR, not system JDK 26 (`flutter build` handles this itself).
- No `.claude/skills/` or `.agents/skills/` exist, so no project skill rules apply.

## Summary

Phase 23 is mostly integration work, and the integration surface is already well marked. The two places where a PHYS-04 deficit gate must be wired are literally commented in the code (`nutrition_targets_view.dart` lines 204 and 1447, plus the "PHYS-04 boundary" note on `tdee_estimator.dart:263`), the deep-link seam to the nutrition editor already exists (`context.push(AppRoutes.nutritionTargets, extra: DietPhase)`), the schema-bump recipe has two fresh worked examples (v45, v46), and Phase 26 already shipped the per-kind quota + `knowledgeVersion`/`modelVersion` provenance that PHYS-07 consumes. The heavy lifting is (a) four new synced tables and one idempotent legacy migrator, (b) an image-sanitising pipeline that does not exist yet, (c) pure-Dart domain logic (tempo, roadmap, eligibility, exit criteria, verdict classifier), and (d) one new edge-function kind.

Several things in the codebase contradict an obvious reading of the spec and the planner must design around them: **(1)** `image` is only a *dev* dependency today and nothing in `lib/` imports it. **(2)** `google_mlkit_face_detection` latest (0.15.1) needs `google_mlkit_commons ^0.13`, but the lockfile pins commons 0.12.0 via `google_mlkit_text_recognition 0.16.0`; use **0.14.0** (commons `^0.12.0`) to avoid a collateral upgrade. **(3)** Existing `ProgressPhotos.filePath` rows store the `image_picker` *cache* path (`measurements_view.dart:224-238` stores `file.path` straight from the picker), not a documents-dir path as the table comment claims, so many legacy files may already be gone; the migrator must tolerate missing sources. **(4)** The edge function's dream-physique consent check is hard-coded to `kind === "dream_physique"`; a new image-bearing kind will upload photos with no consent gate unless that check is extended. **(5)** The current `/training-level` screen and `levelProgressProvider` are XP-based, so PHYS-08's "training level" series needs its own deterministic source. **(6)** `DreamPhysiqueAnalysisResult` has no BF range or assessment-confidence label, so D-06 ("low label or wide band") cannot be evaluated until the dream-physique prompt/normaliser/parser are extended. **(7)** `dream_physique_view.dart` is 1780 lines and its analyse/save path (line ~275) must be rewired, so it must be split with `part` files in plan 1 before any edit.

**Primary recommendation:** Build bottom-up in this order: pure-Dart physique domain (guardrails, tempo, roadmap, verdict, cap policy) -> single v47 schema bump with four synced tables and the human-gated Supabase push -> repositories + photo sanitiser + idempotent legacy migrator -> `physique_checkin` edge-function kind -> providers, progress screen, route and the two editor gate call sites. Keep `DreamPhysiqueAnalysisSummary` and `dreamPhysiqueSummaryProvider` as a compatibility bridge (derived from the active goal's latest baseline) so Phase 27's contract and the five existing test files keep working.

## Architectural Responsibility Map

Herculex is offline-first mobile (no SSR/CDN tier). Tiers here are: UI (presentation), App logic (domain/application), Local DB (drift), Device services (files/ML Kit), Cloud (Supabase Postgres + edge function + Gemini).

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Goal/assessment/roadmap/photo-metadata persistence | Local DB (drift) | Cloud (Postgres via SyncService) | Offline-first; sync is metadata only (D-09) |
| Photo bytes (sanitised, optionally blurred) | Device file sandbox | none (never leaves device) | D-09, GDPR Art. 9 memo: bytes never to Supabase |
| EXIF strip + orientation bake + face blur | Device (Dart isolate + ML Kit) | none | D-07: on-device, unblurred face never stored |
| Tempo, roadmap proposal, exit criteria, eligibility, verdict state, cap policy | App logic (pure-Dart domain) | none | House rule: deterministic primary; guardrail in domain not UI (D-06) |
| 7-day check-in cap (PHYS-06) | Repository (data layer, in a transaction) | UI only displays next date | Spec: "enforced in the repository rather than the widget" |
| Visual assessment + check-in direction band | Cloud (Gemini via `gemini-analyze`) | App logic classifies | AI bounded: returns band/label/reason; Dart derives state; AI never writes to DB |
| Per-kind quota, consent gate, response whitelist | Edge function | DB (`ai_usage_bump` RPC) | Existing Phase 26 pattern |
| Calorie target changes | Existing nutrition editor (user action) | none | D-02/D-11: deep-link only, never auto-write |
| Charts (weight, e1RM, training level, target band) | UI (fl_chart) | App logic builds series | Series construction is pure domain, testable |
| Legacy migration (SharedPreferences + ProgressPhotos) | App startup service | Local DB | Cannot run in drift `onUpgrade` (needs prefs + file I/O) |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| drift | ^2.21.0 (locked, existing) | New synced tables, transactions for the cap | Project standard; every synced table uses `SyncColumns`/`SyncTombstone` |
| fl_chart | 0.69.2 (locked, existing) | Stacked progress charts | Already in project; has `RangeAnnotations`/`HorizontalRangeAnnotation` and `BetweenBarsData` for the target band [VERIFIED: pub cache source `fl_chart-0.69.2`] |
| image | ^4.8.0 (locked 4.8.0; **dev -> main dependency move**) | Decode, `bakeOrientation`, re-encode without EXIF, crop/pixelate/composite | Only pure-Dart option already in the lockfile; JPEG encoder writes `image.exif` and `image.iccProfile` only if present [VERIFIED: `image-4.8.0/lib/src/formats/jpeg_encoder.dart` lines 56-64] |
| google_mlkit_face_detection | **^0.14.0** (NEW) | On-device face bounding boxes | Same publisher/monorepo as the already-used text recognition; 0.14.0 depends on `google_mlkit_commons ^0.12.0` which matches the lockfile [VERIFIED: pub.dev API] |
| image_picker | ^1.1.2 (existing) | Camera/gallery capture | Existing |
| path_provider | ^2.1.5 (existing) | `getApplicationDocumentsDirectory()` for the photo sandbox | Existing |
| shared_preferences | ^2.3.3 (existing) | Read legacy summary once for migration | Existing |
| uuid | ^4.5.1 (existing) | Collision-free photo file names | Existing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| flutter_test | SDK | All unit/widget tests | Everywhere |
| Deno test runner | deno 2.9.6 (installed) | Edge-function tests (`gemini-analyze/*_test.ts`) | The new `physique_checkin` kind |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `google_mlkit_face_detection 0.14.0` | 0.15.1 (latest) | 0.15.1 needs `google_mlkit_commons ^0.13` -> forces `google_mlkit_text_recognition` 0.17.1 too (a second, unrelated native upgrade). Not worth it this phase |
| Pixelate face region | Gaussian blur | Pixelation with a large block is harder to reverse than a light blur and is a single call in `image`; use `PixelateMode.average` on a cropped, inflated face rect |
| New `physique_photos` table | Add sync columns to legacy `ProgressPhotos` | Adding `SyncColumns` to an existing populated table needs the v25-style column add + uuid backfill + triggers; a new table is cleaner. Legacy table is drained and left in place (dropping it is a later migration) |
| `compute()`/`Isolate.run` for image work | Main isolate | Decoding a 12 MP JPEG is ~48 MB RGBA and blocks the UI; always run in an isolate |

**Installation:**
```bash
# pubspec.yaml: add under dependencies
#   google_mlkit_face_detection: ^0.14.0
# pubspec.yaml: MOVE `image: ^4.8.0` from dev_dependencies to dependencies
flutter pub get
```

**Version verification:** `google_mlkit_face_detection` versions and their `google_mlkit_commons` constraints were read from the pub.dev API on 2026-10-02: 0.13.2 (2026-02-03, commons ^0.11.0), **0.14.0 (2026-07-07, commons ^0.12.0, sdk >=3.8.0)**, 0.15.0 (2026-08-17, commons ^0.12.0, sdk ^3.12.0), 0.15.1 (2026-08-17, commons ^0.13.0). Lockfile: `google_mlkit_commons 0.12.0`, `google_mlkit_text_recognition 0.16.0`, `image 4.8.0` (latest 4.10.1, not needed), `fl_chart 0.69.2`. Toolchain: Flutter 3.44.8, Dart 3.12.2. [VERIFIED: pub.dev API, pubspec.lock]

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| google_mlkit_face_detection | pub.dev | multi-year (0.11.x in 2024, 0.14.0 July 2026) | ~110k / 30 days, 327 likes, 150 pub points | github.com/flutter-ml/google_ml_kit_flutter (same monorepo as the already-shipped `google_mlkit_text_recognition`) | n/a (see note) | Approved, publisher `flutter-ml.dev` is a verified pub.dev publisher |
| image | pub.dev | long-established (already in lockfile 4.8.0) | n/a | github.com/brendan-duncan/image | n/a | Approved (already resolved; only category move) |

**slopcheck note:** `slopcheck 0.6.1` installed, but it only checks PyPI/npm. Running it on the pub.dev package returned `[SLOP] does not exist on pypi`, which is a cross-ecosystem false positive, not a verdict. It does not support `--json` in this version. Legitimacy was instead established from the pub.dev API (verified publisher `flutter-ml.dev`, repo link, download/like counts) plus the fact the sibling package from the same monorepo is already a direct dependency. pub.dev packages have no npm-style `postinstall` scripts. The package was found from official pub.dev docs, not from a non-authoritative search.

**Packages removed due to slopcheck [SLOP] verdict:** none (the one SLOP result was a wrong-ecosystem false positive, documented above)
**Packages flagged as suspicious [SUS]:** none
**Recommended extra gate:** the planner should still put the `pubspec.yaml` edit behind a normal `flutter pub get` + `flutter analyze` check, and the first on-device run of face detection behind a `checkpoint:human-verify` (see Environment Availability: it cannot be exercised on this host).

## Architecture Patterns

### System Architecture Diagram

```
                  CAPTURE (image_picker, maxWidth/Height 2048)
                               |
                               v
        +-------------- PhysiquePhotoSanitizer (device) --------------+
        | 1. Isolate: decode -> bakeOrientation -> fresh ExifData     |
        |    (drop ICC) -> encodeJpg  => EXIF-free, upright temp file |
        | 2. if blur requested: FaceDetectorPort(temp file) -> boxes  |
        |    Isolate: crop inflated box -> pixelate -> composite back |
        | 3. write final to <docs>/physique/<goalUuid>/<uuid>.jpg      |
        | 4. delete temp + picker cache copy                          |
        +------------------------------+------------------------------+
                                       | relative file name only
                                       v
   +--------------- Repositories (data layer, drift transactions) ----------------+
   |  PhysiqueGoalRepository   PhysiqueRoadmapRepository                         |
   |  PhysiqueAssessmentRepository.recordCheckIn()  <-- ONLY writer of 'checkin' |
   |     tx { re-check 7-day cap via Clock -> insert photo + assessment }         |
   +---------+--------------------------+-----------------------------+----------+
             |                          |                             |
        drift tables (synced)      SyncService (metadata only)   Clock (core/utils)
  physique_goals / _assessments        -> Supabase RLS tables
  _roadmap_phases / _photos
             ^
             |  read (StreamProvider)
   +---------+----------------- Domain (pure Dart, no Flutter) -----------------+
   | PhaseEligibility (age, confidence)  PhysiqueTempoPolicy                    |
   | PhysiqueRoadmapGenerator (D-01)     RoadmapExitEvaluator (D-02)            |
   | CheckInCapPolicy (PHYS-06)          CheckInVerdictClassifier (PHYS-07)     |
   | TrendSeries (existing, Phase 28)    E1rmSeriesBuilder / TrainingLevelSeries|
   +---------+--------------------------------------+---------------------------+
             |                                      |
             v                                      v
   Progress screen (new route)            check-in flow: sanitise -> cap pre-check
   chips, bands, charts, deep-link        -> GeminiBackend.analyzePhysiqueCheckIn
   to /nutrition-targets (extra: DietPhase)   -> edge fn kind `physique_checkin`
                                              (consent gate, quota, whitelist,
                                               provenance) -> band+label+reason
                                              -> Dart classifier -> 3-state verdict
                                              -> recordCheckIn() persists
```

### Recommended Project Structure
```
lib/features/physique/                      # NEW feature; profile/ files stay in place
  domain/
    physique_guardrails.dart                # PhaseEligibility, RestrictionReason
    physique_tempo_policy.dart              # % bw/week ceilings, rate->kcal, duration
    physique_roadmap.dart                   # RoadmapPhaseDraft, PhysiqueRoadmapGenerator
    roadmap_exit_criteria.dart              # per-phase exit evaluation + advance offer
    check_in_policy.dart                    # 7-day cap maths (calendar-day based)
    check_in_verdict.dart                   # band, label, CheckInVerdict, classifier
    physique_series.dart                    # series builders for PHYS-08
  data/
    physique_goal_repository.dart
    physique_roadmap_repository.dart
    physique_assessment_repository.dart     # recordCheckIn + typed errors
    physique_photo_store.dart               # file layout, delete, resolve relative path
    physique_photo_sanitizer.dart           # isolate pipeline + FaceDetectorPort
    physique_legacy_migrator.dart           # SharedPreferences + ProgressPhotos -> goal
    physique_checkin_service.dart           # backend call + response parse
  application/
    physique_providers.dart                 # StreamProviders, eligibility, series
  presentation/                             # splits into views/sheets/widgets at 8 files
    views/physique_progress_view.dart
    widgets/ ...                            # phase card, verdict chip, range bar, charts
```
`DietPhase` (nutrition/domain) is reused as the phase type; persist `DietPhase.name`.

### Pattern 1: Synced-table recipe (copy v45/v46 exactly)
**What:** Table with `SyncColumns, SyncTombstone`, `@DataClassName`, registered in `@DriftDatabase`, `syncedTableNames`, `syncTableSpecs` (parent before child), guarded `onUpgrade` block, Supabase migration, parity + registration tests.
**When to use:** all four new tables.
**Example:**
```dart
// Source: lib/data/local/database.dart (v45/v46 blocks), tables.dart TdeeEstimates
@DataClassName('PhysiqueGoalData')
class PhysiqueGoals extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active | archived
  TextColumn get source => text().withDefault(const Constant('ai_analysis'))(); // ai_analysis | legacy_import | manual
  TextColumn get targetAestheticStyle => text()();
  RealColumn get targetBfPercent => real()();
  RealColumn get startWeightKg => real().nullable()();
  IntColumn get estimatedMonths => integer()();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  // ...
}

// onUpgrade (guarded, one block for all four tables)
if (from < 47 && to >= 47) {
  for (final (name, table) in [/* (sqlite name, table info) x4, parent first */]) {
    final exists = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='$name'",
    ).getSingleOrNull();
    if (exists == null) await m.createTable(table);
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_uuid_$name ON $name(sync_uuid)',
    );
  }
  await installSyncTriggers(this);
}
```

### Pattern 2: Typed gate in the repository, re-checked inside a transaction (PHYS-06)
**What:** The UI pre-checks to disable the button (D-13) but `recordCheckIn` is the real gate and runs the check *inside* `db.transaction` using the injected `Clock`.
**Example:**
```dart
// Source: house pattern (repository enforces; widget only reflects)
Future<CheckInResult> recordCheckIn({required int goalId, ...}) {
  return _db.transaction(() async {
    final last = await _latestCheckInAssessedAt(goalId, includeDeleted: true);
    final today = _clock.now();
    final next = CheckInCapPolicy.nextEligibleDate(lastCheckIn: last);
    if (!CheckInCapPolicy.isEligible(today: today, nextEligible: next)) {
      throw CheckInTooSoonException(nextEligibleDate: next!);
    }
    // insert physique_photos (role 'checkin') + physique_assessments in the same tx
  });
}
```

### Pattern 3: Sanitiser pipeline (EXIF strip + optional blur)
**What:** Always produce an upright, EXIF-free file first; run face detection on that file (no EXIF -> no rotation ambiguity between ML Kit's coordinate frame and the pixels); blur on the same decoded pixels; encode.
**Example:**
```dart
// Source: image 4.8.0 source (bake_orientation.dart, jpeg_encoder.dart, pixelate.dart)
Uint8List sanitizeJpeg(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const PhotoSanitizeException('Unreadable image');
  final upright = img.bakeOrientation(decoded);     // keeps OTHER exif tags!
  upright.exif = img.ExifData();                    // drop GPS, make/model, timestamps
  upright.iccProfile = null;
  return Uint8List.fromList(img.encodeJpg(upright, quality: 88));
}

img.Image pixelateRegion(img.Image src, ui.Rect box) {
  final r = box.inflate(box.shortestSide * 0.25);
  final x = r.left.floor().clamp(0, src.width - 1);
  final y = r.top.floor().clamp(0, src.height - 1);
  final w = r.width.ceil().clamp(1, src.width - x);
  final h = r.height.ceil().clamp(1, src.height - y);
  final face = img.copyCrop(src, x: x, y: y, width: w, height: h);
  final blurred = img.pixelate(face, size: (w ~/ 6).clamp(8, 64), mode: img.PixelateMode.average);
  return img.compositeImage(src, blurred, dstX: x, dstY: y);
}
```
Key fact: `bakeOrientation` copies *all* EXIF except orientation into the result, so assigning a fresh `ExifData()` afterwards is mandatory; relying on bake alone leaves GPS in place. [VERIFIED: `bake_orientation.dart`]

### Pattern 4: AI returns evidence, Dart returns the verdict
**What:** The edge function returns a closed-vocabulary response: a directional score band, a confidence label, a short reason and limitations. A pure-Dart classifier maps to on-track / off-track / inconclusive and may only *downgrade* using measured weight trend.
```
band = [lo, hi] in [-1, +1]   (-1 moving away from goal, +1 clearly toward goal)
inconclusive if label == low  OR  (hi - lo) > maxBandWidth  OR  lo <= +t && hi >= -t
onTrack     if lo >  +t        (t = 0.15 suggested)
offTrack    if hi <  -t
measured weight trend contradicting the phase direction downgrades onTrack -> inconclusive; never upgrades
```
Thresholds are Claude's discretion (CONTEXT) and are [ASSUMED] tuning constants to be named in a `PhysiqueTuning` class, same idiom as `TdeeTuning`.

### Anti-Patterns to Avoid
- **Absolute photo paths in the DB:** iOS app-container paths change across reinstall/update, and synced rows would carry a path meaningless on another device. Store a *relative* file name (`physique/<goalUuid>/<uuid>.jpg`) and resolve against `getApplicationDocumentsDirectory()` at read time. [ASSUMED: iOS container-path volatility is well-known platform behaviour, not re-verified here]
- **Doing the cap in the widget or in `MeasurementsRepository.addPhoto`:** the docs warn that a second path to the same method defeats the cap. Generic progress-photo inserts must be unable to create role `checkin`.
- **Running the legacy migration in drift `onUpgrade`:** it needs SharedPreferences, file I/O and image decoding; `onUpgrade` runs inside a migration transaction and must stay SQL-only.
- **Trusting `image_picker` to strip EXIF:** `maxWidth/imageQuality` resizing is not a guarantee of metadata removal. Always sanitise yourself. [ASSUMED: platform behaviour not tested here]
- **Importing `data/` from `domain/`:** `dream_physique_nutrition_recommendation.dart` (domain) currently imports `data/dream_physique_summary_repository.dart` for a model type, which breaks the layering rule. New domain files must declare their own plain input types.
- **Displaying a numeric percentage anywhere on the verdict UI** (D-11, PHYS-07). Show chip + range bar + one line only.
- **Editing `nutrition_targets_view.dart` (2618 lines) beyond the two gate call sites and chip filter.** It is already far over 600 lines; keep edits to a few lines and put logic in domain.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image decode / rotate / crop / pixelate / JPEG encode | Manual JPEG/EXIF byte surgery | `package:image` (`decodeImage`, `bakeOrientation`, `copyCrop`, `pixelate`, `compositeImage`, `encodeJpg`) | EXIF/IFD parsing and orientation maths are error-prone |
| Face localisation | Skin/blob heuristics | `google_mlkit_face_detection` | D-07; on-device, maintained |
| Bodyweight trend smoothing | New EWMA | Existing `TrendSeries.fromLogs` (`nutrition/domain/tdee_trend.dart`) | Handles gaps by interpolation, DST-safe `dayNumber` |
| 1RM estimate | New formula | Existing `OneRepMax.estimate` (`workouts/domain/one_rep_max.dart`, Epley+Brzycki avg, reps 1-12) | Single estimator used by analytics and gamification already |
| Weighted-bodyweight effective load | New load maths | Existing `effective_load.dart` | Keeps pull-up e1RM comparable with the rest of the app |
| Canonical lifts | New list | `PrimaryLift` enum + `preferredSlugs` (squat, deadlift, bench, OHP, pull-up; all five slugs exist in `assets/data/exercises.json`) | Same canon as Phase 22 specialisation |
| Phase calorie/macro maths | New calculator | `DietPhaseCalculator.apply` / `paceOptionsFor` | D-04; add an optional eligibility parameter, do not fork it |
| Sync wiring for new tables | Custom push/pull | `syncTableSpecs`, `syncedTableNames`, `installSyncTriggers` | SyncService handles uuid/FK/datetime conversion |
| Per-kind AI quota | New counter | `ai_usage_bump` RPC + `kindLimits`/`limitForKind` | Phase 26 (fails closed after one retry) |
| Time-of-day / day arithmetic | `DateTime.now()` | `Clock` (`core/utils/clock.dart`) and `DateTime(y, m, d + 7)` calendar arithmetic | CLAUDE.md rule; avoids DST drift from `Duration(days: 7)` |
| 7-day rate limit | Timer or widget state | Repository transaction + `CheckInCapPolicy` | PHYS-06 |

**Key insight:** every hard sub-problem here already has a house component. The new work is composition, a missing image pipeline, and getting the guardrail and cap into the one place that cannot be bypassed.

## Runtime State Inventory

> This phase migrates existing user data (summary history + progress photos) into new tables, so the inventory applies.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | (1) SharedPreferences keys `herculex.dream_physique_summary_history.v1` (<=20 entries) and legacy `herculex.dream_physique_summary.v1`; (2) SharedPreferences `DreamPhysiqueNutritionPreference` (keyed by `summaryAnalyzedAt`, in `dream_physique_nutrition_preference_repository.dart`); (3) drift `progress_photos` rows (`id, dateIso, pose, filePath, notes`, no sync, no goal FK); (4) JPEG files at `filePath`, which for legacy rows are `image_picker` **cache** paths; (5) drift `physique_programming_profiles` (synced, `musclePriorities`) | **Data migration** (idempotent app-level migrator, not `onUpgrade`): history -> assessments of one goal, latest entry defines goal target; photos copied through the sanitiser into `physique_photos`; originals deleted only after successful copy; missing sources skipped and counted. **Keep** `physique_programming_profiles` untouched (Phase 27 seam). Nutrition preference: map `selectedDirection`/`dismissed` onto the initial roadmap's first phase or drop it (document the choice) |
| Live service config | Supabase project `ldzgyzigvbwofbswitrv`: no `physique_*` tables yet; edge function `gemini-analyze` has no `physique_checkin` kind; `ai_usage` is keyed by `(user_id, day, kind)` and accepts any kind string | **Config + code edit** (new SQL migration, edge-function change, deploy). Both human-gated, as in 27-10 (confirm project ref via `supabase projects list`, verify with read-only queries) |
| OS-registered state | None for notifications/alarms/tasks (grep of `lib/services` and `lib/core` for "physique" only hits `gemini_backend_service.dart` and `pending_ai_scan_service.dart`). The latter holds `AiScanContextType.dreamPhysique`, a SharedPreferences marker written before `ImagePicker` opens so the app can resume after Android kills the activity | None to migrate. The new check-in capture should reuse this mechanism (add `physiqueCheckin` to the enum) and handle `retrieveLostData`, see Pitfall 14 |
| Secrets/env vars | New optional edge-function env `GEMINI_LIMIT_PHYSIQUE_CHECKIN` (default suggested 5); no client secrets | Add to `kindLimits`; document in the SQL/README note |
| Build artifacts / installed packages | `database.g.dart` (regenerate via `tool/codegen.ps1`), `drift_schemas/drift_schema_v47.json`, `test/generated_migrations/schema_v47.dart`, `pubspec.lock` (new native ML Kit pods/AAR), Android/iOS native builds pick up ML Kit models | Regenerate and commit; see five chores. First Android build after adding ML Kit is slow |

Account deletion: `local_data_wipe.dart` must (a) add the four new tables to `_fullyClearedTables` and (b) delete `physique_photos` files in addition to `progress_photos` files, otherwise deleting an account leaves special-category photos on disk. `test/auth/account_deletion_test.dart` exercises this path.

## Common Pitfalls

### Pitfall 1: Schema bump done as "just add tables"
**What goes wrong:** ~26 tests fail or sync silently quarantines (PGRST204).
**Why it happens:** the recipe has five coupled chores.
**How to avoid (concrete file list, derived from the v45/v46 precedent):**
1. `lib/data/local/tables.dart` (+4 tables), `lib/data/local/database.dart` (`@DriftDatabase` list, `schemaVersion` 46 -> **47**, guarded `if (from < 47 && to >= 47)` block).
2. `lib/data/local/migrations/sync_backfill.dart` `syncedTableNames` (+4), `lib/data/sync/sync_table_specs.dart` (+4; `physique_goals` level 0, `physique_assessments` and `physique_roadmap_phases` level 1 with `SimpleFk(goal_id)`, `physique_photos` level 2 with `SimpleFk(goal_id)` and nullable `SimpleFk(assessment_id)`; list every non-meta `DateTimeColumn` in `dateTimeColumns`).
3. `tool/codegen.ps1`, then `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/` and `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`.
4. Retarget tests: `test/migration_test.dart` (every `migrateAndValidate(db, 46)` -> 47, plus a new "upgrades from generated v46 fixture to v47" replay) and `test/schema_v27_test.dart`, `schema_v28_test.dart`, `schema_v29_test.dart` (`newVersion: 46` -> 47, `DatabaseAtV46` -> `DatabaseAtV47`); also check `schema_v21/24/25_test.dart` (one hard-coded `PRAGMA user_version`, per CLAUDE.md).
5. `supabase/migrations/2026MMDD000000_physique_v47.sql` modelled on `20260928000000_tdee_estimates_v45.sql` (RLS 4 policies per table, `set_updated_at` + `record_sync_tombstone` triggers, realtime publication, `(user_id, updated_at, id)` pull index). Add parity tests copied from `test/tdee_supabase_migration_test.dart` and a registration test copied from `test/tdee_sync_registration_test.dart` for all four tables.
**Warning signs:** `migration_test` failures naming `physique_*`; outbox rows with `lastError` containing `PGRST204`.

### Pitfall 2: One bump, four tables, but fixtures on both sides
**What goes wrong:** `createTable` throws on fixtures that already built the table from current definitions.
**How to avoid:** the `sqlite_master` guard shown in Pattern 1, per table. If any later step adds columns to these tables, guard with `pragma_table_info` (CLAUDE.md).

### Pitfall 3: CLAUDE.md says 0015/0016 are outstanding, but they are applied
**What goes wrong:** the planner adds an ordering dependency that no longer exists.
**Evidence:** STATE.md 2026-09-30 session note (27-10): `supabase migration list` showed 0015/0016 already applied remotely; only the newest file was pending, which the user then pushed. CLAUDE.md is stale on this. **Still** make the new migration push a human-gated checkpoint with `supabase projects list` ref confirmation and read-only verification queries (the exact 27-10 procedure).

### Pitfall 4: Consent gate bypass on the new image-bearing kind
**What goes wrong:** `index.ts` only demands `privacyConsent` when `payload.kind === "dream_physique"`. A new `physique_checkin` kind that accepts images would skip it.
**How to avoid:** generalise the check to `imageKinds.has(kind)` and add a Deno test asserting a `physique_checkin` request without `privacyConsent` returns 400 (mirror existing tests in `index_test.ts`). Reuse `dream_physique_images_v1`, or bump the version string if the notice text changes (then bump on both client constant `dreamPhysiqueImageConsentVersion` and server). Also set `Cache-Control: no-store` and the `privacy.imagesPersistedByHerculex: false` block like the dream-physique case.

### Pitfall 5: Image size vs the server cap
**What goes wrong:** `maxImageBase64 = 2_600_000` (~1.9 MB raw). A 2048-px q88 JPEG can approach this.
**How to avoid:** store the sanitised file at <=2048 px for display but send a downscaled <=1280 px copy (re-encode in the isolate) to the backend. Keep the total image count within `maxImages` (4 today): baseline 1-2 + current 1.

### Pitfall 6: Face detection coordinates vs EXIF rotation
**What goes wrong:** boxes land on the wrong region when the source has EXIF orientation 6/8.
**How to avoid:** run detection only on the already-baked, EXIF-free temp file (Pattern 3). [ASSUMED: ML Kit gives pixel-frame boxes for an orientation-1 file; verify on a real device with a rotated sample]. If zero faces are found and blur was requested, tell the user and let them save unblurred or retake; never claim "face blurred" without a detection (ML Kit commonly misses cropped or turned heads, and headless torso shots are normal for physique photos). Always `await detector.close()` in a `finally`.

### Pitfall 7: Fail-closed vs rollout when AI confidence is absent
**What goes wrong:** today's deployed prompt returns no BF range and no assessment-confidence label. If D-06 is implemented fail-closed (absent = low) before the new prompt is deployed, every dream-physique user gets restricted to maintain/recomp.
**How to avoid:** extend the prompt and `normalizeDreamPhysiqueResult` with `currentBfRangeMin/Max` and `assessmentConfidence` (`low|medium|high`), make the Dart parser accept absence as `unknown`, and treat `unknown` as restricted *only after* the edge function carrying the new fields is deployed (sequence the deploy before the client release; add a Dart-side constant gate if needed). Surface the "log measurements to refine" hint for `unknown` too.

### Pitfall 8: Two devices create two "active" goals
**What goes wrong:** the legacy migrator (or manual goal creation) runs offline on two devices; after sync both rows are `active`, breaking D-03.
**How to avoid:** define "active goal" as `status='active'` with the greatest `startedAt` (tie-break on `id`); a repository `reconcileSingleActive()` archives the others (a normal synced update) on startup/after pull. Make the migrator idempotent by a deterministic marker (`source='legacy_import'` goal exists) plus a SharedPreferences done-flag. A SQLite partial unique index cannot enforce this across devices, so do not rely on one.

### Pitfall 9: 7-day cap edge cases
**What goes wrong:** DST makes `Duration(days: 7)` land an hour early/late; deleting the last check-in re-opens the window; two rapid taps double-submit; clock changes.
**How to avoid:** compute `nextEligible = DateTime(last.y, last.m, last.d + 7)` in local calendar days and compare calendar dates (`dateIso`, as `TdeeEstimates` does); include soft-deleted check-ins in the lookup (a deletion must not reset the cap; AI quota was spent); do the check inside the transaction; disable the button while a submit is in flight. Document the unavoidable limit: two offline devices can each record one check-in within a window before syncing.

### Pitfall 10: Legacy `ProgressPhotos` sources are probably cache paths
**What goes wrong:** the migrator assumes the file exists, throws mid-way, or deletes originals after a partial copy.
**How to avoid:** process per row: `File.exists` -> sanitise -> insert; collect failures; commit rows in one transaction; delete originals only for rows that copied, and only after the transaction commits. Report "N photos could not be recovered" once, non-fatally. Never delete a row whose copy failed (the row is the only record).

### Pitfall 11: "Training level" accidentally wired to XP
**What goes wrong:** the obvious `levelProgressProvider` / `LevelBand` (novice/intermediate/advanced) comes from the XP ledger (`gamification/domain/level_progress.dart`, `/training-level` route). Plotting it breaks the explicit CONTEXT/blueprint rule.
**How to avoid:** build the series from `ExperienceLevel.recommend(...)` evaluated at sample dates over workout history (see Open Question 2) and assert in a test that the series builder imports nothing from `features/gamification/`.

### Pitfall 12: Behaviour regression for users with no age
**What goes wrong:** applying D-05 in the editor removes Cut/Bulk for any profile where `ageYears == null`. `Profile.isComplete` requires age and onboarding collects it, so this should be rare, but existing installs may have null.
**How to avoid:** the editor shows the restriction with a clear "Add your age in Profile" action (deep-link to profile) rather than a silent removal; add a widget test. Confirm with the user in plan review (Open Question 4).

### Pitfall 14: Camera capture killed by the OS on Android
**What goes wrong:** the activity is destroyed while the camera is open and the check-in flow loses its goal/pose context; the photo is orphaned in cache.
**How to avoid:** follow the existing pattern in `measurements_view.dart` (set `PendingAiScanContext` before `pickImage`, clear after) with a new `AiScanContextType.physiqueCheckin`, carrying `goalId` and pose in `extra`; resume through the same hook `app.dart`/`main_scaffold.dart` already use. New code uses `Clock`, not `DateTime.now()` (the existing capture sites call `DateTime.now()` directly).

### Pitfall 13: Existing five test files and Phase 27 consumers
**What goes wrong:** replacing `DreamPhysiqueSummaryRepository` breaks `dream_physique_summary_*`, `dream_physique_nutrition_*`, `dream_physique_priorities_view_test` and the block-builder (`summary.estimatedMonths`, `dialogs.part.dart`).
**How to avoid:** keep the `DreamPhysiqueAnalysisSummary` model and the provider names (`dreamPhysiqueSummaryProvider`, `dreamPhysiqueSummaryHistoryProvider`). Re-implement them as a bridge over the DB-backed active goal; keep the SharedPreferences repository class only as the one-shot migration source.

## Code Examples

### Tempo: preset capped by % bodyweight / week (D-04)
```dart
// Source: composition over DietPhaseCalculator.apply (weeklyRateKg * 1000 kcal convention)
class PhysiqueTempoPolicy {
  // Named, not inlined (Claude's discretion; cited ranges below).
  static const cutCeilingPctPerWeek = 1.0;      // Helms 2014: 0.5-1 %/wk
  static const bulkCeilingPctPerWeek = 0.5;     // Iraki 2019: 0.25-0.5 %/wk (novice/intermediate)
  static const maingainCeilingPctPerWeek = 0.15;// [ASSUMED]

  static double weeklyKg({required DietPhase phase, required double bodyweightKg,
      required double presetWeeklyKg}) {
    final ceilingPct = switch (phase) {
      DietPhase.cut => cutCeilingPctPerWeek,
      DietPhase.bulk => bulkCeilingPctPerWeek,
      DietPhase.maingain => maingainCeilingPctPerWeek,
      _ => 0.0,
    };
    return math.min(presetWeeklyKg, bodyweightKg * ceilingPct / 100);
  }
  static int plannedWeeks({required double deltaKg, required double weeklyKg}) =>
      weeklyKg <= 0 ? 0 : (deltaKg.abs() / weeklyKg).ceil();
}
```
Note: the existing preset table offers up to 1.0 kg/week, which is 1.67 %/wk for a 60 kg person, so the ceiling will bind for lighter users.

### Eligibility inside the single calorie choke point (PHYS-04)
```dart
// Source: extends lib/features/nutrition/domain/diet_phase.dart
static PhaseTargets apply({
  /* existing params... */
  PhaseEligibility? eligibility,           // null = unchanged behaviour
}) {
  var delta = /* existing derivation */;
  if (eligibility != null) delta = eligibility.clampDelta(phase, delta); // restricted -> 0 or <= +150
  // ...rest unchanged
}
```
`PhaseEligibility.evaluate({int? ageYears, AssessmentConfidence? confidence})` returns allowed phases: minor / age unknown -> `{maintain, recomp, maingain(<=+150 kcal)}`; low/unknown confidence (roadmap context only) -> `{maintain, recomp}`.

### Chart: weight with phase-target band (fl_chart 0.69.2)
```dart
// Source: fl_chart-0.69.2 axis_chart_data.dart (RangeAnnotations / HorizontalRangeAnnotation)
LineChartData(
  rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
    HorizontalRangeAnnotation(y1: band.lowKg, y2: band.highKg,
        color: hx.domainNutrition.withValues(alpha: 0.14)),
  ]),
  lineBarsData: [LineChartBarData(spots: trendSpots, isCurved: true)],
);
```
For a band that *moves* with the roadmap (target weight per week), use two invisible `LineChartBarData` plus `betweenBarsData: [BetweenBarsData(fromIndex: 0, toIndex: 1, color: ...)]`.

### e1RM time series (new query; none exists)
```dart
// Source: pattern from analytics_repository.topOneRms (filters: completed, !warmup, not deleted)
// Add: setType == 'standard', LoggingMetric.isRepBased && isLoaded, exercise slug IN PrimaryLift slugs,
// group by session day -> max OneRepMax.estimate(effective load, reps) per day.
```
Use effective load for bodyweight-loaded lifts, exclude non-standard set types (the blueprint rule: no strength signal from warmup/assisted/drop/myo sets). Put this query in a repository (UI never touches drift).

### Edge-function kind skeleton (Deno)
```ts
// Source: supabase/functions/gemini-analyze/index.ts patterns (dream_physique, program_brief)
// 1) GeminiKind += "physique_checkin"; kindLimits.physique_checkin = Number(Deno.env.get("GEMINI_LIMIT_PHYSIQUE_CHECKIN") ?? "5");
// 2) kindDisplayNames.physique_checkin = "Physique check-ins";
// 3) consent gate: if (imageKinds.has(payload.kind) && !validConsent) return json({error}, 400)
// 4) case "physique_checkin": validateImages(...) -> generateJson({images, promptText: physiqueCheckinPrompt(ctx),
//      systemInstruction: nutrition /* or core */, temperature: 0.2}) -> normalizePhysiqueCheckin(raw)
//    return json({result, provenance: {modelVersion, knowledgeVersion: KNOWLEDGE_VERSION}}) + no-store header
// normalizePhysiqueCheckin: whitelist {directionBand:{low,high}, confidence:'low'|'medium'|'high', reason, limitations[]},
//   clamp band to [-1,1], reject any percent-like field, strip experience-level guesses.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Dream Physique summary in SharedPreferences, 20-entry cap | Synced drift tables + goal/assessment/roadmap model | This phase | Needs legacy migrator; keep summary model as a bridge |
| Progress photos: local-only pointer table, picker cache path, no goal FK | Sandboxed relative-path photos, EXIF stripped, synced metadata | This phase | New `physique_photos` table; legacy table drained |
| Single "direction" suggestion card (`DreamPhysiqueNutritionRecommender`) | Ordered, editable multi-phase roadmap with exit criteria | This phase | First roadmap phase should equal the old recommender result (regression test) |
| Shared 50/day AI quota failing open | Per-kind quota failing closed after one retry | Phase 26 (migration 0021) | Add `physique_checkin` kind, not a new mechanism |
| Free-text AI results | Whitelisted/normalised responses with `modelVersion` + `knowledgeVersion` provenance | Phases 26/27 | PHYS-07 follows the `program_brief` shape |

**Deprecated/outdated:**
- CLAUDE.md "0015 and 0016 are both outstanding": stale per STATE.md (27-10 note); already applied remotely.
- CLAUDE.md "`nutrition_targets_view.dart` ~1450 lines": actual 2618 lines.
- ROADMAP success text lists four phase types (`cut, maintain, recomp, bulk`); REQUIREMENTS PHYS-03/05 and CONTEXT include `maingain`. Implement all five (the existing `DietPhase` enum already has them).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `maingainCeilingPctPerWeek = 0.15` | Code Examples (tempo) | Mis-sized maingain pacing; low stakes, tunable constant |
| A2 | iOS app-container path changes across reinstall/update, so relative paths are required | Anti-Patterns | If wrong, relative paths are merely harmless extra safety |
| A3 | `image_picker` resizing does not reliably strip EXIF (esp. GPS) | Anti-Patterns | If it did, sanitising is redundant but still required by spec |
| A4 | ML Kit returns pixel-frame boxes for an EXIF-free orientation-1 file | Pitfall 6, Pattern 3 | Blur lands on wrong region; **needs a real-device check** |
| A5 | iOS deployment target 13.0 in `project.pbxproj`/Podfile is incompatible with ML Kit face detection (pub.dev states iOS 15.5, Xcode 15.3+) | Environment Availability | iOS build fails at `pod install`. Note text recognition is already a dependency, so verify what the current iOS build actually does |
| A6 | Band thresholds (`t = 0.15`, max band width 0.8), default `GEMINI_LIMIT_PHYSIQUE_CHECKIN = 5` | Pattern 4, Runtime State | Verdicts too eager/too timid; tunable |
| A7 | Training-level series derived from `ExperienceLevel.recommend` over workout history (see Open Question 2) | Pitfall 11 | Chart semantics differ from what the user expects; needs confirmation |
| A8 | Cap lookup includes soft-deleted check-ins | Pitfall 9 | If undesired, deleting a check-in reopens the window (simpler, bypassable) |
| A9 | Roadmap generator rule table (cut -> maintain -> bulk/maingain; first phase equals old recommender; optional 2-week maintain between a long cut and a bulk) | Architecture Patterns | Roadmap proposals feel unrealistic; user can edit (D-01), so low harm |
| A10 | GDPR: processing physique photos/BF for under-18s may need parental consent (Art. 8 age of digital consent differs by member state) | Security Domain | Compliance gap; needs a human/legal answer, not a code answer |
| A11 | iCloud backup of the Documents directory could carry physique photos off-device on iOS | Open Questions | Privacy gap vs "private local" promise; needs native `isExcludedFromBackup` or a different directory |

## Open Questions

1. **Where does the low-confidence gate apply?**
   - What we know: D-06 says low confidence restricts to maintain/recomp; D-05 (minor) is unambiguous and global.
   - What's unclear: whether low confidence should also restrict the *manual* nutrition editor, or only roadmap generation/advancement and the deep-link preset.
   - Recommendation: minors/unknown age gate the roadmap AND the editor (otherwise the editor is a bypass); low confidence gates the roadmap and the preset phase only, because the editor is a deliberate manual act not derived from a visual assessment. Confirm with the user.

2. **What is "training level" over time (PHYS-08)?**
   - What we know: must be `ExperienceLevel`/strength standards, not XP rank; the blueprint says population percentiles are not in v1 (own confirmed progress). No strength-standards table exists in the repo.
   - What's unclear: a historical series needs inputs; `ExperienceLevel.recommend` takes `consistentTrainingMonths`, `sessionsLast12Weeks`, `understandsRirRpe`, `hasRunStructuredBlocks`; the last two have no history.
   - Recommendation: step line over 3 levels from `recommend()` sampled weekly, with months/sessions computed from `workout_sessions`, and the two unknowns fixed at their *current* stored value (or false, capping the line at intermediate). Alternative: relative-strength tiers from e1RM/bodyweight with static thresholds (needs a new constants table, flagged [ASSUMED]). Planner/discuss decision; default to the first.

3. **What happens when the AI check-in call fails?**
   - Recommendation: do not consume the cap or persist anything on failure; offer "Save photo without verdict", which persists with verdict `inconclusive` and reason "Herculex AI unavailable" and does count toward the cap.

4. **Missing-age regression.** Confirm that removing Cut/Bulk from the manual editor for `ageYears == null` is acceptable, with a Profile deep-link.

5. **iOS deployment target and iCloud backup exclusion.** Could not be tested on Windows. Verify `pod install` with the ML Kit pods and decide on a native method-channel to set `NSURLIsExcludedFromBackupKey` for the physique folder.

6. **Check-in baseline.** Which photos does the AI compare against: the goal's baseline assessment photos, or the previous check-in? Recommendation: baseline (PHYS-07 says "against the baseline"), with the previous check-in as optional context only.

7. **GDPR memo update.** `docs/GDPR_ARTICLE_9_COMPLIANCE.md` currently states progress photos are "strictly local... never sent to Supabase". Photo *metadata* now syncs and photos go to Gemini for assessment (already true for Dream Physique). The memo needs an edit and the under-18 question (A10) needs an owner.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter / Dart | build, tests | yes | Flutter 3.44.8 / Dart 3.12.2 | none needed |
| drift_dev / build_runner | codegen, schema dump/generate | yes (dev deps) | ^2.21.0 | none needed |
| Deno | edge-function tests | yes | 2.9.6 | none needed |
| Supabase CLI | migration push + verification | yes | 2.115.0 | manual SQL via dashboard |
| Python + slopcheck | package audit | yes | slopcheck 0.6.1 (npm/PyPI only) | pub.dev API check (done) |
| Android emulator / device with Play Services | ML Kit face detection run | unknown | not probed | unit tests use a fake `FaceDetectorPort`; real-device check as a human-verify checkpoint |
| macOS + Xcode + CocoaPods | iOS pod install for ML Kit | no (Windows host) | none | Defer iOS verification to a human checkpoint; note A5 |
| Network access to Supabase `ldzgyzigvbwofbswitrv` | pushing v47 SQL | requires user go-ahead | n/a | human-gated, as in 27-10 |

**Missing dependencies with no fallback:** none blocking planning or Dart/Deno execution.
**Missing dependencies with fallback:** real ML Kit execution and iOS pods (cannot be exercised here); fake detector for tests plus human-verify checkpoints.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK 3.44.8); Deno test for edge functions |
| Config file | none (standard `test/` discovery); `tool/check_structure.dart` for layout |
| Quick run command | `flutter test test/features/physique` |
| Full suite command | `flutter test > test_output.txt 2>&1` (redirect, do not pipe to `tail`; `tr '\r' '\n'` before grepping). Last recorded baseline in STATE.md: 1627 passed / 9 skipped (Phase 28); Phase 22 research targeted 1721+. Use the count recorded at the start of Phase 23 execution as the floor |
| Static gates | `flutter analyze` (0 errors), `dart run tool/check_structure.dart`, `dart format lib test tool` |
| Edge function | `deno test --allow-env --allow-net supabase/functions/gemini-analyze/` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PHYS-01 | v46 -> v47 migration replay; four tables exist; sync_uuid unique indexes; outbox row on insert | migration/integration | `flutter test test/migration_test.dart test/physique_sync_registration_test.dart` | migration_test exists (retarget); registration test Wave 0 |
| PHYS-01 | Supabase SQL parity: every drift column present in Postgres, RLS 4 policies, triggers, realtime, index | text-level | `flutter test test/physique_supabase_migration_test.dart` | Wave 0 (copy of tdee test) |
| PHYS-01 | Legacy migrator: summary history -> assessments, photos copied, idempotent re-run, missing source skipped, originals deleted only after success | unit (temp dir + in-memory DB) | `flutter test test/features/physique/physique_legacy_migrator_test.dart` | Wave 0 |
| PHYS-02 | Sanitiser: output has no EXIF (GPS/make/model absent), orientation baked, dimensions preserved; unreadable input -> typed error | unit (synthetic JPEG built with `image`, EXIF injected) | `flutter test test/features/physique/physique_photo_sanitizer_test.dart` | Wave 0 |
| PHYS-02 | Blur: fake `FaceDetectorPort` returns a box; pixels inside differ, outside identical; zero faces -> reported, not silently "blurred" | unit | same file | Wave 0 |
| PHYS-02 | Wipe removes physique photo files and new tables | integration | `flutter test test/auth/account_deletion_test.dart` | exists (extend) |
| PHYS-03 | Tempo caps preset by % bw/week; plannedWeeks maths; first roadmap phase == old recommender direction (regression); editable-draft invariants (reorder/resize/delete keep order indices dense) | unit | `flutter test test/features/physique/physique_roadmap_test.dart test/features/physique/physique_tempo_policy_test.dart` | Wave 0 |
| PHYS-04 | Eligibility matrix (age <18, null, 18, low confidence, unknown) x phases; `DietPhaseCalculator.apply` clamps only when eligibility passed; default behaviour unchanged | unit | `flutter test test/features/physique/physique_guardrails_test.dart test/diet_phase_test.dart` | guardrails Wave 0; diet-phase test location to confirm |
| PHYS-04 | Editor hides/blocks restricted phases at both call sites; deep-link `extra` coerced | widget | `flutter test test/features/nutrition` (new case) | extend |
| PHYS-05 | Exit evaluator per phase (weight reached, BF reached, duration elapsed via fake `Clock`); advance offer; postpone suppresses prompt until date; never writes targets | unit | `flutter test test/features/physique/roadmap_exit_criteria_test.dart` | Wave 0 |
| PHYS-05 | Progress screen names active phase, position "2 of 4", time in phase, exit criteria | widget | `flutter test test/features/physique/physique_progress_view_test.dart` | Wave 0 |
| PHYS-06 | Second check-in within 7 days throws `CheckInTooSoonException` with correct date; day 7 allowed; DST boundary; soft-deleted check-in still counts; per-goal isolation; concurrent submits (two futures) -> exactly one succeeds | unit (in-memory DB + fake Clock) | `flutter test test/features/physique/physique_assessment_repository_test.dart` | Wave 0 |
| PHYS-06 | Button disabled with "Next check-in available <date>" | widget | progress view test | Wave 0 |
| PHYS-07 | Classifier truth table (label low, wide band, straddle, clear toward/away, weight-trend downgrade, never upgrade); no `%` string in any rendered verdict | unit + widget | `flutter test test/features/physique/check_in_verdict_test.dart` | Wave 0 |
| PHYS-07 | Edge function: consent required for `physique_checkin`; quota per kind; normaliser rejects percent fields, clamps band, strips experience guesses; provenance has `modelVersion` + `knowledgeVersion` | Deno unit | `deno test --allow-env --allow-net supabase/functions/gemini-analyze/` | extend `index_test.ts`, `usage_test.ts`; add `physique_checkin_test.ts` |
| PHYS-07 | Dart parser tolerant of absent confidence (`unknown`) and rejects malformed band | unit | `flutter test test/features/physique/physique_checkin_service_test.dart` | Wave 0 |
| PHYS-08 | Series builders: weight trend + band, e1RM per canonical lift (standard sets only, effective load, 1M/3M/All windowing), training level series; builder imports nothing from `features/gamification/` | unit | `flutter test test/features/physique/physique_series_test.dart` | Wave 0 |
| PHYS-08 | Charts render with empty and sparse data without throwing | widget | progress view test | Wave 0 |
| Compat | Existing summary/direction/priorities tests still pass through the bridge; Phase 27 `estimatedMonths` consumers unchanged | unit/widget | `flutter test test/dream_physique_summary_repository_test.dart test/dream_physique_summary_card_test.dart test/dream_physique_nutrition_recommendation_test.dart test/dream_physique_nutrition_direction_card_test.dart test/dream_physique_priorities_view_test.dart test/block_builder_view_test.dart` | exist |
| Layout | New files <=600 lines, no `domain/` importing `data/`/Flutter, routes via `AppRoutes` | static | `dart run tool/check_structure.dart` | exists |

### Sampling Rate
- **Per task commit:** `flutter test test/features/physique` plus the specific touched test file; `flutter analyze <touched paths>`.
- **Per wave merge:** the Compat row above, `test/migration_test.dart`, `test/auth/account_deletion_test.dart`, `deno test` for edge function waves, full `flutter analyze`, `dart run tool/check_structure.dart`.
- **Phase gate:** full `flutter test` green (>= baseline recorded at execution start, plus new tests, 0 failures), 0 analyzer errors, `check_structure` passes, edge-function Deno tests pass, before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/features/physique/` directory with all domain tests listed above (pure Dart; no framework install needed).
- [ ] `test/physique_sync_registration_test.dart` and `test/physique_supabase_migration_test.dart` (copy from the tdee pair, four tables).
- [ ] A fake `FaceDetectorPort` and a synthetic-EXIF JPEG fixture builder (in `test/support/`), since ML Kit cannot run under `flutter test`.
- [ ] A fake `Clock` helper for repository tests if `test/support/` lacks one (check before creating).
- [ ] `supabase/functions/gemini-analyze/physique_checkin_test.ts`.
- [ ] Human-verify checkpoints (not automatable here): real-device face blur on a rotated sample; Supabase v47 push + read-only verification queries; iOS `pod install`/run.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (unchanged) | existing Supabase auth; edge function reads `sub` via `callerUserId` |
| V3 Session Management | no | unchanged |
| V4 Access Control | yes | Postgres RLS owner-only policies on all four new tables (`user_id = auth.uid()`), tested by SQL parity tests; repository gate for the cap |
| V5 Input Validation | yes | Dart `fromJson` validation with typed `FormatException`; edge-function whitelist normaliser; image decode failure handled; size/count limits (`maxImageBase64`, `maxImages`); closed verdict vocabulary; clamp band values |
| V6 Cryptography | no new | none hand-rolled; photos protected by app sandbox + `allowBackup=false` on Android (verified in manifest) |
| V8 Data Protection | yes | special-category data (GDPR Art. 9): EXIF/GPS stripped, optional face blur, bytes never synced, wipe on account deletion, `Cache-Control: no-store` on image responses |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| GPS/device metadata leaking via EXIF | Information Disclosure | Always re-encode with a fresh `ExifData`; test asserts no EXIF tags |
| Photos uploaded to AI without consent | Information Disclosure | Extend server consent gate to every image kind (Pitfall 4) |
| Prompt injection via photo text or user note changing the verdict | Tampering | Prompt states to ignore embedded instructions (existing wording); server whitelists output; AI never writes to DB; Dart classifies |
| Rate-limit bypass through a second code path | Elevation of Privilege | Repository is the only writer of `checkin` rows; transaction re-check |
| Absolute-path or traversal in synced photo rows | Tampering | Store/resolve relative file names only; reject names containing `..` or separators on read |
| Orphaned photo files after delete/archive | Information Disclosure | Photo store deletes files on row delete and in `wipeAllLocalUserData` |
| Minor receiving aggressive calorie targets | Tampering / safety | Domain-layer `PhaseEligibility` at the single calorie choke point |
| AI over-confident visual claims | Spoofing (credibility) | Band + label, never a percentage; fail-closed to inconclusive |
| Child data and consent (GDPR Art. 8) | Compliance | Open Question 7 / A10 — owner needed |

## Sources

### Primary (HIGH confidence)
- Codebase reads, 2026-10-02: `lib/features/nutrition/domain/diet_phase.dart`, `lib/features/profile/domain/dream_physique_nutrition_recommendation.dart`, `lib/features/profile/data/dream_physique_summary_repository.dart`, `dream_physique_service.dart`, `dream_physique_nutrition_preference_repository.dart`, `lib/data/local/{tables,database,local_data_wipe}.dart`, `lib/data/local/migrations/sync_backfill.dart`, `lib/data/sync/sync_table_specs.dart`, `lib/features/measurements/data/measurements_repository.dart`, `measurements_view.dart`, `nutrition_targets_view.dart` (gate comments at ~204, ~1447), `tdee_estimator.dart:263`, `tdee_trend.dart`, `one_rep_max.dart`, `primary_lift_specialization.dart`, `programming_models.dart` (`ExperienceLevel`), `gamification/presentation/training_level_view.dart`, `app/router/{routes,router}.dart`, `services/ai/gemini_backend_service.dart`, `supabase/functions/gemini-analyze/{index,prompts,knowledge_base}.ts`, `supabase/migrations/20260928000000_tdee_estimates_v45.sql`, `0021_ai_usage_bump_per_kind.sql`, tests `tdee_sync_registration_test.dart`, `tdee_supabase_migration_test.dart`, `migration_test.dart`, `schema_v2*_test.dart`, `docs/ARCHITECTURE.md`, `docs/herculex-ai-plan-2026-09-27.md` section 6, `docs/GDPR_ARTICLE_9_COMPLIANCE.md`, `.planning/STATE.md`, `.planning/phases/28-*/28-CONTEXT.md`, `.planning/phases/22-*/22-RESEARCH.md` and `22-VERIFICATION.md`.
- `image-4.8.0` package source in pub cache: `formats/jpeg_encoder.dart`, `transform/bake_orientation.dart`, `filter/pixelate.dart`, `filter/gaussian_blur.dart`, `transform/copy_crop.dart`.
- `fl_chart-0.69.2` package source: `RangeAnnotations`, `HorizontalRangeAnnotation`, `BetweenBarsData` present.
- pub.dev API (versions, dependency constraints, publisher `flutter-ml.dev`, like/download counts) for `google_mlkit_face_detection`, `google_mlkit_text_recognition`, `image`: https://pub.dev/api/packages/google_mlkit_face_detection
- pub.dev package page: https://pub.dev/packages/google_mlkit_face_detection (iOS 15.5 / Xcode 15.3+, Android minSdk 21; `FaceDetectorOptions`; boxes via `boundingBox`)
- Helms ER, Aragon AA, Fitschen PJ. Evidence-based recommendations for natural bodybuilding contest preparation. J Int Soc Sports Nutr 2014: https://pmc.ncbi.nlm.nih.gov/articles/PMC4033492/ (0.5-1 % bodyweight/week loss)

### Secondary (MEDIUM confidence)
- Iraki J et al. Nutrition recommendations for bodybuilders in the off-season: a narrative review. Sports 2019 (0.25-0.5 % bodyweight/week gain for novice/intermediate): https://elementssystem.com/wp-content/uploads/2019/07/iraki-nutrition-bodybuilders-2019-sports-07-00154.pdf and https://www.researchgate.net/publication/334044740_Nutrition_Recommendations_for_Bodybuilders_in_the_Off-Season_A_Narrative_Review (found via WebSearch; the summary text was not re-read in the PDF)

### Tertiary (LOW confidence)
- iOS container-path volatility, `image_picker` EXIF behaviour, ML Kit coordinate frame on EXIF-free input, iCloud backup of Documents: training knowledge, not verified in this session (A2-A5, A11).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH for versions/constraints (read from registry and lockfile); MEDIUM on runtime behaviour of ML Kit (not executed).
- Architecture: HIGH; every integration seam was read in the codebase and the schema recipe has two worked precedents.
- Pitfalls: HIGH for codebase-derived ones (consent gate, cache-path photos, XP vs training level, stale CLAUDE.md notes, file sizes); MEDIUM/LOW for platform-behaviour ones (flagged `[ASSUMED]`).

**Research date:** 2026-10-02
**Valid until:** 2026-10-16 for package versions (ML Kit packages released twice in August 2026); 30 days for the architecture findings unless Phase 29/24/25 land first and bump the schema (then the target version number shifts from 47).
