# Herculex Auth (Supabase) + Wear Sync Setup

Replaces `android-native-firebase-wear-setup.md`. Firebase was removed in the
Supabase cutover; the Wear half of the old document was still accurate and is
carried over verbatim in §5–§6.

Auth now lives entirely in Dart (`lib/features/auth/`), not in Kotlin. There is
no `com.ams.herculex/auth` MethodChannel any more, and `MainActivity.kt` only
registers the wear and widget channels.

## 1. Why Supabase

- **iOS auth works for the first time.** The Firebase implementation was
  Android-only Kotlin — no Podfile, no `GoogleService-Info.plist`, no native
  code — so every auth call on iOS threw `MissingPluginException`.
  `supabase_flutter` is pure Dart.
- Auth, Postgres, Realtime, Storage and Edge Functions come from one backend
  with one identity (`auth.uid()`), which is what the cloud-sync work needs.

## 2. Project configuration

Create a Supabase project, then supply credentials at build time. There is no
`.env` file — the app uses `--dart-define` for everything (see
`lib/core/env.dart`).

```
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-or-anon-key> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<...>.apps.googleusercontent.com
```

The anon/publishable key is a **public** client credential. It identifies the
project; it authorises nothing. Row Level Security is the actual boundary — see
`supabase/migrations/*_rls.sql`. Shipping it in the binary is expected.

`Env.hasSupabase` is false when the defines are absent, and every
Supabase-touching path is guarded by it, so the app still builds and runs
fully local-first without a backend. Tests rely on this.

## 3. Redirect URL

In the dashboard: **Authentication → URL Configuration → Additional Redirect
URLs**, add:

```
io.supabase.herculex://login-callback/
```

This must stay in sync with three places:

- `Env.authCallbackUrl` (`lib/core/env.dart`)
- the Android intent-filter in `android/app/src/main/AndroidManifest.xml`
- the iOS `CFBundleURLTypes` entry in `ios/Runner/Info.plist`

Used by email confirmation and password-reset links. Native Google sign-in does
not need it.

## 4. Providers

### Email / password
Enable in **Authentication → Providers → Email**. No client code needed beyond
`registerWithEmail` / `loginWithEmail`. If "Confirm email" is on, `signUp`
returns a user but **no session** — `SupabaseAuthService._require` surfaces
"Check your email to confirm your account, then sign in."

### Google
Uses the native account-picker flow (`google_sign_in` → `signInWithIdToken`),
not a browser redirect.

1. Reuse the existing Google Cloud project (`herculex-8bf9f`) or create a new one.
2. Create a **Web** OAuth client → its client ID is `GOOGLE_WEB_CLIENT_ID`.
   Supabase verifies the ID token against this on *every* platform, which is why
   it is passed as `serverClientId`, not `clientId`.
3. Create an **Android** OAuth client with package `com.ams.herculex` and both
   the debug and release SHA-1 fingerprints. Without this the ID token comes
   back null.
4. Create an **iOS** OAuth client → `GOOGLE_IOS_CLIENT_ID`.
5. In Supabase, enable the Google provider and paste the Web client ID + secret.

> The old `google-services.json` had `"oauth_client": []` — no SHA-1 was ever
> registered, so Google sign-in never actually worked. Expect it to start
> working, not to regress.

### Apple
Native on iOS/macOS via `sign_in_with_apple`. On Android the button throws a
clear error: the web flow needs an Apple Service ID and is not configured yet.

Apple sends the user's display name **only on the first authorization** —
`signInWithApple` captures it into `user_metadata.full_name` at that moment.

## 5. Wear data-layer usage

Unchanged by the cutover. `play-services-wearable` stays; the watch is a peer of
the phone, not a Supabase client.

Persistent state uses `DataClient`:

- `/herculex/state/active_workout`
- `/herculex/state/macro_targets`

Transient realtime events use `MessageClient`:

- `/workout/start_rest_timer`
- `/workout/update_weight`
- `/workout/finish`

```kotlin
val syncManager = MobileWearSyncManager(context)
syncManager.syncActiveWorkoutSession(sessionJson)
syncManager.syncMacroTargets(macroTargetsJson)
syncManager.sendRealtimeEvent(
    WearSyncPaths.MESSAGE_START_REST_TIMER,
    """{"durationSeconds":90}""",
)
```

> `syncUserToken(firebaseIdToken)` from the old doc is gone. The watch does not
> need a bearer token — it talks to the phone, and the phone talks to Supabase.

## 6. Offline-first behavior (wear)

- `DataClient` carries durable state, so Play services forwards it after reconnect.
- The latest persistent state is also cached in `SharedPreferences`.
- `MessageClient` events are queued locally when no node is reachable.
- On `onPeerConnected(...)` each side replays the latest persistent state and
  flushes queued transient messages.

## 7. Migration notes

- **All existing users must sign in again once.** Supabase issues new UUIDs;
  a cached Firebase uid is meaningless. Nothing in Drift stores a user id, so
  no local training or nutrition data is affected.
- The orphaned `herculex.auth_id_token` secure-storage entry is deleted on
  first run by `LocalAuthRepository._purgeLegacyToken()`.
- The Supabase session (including the refresh token) is stored via
  `SecureAuthStorage` — Keychain on iOS, Keystore-backed
  EncryptedSharedPreferences on Android — not plain SharedPreferences.
- ⚠️ `android/app/google-services.json` was git-tracked with a live API key.
  Deleting the file does not remove it from history: **rotate or restrict that
  key in Google Cloud Console.**
