# Herculex Android Auth + Wear Sync Setup

This repository now includes native Kotlin scaffolding for:

- Firebase Authentication in `android/app/src/main/kotlin/com/ams/herculex/auth/`
- Offline-first Wear OS data-layer sync in `android/app/src/main/kotlin/com/ams/herculex/sync/`
- Wear-side data-layer handling in `android/wear/src/main/java/com/ams/herculex/sync/`

## 1. Firebase project wiring

Firebase project:

- Project ID: `herculex-8bf9f`

Required Android setup:

1. In Firebase Console, add the Android app with package name `com.ams.herculex`.
2. Register both debug and release SHA-1 and SHA-256 fingerprints.
3. Download `google-services.json`.
4. Place it at `android/app/google-services.json`.
5. In Firebase Console, enable these providers:
   - Email/Password
   - Google
   - Apple

Recommended Gradle plugin step once `google-services.json` is available:

```kotlin
// android/settings.gradle.kts
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
    id("com.google.gms.google-services") version "4.4.3" apply false
}
```

```kotlin
// android/app/build.gradle.kts
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
```

## 2. Google Sign-In setup

1. In Firebase Console, open Authentication > Sign-in method > Google and enable it.
2. Copy the Web client ID from the Google provider config.
3. Pass that Web client ID into `FirebaseAuthRepository.buildGoogleSignInIntent(...)`.
4. Use the same Web client ID when handling the result in `signInWithGoogleResult(...)`.

Example:

```kotlin
private const val FIREBASE_WEB_CLIENT_ID =
    "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"
```

## 3. Apple Sign-In setup for Android

Firebase Android uses OAuth for Apple Sign-In.

In Firebase Console:

1. Open Authentication > Sign-in method > Apple.
2. Configure:
   - Apple Service ID
   - Apple Team ID
   - Key ID
   - Private key
3. Add the Android redirect URI shown by Firebase to your Apple Service ID configuration.

The repository method `signInWithApple(activity)` is already written to use `OAuthProvider("apple.com")`.

## 4. Email/Password setup

No extra client code is needed beyond enabling Email/Password in Firebase Console.

Use:

```kotlin
repository.registerWithEmail(
    email = "athlete@herculex.app",
    password = "strong-password",
    displayName = "Athlete",
)

repository.loginWithEmail(
    email = "athlete@herculex.app",
    password = "strong-password",
)
```

## 5. Wear data-layer usage

Persistent state uses `DataClient`:

- `/herculex/state/active_workout`
- `/herculex/state/macro_targets`
- `/herculex/state/user_token`

Transient realtime events use `MessageClient`:

- `/workout/start_rest_timer`
- `/workout/update_weight`
- `/workout/finish`

Mobile-side examples:

```kotlin
val syncManager = MobileWearSyncManager(context)

syncManager.syncActiveWorkoutSession(sessionJson)
syncManager.syncMacroTargets(macroTargetsJson)
syncManager.syncUserToken(firebaseIdToken)

syncManager.sendRealtimeEvent(
    WearSyncPaths.MESSAGE_START_REST_TIMER,
    """{"durationSeconds":90}""",
)
```

Watch-side examples:

```kotlin
val syncManager = WearDataLayerSyncManager(context)

syncManager.pushActiveWorkoutSession(sessionJson)
syncManager.sendRealtimeEvent(
    WearSyncPaths.MESSAGE_UPDATE_WEIGHT,
    """{"exerciseIndex":2,"weight":100.0,"reps":5}""",
)
```

## 6. Offline-first behavior

The new sync managers follow this pattern:

- `DataClient` is used for durable state, so Google Play services can forward it after reconnection.
- The latest persistent state is also cached locally in `SharedPreferences`.
- `MessageClient` events are queued locally when no node is reachable.
- On `onPeerConnected(...)`, each side:
  - replays the latest persistent state
  - flushes queued transient messages

That gives you immediate local writes plus best-effort fast delivery once Bluetooth or Wi-Fi returns.
