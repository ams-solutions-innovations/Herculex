# Phase 26: Herculex AI Knowledge Base & Brand Unification - Pattern Map

**Mapped:** 2026-09-27
**Files analyzed:** 29 (3 new TS, 1 new SQL migration, 4 modified TS/SQL, 1 extended Dart test,
~20 Dart string-rename files treated as one homogeneous group)
**Analogs found:** 29 / 29 (every file has at least a role-match; note the one **correction to
RESEARCH.md** below — the Dart brand-default test file it flagged as possibly not existing
**does exist** and is read in full here)

RESEARCH.md already contains verified, line-numbered code excerpts for the four core mechanics
(`system_instruction` body shape, `modelVersion` threading, `limitForKind()`, the corrected
`ai_usage_bump` SQL, `bumpUsage()`'s fail-closed retry). This file does not repeat those — it
adds the three things the mapper brief asked for: concrete test-file analogs for the 3
new/extended `*_test.ts` files, confirmation (with a correction) of the Dart brand-consistency
test situation, and a consistency check across the ~20-file Dart rename set.

## Correction to RESEARCH.md

RESEARCH.md's Wave-0-gaps section says of the Dart brand-default test: "does not appear to exist
today — verify during planning; not found in this session's search." **It exists:**
`test/gemini_food_analyzer_service_test.dart` (287 lines, read in full this session). It already
covers `analyzeFoodPhoto`/`analyzeNutritionLabel`/`analyzeRamblerText` against a
`_FakeGeminiBackend`, and its fake backend's `analyzeFoodPhoto` response at line 101 currently
returns `'brand': 'Gemini AI'` explicitly (not omitted), so Pitfall 3's recommended new
assertion — "log a food photo with a response *missing* `brand`, assert the stored value falls
back to `'Herculex AI'`" — is a new `test(...)` block appended to this existing file, not a new
file. This is a **modified file**, not new, and its own existing fixture data (line 101,
`'brand': 'Gemini AI'`) itself needs updating consistent with D-18 (test fixtures are not
historical user data, so update them to the new brand) or left as an intentional
"stored-JSON-included-old-brand" regression case — planner's call, flag explicitly either way.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `supabase/functions/gemini-analyze/knowledge_base.ts` (new) | config/utility | transform (static string export) | `supabase/functions/gemini-analyze/prompts.ts` | exact |
| `supabase/functions/gemini-analyze/knowledge_base_test.ts` (new) | test | unit | `supabase/functions/gemini-analyze/prompts_test.ts` | exact |
| `supabase/functions/gemini-analyze/index_test.ts` (new) | test | unit | `supabase/functions/gemini-analyze/prompts_test.ts` | role-match (no prior test of `index.ts`) |
| `supabase/functions/gemini-analyze/usage_test.ts` (new) | test | unit (mocked `fetch`) | `supabase/functions/gemini-analyze/prompts_test.ts` | role-match (no prior fetch-mock pattern in repo — see below) |
| `supabase/migrations/0021_ai_usage_bump_per_kind.sql` (new) | migration | CRUD (SECURITY DEFINER fn) | `supabase/migrations/0018_shared_data_hardening.sql` | exact (already fully excerpted in RESEARCH.md) |
| `supabase/functions/gemini-analyze/index.ts` (modified) | route/controller (`Deno.serve`) | request-response | itself (existing file, extend in place) | n/a — already fully excerpted in RESEARCH.md |
| `supabase/functions/gemini-analyze/prompts.ts` (modified) | utility | transform | itself | n/a — single literal swap, line 36 per RESEARCH.md |
| `supabase/functions/gemini-analyze/prompts_test.ts` (modified) | test | unit | itself | n/a — add one assertion |
| `test/gemini_food_analyzer_service_test.dart` (modified, exists) | test | unit | itself (see Correction above) | exact |
| `lib/features/nutrition/data/gemini_food_analyzer_service.dart` (modified) | service (data layer) | transform (JSON → model) | n/a — editing in place | n/a |
| `lib/features/nutrition/presentation/dialogs/gemini_photo_analysis_dialog.dart` (modified) | component/dialog | request-response (display) | see "Dart rename group" below | consistent |
| `lib/features/profile/presentation/dream_physique_view.dart` (modified) | component/view | request-response (display) | see "Dart rename group" below | consistent, but has 2 sentinel exceptions |
| ~18 other Dart presentation/dialog/data files (full list in RESEARCH.md's Brand Rename Inventory) | component/dialog/service | display (string literal only) | each other — homogeneous group, see below | consistent, no deviations found |

## Pattern Assignments

### `supabase/functions/gemini-analyze/knowledge_base_test.ts`, `index_test.ts`, `usage_test.ts` (test, unit)

**Analog:** `supabase/functions/gemini-analyze/prompts_test.ts` (the only Deno test file that
exists anywhere in this repo — verified via `Glob("supabase/functions/**/*_test.ts")`, one hit).

**Full file** (38 lines, use as the structural template for all three new/extended test files):
```typescript
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  barcodeProductPrompt,
  dreamPhysiquePrompt,
  foodPhotoPrompt,
  nutritionLabelPrompt,
} from "./prompts.ts";

Deno.test("dream physique prompt carries the programming and privacy contract", () => {
  const prompt = dreamPhysiquePrompt(
    {},
    "Prioritize symmetry",
  );

  assert(prompt.includes('"schemaVersion": 1'));
  assert(prompt.includes('"muscleId": "chest"'));
  assert(prompt.includes("maintenance"));
  assert(prompt.includes("Never infer or return training experience"));
  assert(prompt.includes("Do not include an experienceLevel field anywhere"));
  assert(prompt.includes("Do not choose a final exercise list"));
  assert(prompt.includes('"targetAestheticStyle"'));
  assert(prompt.includes("All human-readable descriptions"));
  assert(prompt.includes("Athletic, defined V-taper physique"));
  assertEquals(prompt.includes('"experienceLevel":'), false);
});

Deno.test("food prompts require a practical, physically grounded portion", () => {
  const photo = foodPhotoPrompt();
  const label = nutritionLabelPrompt("Serving size: 30 g");
  const barcode = barcodeProductPrompt("4006381333931");

  for (const prompt of [photo, label, barcode]) {
    assert(prompt.includes('"portionAmount"'));
    assert(prompt.includes('"portionUnit"'));
  }
  assert(photo.includes("Never use ml for meat"));
  assert(label.includes("Do not use ml for solid foods"));
});
```

**Conventions to copy:**
- Single `import { assert, assertEquals } from "jsr:@std/assert@1";` — no other assertion
  library anywhere in the repo. Use this for all three new files, not `@std/testing/asserts` or
  any other import path.
- Named import of the module under test via a **relative `./...ts` path** (Deno convention,
  distinct from Dart's `package:herculex/...` rule in CLAUDE.md — that rule does not apply to
  `supabase/functions/`).
- One `Deno.test("<plain-English behavior sentence>", () => { ... })` per behavior, not one
  per function — group related assertions (see the two tests above each covering multiple
  prompt functions in one block).
- Assertions are plain `assert(x.includes(...))` / `assertEquals(a, b)` on string content —
  no snapshot testing, no mocking library imported.
- Run command confirmed live this session: `deno test supabase/functions/gemini-analyze/prompts_test.ts`
  → `ok | 2 passed | 0 failed (39ms)`.

**Per-file specifics:**
- `knowledge_base_test.ts` — same shape exactly: import `core`, `programming`, `nutrition`,
  `recovery`, `KNOWLEDGE_VERSION` from `./knowledge_base.ts` and assert non-empty strings, the
  `kb-YYYY.MM-N` version format (D-09), and — since `generate()`'s `system_instruction` field
  is the injection point (D-01) — a direct assertion on the constructed request body shape is
  more valuable than a live call; consider exporting a small pure helper (e.g.
  `buildSystemInstruction(text)`) from `index.ts` or `knowledge_base.ts` so this test can assert
  `{ parts: [{ text }] }` without hitting the network.
- `index_test.ts` — genuinely new territory (no `Deno.serve` handler is unit-tested anywhere in
  this repo today). RESEARCH.md's Wave-0 note is correct that `limitForKind()`, `bumpUsage()`,
  and the provenance-envelope construction should be extracted into small pure/testable
  functions as part of this phase's refactor — the analog for *those* extracted functions'
  tests is still this same `Deno.test(...)` + `assert`/`assertEquals` shape, just targeting the
  extracted functions directly rather than the full HTTP handler.
- `usage_test.ts` — **no existing analog for mocking `fetch`** anywhere in this repo (only
  `prompts_test.ts` exists, and it tests pure string functions with no I/O). This is the one
  gap in this phase's test coverage with zero precedent to copy. Deno's native `fetch` can be
  stubbed by reassigning `globalThis.fetch` for the duration of a test (standard Deno pattern,
  not repo-specific) — structure the test file the same way as the other two (same import line,
  same `Deno.test("<behavior>", ...)` blocks) but add a `try { globalThis.fetch = fakeFetch; ...
  } finally { globalThis.fetch = originalFetch; }` wrapper per test, since there's no existing
  helper to copy for this.

---

### `test/gemini_food_analyzer_service_test.dart` (test, unit — modified, not new)

**Analog:** itself — extend in place. Full relevant structure (see Correction section above for
the full 287-line read):

**Imports** (lines 1-6):
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
```

**Core pattern** (fake backend + service under test, lines 8-29, 84-113):
```dart
void main() {
  test(
    'food photo analysis is delegated to the server-side Gemini backend',
    () async {
      final backend = _FakeGeminiBackend();
      final service = GeminiFoodAnalyzerService(backend);
      final image = await _tempImage('.png');

      final result = await service.analyzeFoodPhoto(
        imageFile: image,
        userNote: 'large bowl',
      );

      expect(backend.lastKind, 'food_photo');
      expect(backend.lastMimeType, 'image/png');
      expect(backend.lastUserNote, 'large bowl');
      expect(result.name, 'Test meal');
      expect(result.kcalPer100g, 123);
      expect(result.portionAmount, 1);
      expect(result.portionUnit, 'scoop');
    },
  );
  // ...
}

class _FakeGeminiBackend implements GeminiBackend {
  String? lastKind;
  String? lastMimeType;
  String? lastUserNote;
  String? lastOcrText;

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    lastKind = 'food_photo';
    lastMimeType = mimeType;
    lastUserNote = userNote;
    return {
      'name': 'Test meal',
      'brand': 'Gemini AI',            // <-- update per D-18/Pitfall 3, see below
      'estimatedServingGrams': 250,
      'portionAmount': 1,
      'portionUnit': 'scoop',
      'kcalPer100g': 123,
      // ...
    };
  }
  // ...
}
```

**Pattern for the new Pitfall-3 brand-default test:** add a fourth `test(...)` block that
constructs a `_FakeGeminiBackend`-like response **omitting** the `brand` key entirely (or a
second fake/override returning a map without `'brand'`), then asserts
`result.brand == 'Herculex AI'` — mirroring the existing three tests' shape exactly (arrange
fake backend → act via `service.analyzeFoodPhoto(...)` → assert on the returned
`GeminiFoodAnalysisResult`). No new test infrastructure needed; this file's existing
`_FakeGeminiBackend` class is reusable — just don't set `'brand'` in the map returned by one
test's override, or add a second minimal fake.

**Existing fixture note:** line 101's `'brand': 'Gemini AI'` in `_FakeGeminiBackend` is a
*hardcoded model-response fixture*, not the code under test — its assertion (line 24 checks
`result.name` etc., never `result.brand`) doesn't currently exercise the brand default at all,
so this fixture can be updated to `'Herculex AI'` for cleanliness (D-18 doesn't protect test
fixtures, only real stored rows) without weakening any existing assertion.

---

### Dart rename group (~20 files, component/dialog/service role, display data flow)

**Consistency check result:** confirmed uniform. Grepped `Gemini` directly in
`rambler_food_dialog.dart`, `label_capture_dialog.dart`, `dream_physique_view.dart`,
`gemini_photo_analysis_dialog.dart`, `body_fat_ai_dialog.dart`,
`exercise_ai_scan_dialog.dart`, `gemini_backend_service.dart`, and
`gemini_food_analyzer_service.dart` this session. Every display-string occurrence is a plain
string literal (`'...Gemini AI...'` or a Slovenian equivalent), assigned directly to a `Text(...)`
widget, a tooltip `message:`, a thrown `Exception(...)`, or a local `_error =` field. **No
occurrence uses string interpolation of the word "Gemini" itself** (two lines do interpolate,
`'OCR/Gemini analiza ni uspela: $e'` and `'Error connecting to Gemini AI: $e'`, but only `$e`
varies — "Gemini" itself is still a static literal segment, safe to find-and-replace). **No
occurrence reads from a shared constant** (e.g. no `AppStrings.geminiLabel` — each site repeats
its own literal). **No file is referenced from more than one place** in a way that would change
this — each is a local widget-tree string, not a shared branded-constant.

**One representative pattern** — a typical tooltip/label rename site
(`lib/features/measurements/presentation/body_fat_ai_dialog.dart:244`):
```dart
'Gemini AI Body Fat Estimation',   // → 'Herculex AI Body Fat Estimation'
```

**Two deviations flagged, both already identified in RESEARCH.md, restated here for planner
visibility since they are the only files in the group that are NOT a simple 1:1 literal swap:**

1. `dream_physique_view.dart:307-309` — is a **3-way string-matching coupling**, not a display
   string in isolation:
   ```dart
   if (message.contains('Gemini API request failed (401)') ||
       message.contains('Gemini server authorization failed')) {
     return 'Gemini is not authorised on the server yet. Your photos are '
   ```
   Lines 307-308 (`.contains(...)`) match against `index.ts`'s sentinel error strings verbatim
   — leave those two `.contains(...)` literals untouched per RESEARCH.md's Pitfall 1
   recommendation. Only line 309's **return value** ("Gemini is not authorised..." → "Herculex
   AI is not authorised...") is a safe, ordinary rename.
2. `dream_physique_view.dart:819` — the one **Keep** (protected consent) string per D-15; not a
   plain rename, needs reworded text naming Google Gemini explicitly
   ("Herculex AI (powered by Google Gemini)" per D-15/RESEARCH.md, pending legal-doc wording
   check per the Open Questions in RESEARCH.md).

All other ~34 sites across this group (including the four **Data** sites —
`gemini_food_analyzer_service.dart:24,40,52` and `gemini_photo_analysis_dialog.dart:145` — which
are default-value expressions, not `Text(...)` widgets, but are still simple literal
replacements in code, just not display-only) are uniform 1:1 literal swaps with no widget
restructuring required.

---

### `lib/features/nutrition/data/gemini_food_analyzer_service.dart` (service/data layer, transform)

**Core pattern** (the 4-site Data disposition from RESEARCH.md's Pitfall 3, grep-confirmed this
session):
```dart
class GeminiFoodAnalysisResult {
  const GeminiFoodAnalysisResult({
    // ...
    this.brand = 'Gemini AI',                              // line 24 → 'Herculex AI'
    // ...
  });

  factory GeminiFoodAnalysisResult.fromJson(Map<String, dynamic> json) {
    return GeminiFoodAnalysisResult(
      // ...
      brand: json['brand'] as String? ?? 'Gemini AI',       // line 40 → 'Herculex AI'
      // ...
      ratingReason:
          json['ratingReason'] as String? ?? 'Evaluated with Gemini AI.',  // line 52 → '...Herculex AI.'
    );
  }
}
```
Confirms RESEARCH.md's line numbers exactly; no deviation found. `gemini_photo_analysis_dialog.dart:145`
(`brand: _result?.brand ?? 'Gemini AI'`) is the fourth site in the same coupled group and must
change in the same task per Pitfall 3.

## Shared Patterns

### Deno test file shape (all 3 new/extended `*_test.ts` files)
**Source:** `supabase/functions/gemini-analyze/prompts_test.ts` (full file excerpted above)
**Apply to:** `knowledge_base_test.ts`, `index_test.ts`, `usage_test.ts`
- `import { assert, assertEquals } from "jsr:@std/assert@1";`
- Relative `./*.ts` imports of the module under test (Deno convention; does not conflict with
  CLAUDE.md's `package:herculex/...` rule, which is Dart-only)
- One `Deno.test("<behavior sentence>", () => {...})` block per behavior

### Brand string literal swap (Dart display strings)
**Source:** any of the ~20 files in the Dart rename group (pattern is identical across all of
them — see above)
**Apply to:** all files in RESEARCH.md's Brand Rename Inventory table marked "Rename," except
the two sentinel-matching lines in `dream_physique_view.dart:307-308` (leave untouched) and the
one consent string at line 819 (reword per D-15, not a plain swap)
- Find `'...Gemini AI...'` / `'...Gemini...'` literal → replace with `'...Herculex AI...'`,
  preserving surrounding sentence structure and any Slovenian text
- No shared constant to introduce or update — each site owns its own literal (confirmed, no
  deviation)

### Stored `brand` data value (4-site coupled group)
**Source:** `lib/features/nutrition/data/gemini_food_analyzer_service.dart` lines 24, 40, 52 +
`lib/features/nutrition/presentation/dialogs/gemini_photo_analysis_dialog.dart:145` +
`supabase/functions/gemini-analyze/prompts.ts:36` (server-side JSON-schema instruction, already
excerpted in RESEARCH.md)
**Apply to:** exactly these 5 locations, atomically in one task — verified via grep this session,
matches RESEARCH.md's Pitfall 3 exactly, no additional sites found

### Quota-exhausted error message (currently generic, becomes kind-specific per D-14)
**Source:** `supabase/functions/gemini-analyze/index.ts` lines 164-175 (read directly this
session — a concrete excerpt RESEARCH.md did not quote verbatim):
```typescript
const quota = await bumpUsage(userId, payload.kind ?? "unknown");
if (!quota.allowed) {
  return json(
    {
      error:
        `Dnevna kvota za AI analize (${quota.limit}/dan) je presežena. Poskusi jutri.`,
      used: quota.used,
      limit: quota.limit,
    },
    429,
  );
}
```
**Apply to:** the `index.ts` task implementing D-14. Note the call site is currently
`bumpUsage(userId, payload.kind ?? "unknown")` — a 2-arg call with no limit argument at all
today (the limit is looked up/defaulted inside `bumpUsage` itself in the pre-Phase-26 code);
D-12's fix requires this call site to become 3-arg (`bumpUsage(userId, kind, limitForKind(kind))`)
and the error string to be templated per-kind (e.g. naming "photo food scans" not "AI analize")
per D-14's example wording in CONTEXT.md.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `supabase/functions/gemini-analyze/usage_test.ts` fetch-mocking helper | test | unit (mocked I/O) | No existing Deno test in this repo stubs `fetch` or any I/O — `prompts_test.ts` tests pure string functions only. Use Deno's native `globalThis.fetch` reassignment (standard Deno idiom, not repo-specific); no in-repo precedent to copy beyond the outer `Deno.test`/`assert` shape. |

## Metadata

**Analog search scope:** `supabase/functions/gemini-analyze/` (all 3 existing files),
`supabase/functions/` (confirmed no other `*_test.ts` exists repo-wide), `test/` (confirmed
`gemini_food_analyzer_service_test.dart` exists and was misreported as absent by RESEARCH.md),
and the ~8 representative files grepped from RESEARCH.md's 22-file Brand Rename Inventory to
confirm rename-shape consistency.
**Files scanned:** 3 TS source files, 1 TS test file (read in full), 1 Dart test file (read in
full), 8 Dart source files (grepped for `Gemini` occurrences and cross-checked against
RESEARCH.md's inventory), `index.ts` imports + switch-dispatch header (read directly for line
numbers).
**Pattern extraction date:** 2026-09-27
