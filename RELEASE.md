# Release checklist

Herculex is a local-first app backed by Supabase for authentication, cloud
sync, and serverless AI label/meal analysis. This checklist covers backend
provisioning, platform packaging, and store submission.

## 1. Backend provisioning (Supabase)

### Database migrations
Ensure every migration in `supabase/migrations/` (`0001` through `0013` as of
2026-08-19) is applied to the production Supabase project. The full workflow —
install, auth, link, inspect, apply — is in `docs/supabase-migrations.md`; the
short version is:
```bash
npx supabase migration list   # confirm local == remote first
npx supabase db push
```

### Edge Functions & Secrets
Set the server-side Gemini API key and deploy all three functions. `SUPABASE_URL`
and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform and must NOT be set
by hand:
```bash
npx supabase secrets set GEMINI_API_KEY="<your-gemini-api-key>"
npx supabase functions deploy gemini-analyze --use-api
npx supabase functions deploy product-catalogue-publish --use-api
npx supabase functions deploy delete-account --use-api
```

`--use-api` bundles server-side. Without it the CLI bundles in Docker, and on a
machine with no Docker daemon running the deploy fails with an opaque
`EFTYPE: inappropriate file type or format, uv_spawn` rather than saying so.

`delete-account` is not optional: without it the in-app "Delete Account" button
fails, and an app that offers account creation but no working deletion is
rejected under App Store Guideline 5.1.1(v).

### Build-time compile arguments
Production builds require the Supabase URL and anonymous key (plus optional OAuth client IDs for Google Sign-In) passed at compile time via `--dart-define` or `--dart-define-from-file`:
```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://<your-project-id>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id> \
  --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>
```

---

## 2. Confirm the application / bundle ID

The placeholder `com.example.*` has been replaced with **`com.ams.herculex`** in:

- `android/app/build.gradle.kts` (`namespace`, `applicationId`)
- `android/app/src/main/kotlin/com/ams/herculex/MainActivity.kt` (package)
- `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`)

> ⚠️ The application ID is **permanent** once published. If `com.ams.herculex`
> is not the reverse form of a domain you control, change it now (search & replace
> the three locations above) before the first upload.

## 3. Android release signing

A keystore is **not** committed. The build reads `android/key.properties` when
present and otherwise falls back to debug signing (so `flutter run --release`
still works locally). To produce an uploadable build:

```bash
# Generate an upload keystore (keep the .jks and passwords safe & backed up)
keytool -genkey -v -keystore ~/herculex-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties` (git-ignored):

```properties
storePassword=••••••
keyPassword=••••••
keyAlias=upload
storeFile=/absolute/path/to/herculex-upload.jks
```

Then:

```bash
flutter build appbundle --release   # → build/app/outputs/bundle/release/app-release.aab
```

R8 shrinking/obfuscation is enabled; keep rules live in
`android/app/proguard-rules.pro`. Smoke-test the release build on a device before
uploading (R8 can strip code the rules miss).

## 4. iOS release signing

Open `ios/Runner.xcworkspace` in Xcode → Signing & Capabilities → select your
team and a provisioning profile for `com.ams.herculex`, then:

```bash
flutter build ipa --release
```

## 5. Permissions / privacy

Declared permissions and their justification (needed for store privacy forms):

| Permission | Used for |
| --- | --- |
| Camera | Barcode scanning and food packaging OCR |
| Internet | Supabase sync/auth, OpenFoodFacts product lookup, Gemini label analysis |
| Notifications | Active-workout lock-screen status and timers |
| Foreground service (health) | Keeping the active-workout notification alive |

Data collection:
- **Local-first by default**: unauthenticated usage stores all workouts, nutrition logs, and profile data solely on-device.
- **When signed in**: user-created workout history, nutrition logs, and custom entries sync securely to Supabase PostgreSQL protected by Row Level Security (`user_id = auth.uid()`).
- **AI features**: food photos/labels sent for OCR are routed via secure Supabase Edge Function to Google Gemini; no user credentials or personal history leave the device.

## 6. Store assets still required

- App icon set (`flutter_launcher_icons` or the existing `scripts/generate_icons.py`).
- Screenshots per required device size.
- Short + full description, privacy-policy URL.

## 7. Pre-flight

```bash
flutter analyze        # expect: no issues
flutter test           # expect: all green
flutter build apk --release   # or appbundle
```
