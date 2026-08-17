# RB-01 Gemini Secret Remediation

Date: 2026-08-13

> ⚠️ **Wrong project (corrected 2026-08-15).** Every `jioesomepkauponjrena`
> reference below is the **SummitSki** project, not Herculex. Herculex's real
> backend is **`ldzgyzigvbwofbswitrv`**. The code remediation described here is
> unaffected, but the deployment close-out landed in the wrong project. The
> `gemini-analyze` function was redeployed to `ldzgyzigvbwofbswitrv` on
> 2026-08-15; **`GEMINI_API_KEY` still has to be set there** before AI food
> analysis works.

## Status

RB-01 is closed as of 2026-08-13.

Flutter no longer ships, accepts, stores, or directly uses a Gemini API key.
Gemini requests now go through the Supabase Edge Function at
`supabase/functions/gemini-analyze/index.ts`.

External close-out was completed after code remediation:

- `GEMINI_API_KEY` is present as a Supabase project secret on
  `jioesomepkauponjrena`.
- `gemini-analyze` is deployed and active on `jioesomepkauponjrena`.
- Supabase reports `verify_jwt = true` for the deployed function.

The value pasted into chat was not written to the repo or to a local secrets
file by this session. It was treated as exposed and not reused by Codex.

## What Changed

- `lib/features/nutrition/data/gemini_food_analyzer_service.dart` delegates food
  photo and nutrition-label fallback analysis to a `GeminiBackend` abstraction.
- `lib/services/ai_service.dart` delegates exercise-image identification to the
  same backend instead of using `google_generative_ai`.
- `lib/features/nutrition/presentation/gemini_photo_analysis_dialog.dart` no
  longer shows an API-key entry panel or stores user-provided Gemini keys.
- `lib/services/gemini_backend_service.dart` invokes the Supabase Edge Function
  when Supabase is configured, and reports AI as unavailable in local-only
  builds.
- `supabase/config.toml` sets `verify_jwt = true` for `gemini-analyze`.
- `pubspec.yaml` / `pubspec.lock` no longer include `google_generative_ai`.

## Verification

Ran:

```bash
flutter test test/gemini_food_analyzer_service_test.dart
flutter analyze lib/services/gemini_backend_service.dart lib/services/ai_service.dart lib/features/nutrition/data/gemini_food_analyzer_service.dart lib/features/nutrition/presentation/gemini_photo_analysis_dialog.dart test/gemini_food_analyzer_service_test.dart
rg -n "GEMINI_API_KEY|google_generative_ai|GenerativeModel|x-goog-api-key|gemini_api_key|setApiKey|hasCustomApiKey|AIzaSy|aistudio|generativelanguage.googleapis.com" lib test pubspec.yaml supabase
```

Results:

- Focused tests passed.
- Focused analyzer passed.
- Flutter-side secret scan is clean. Remaining Gemini key/API endpoint matches
  are server-side Edge Function code or explanatory text.
- `npx supabase functions deploy gemini-analyze --project-ref
  jioesomepkauponjrena --use-api` succeeded from the repo root.
- `npx supabase functions list --project-ref jioesomepkauponjrena` reports
  `gemini-analyze` as `ACTIVE` with `verify_jwt: true`.
- `npx supabase secrets list --project-ref jioesomepkauponjrena` reports
  `GEMINI_API_KEY` present.

Full `flutter analyze` was attempted but did not finish within the 120 second
tool timeout on this worktree, so the verification above is intentionally
focused on RB-01 touched files.
