/// Compile-time configuration, supplied via `--dart-define`.
///
/// The app deliberately has no `.env` file or dotenv dependency. Client-safe
/// build-time values arrive through `--dart-define`; real server secrets, such
/// as `GEMINI_API_KEY`, live only in backend secret storage.
///
/// The Supabase anon key is a *public* client credential: it identifies the
/// project, it does not authorise anything. Row Level Security is the actual
/// boundary. Shipping it in the binary is expected and safe; see
/// `supabase/migrations/*_rls.sql`.
abstract final class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// OAuth client IDs for native Google sign-in. The *web* client id is what
  /// Supabase verifies the ID token against, so it is required on every
  /// platform; the iOS client id is additionally needed by `google_sign_in`
  /// on Apple platforms.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const oneSignalAppId = String.fromEnvironment('ONESIGNAL_APP_ID');

  /// Deep-link target for OAuth redirects. Must match the Android
  /// intent-filter, the iOS `CFBundleURLTypes` entry, and the Supabase
  /// dashboard's "Additional Redirect URLs" list.
  static const authCallbackUrl = 'io.supabase.herculex://login-callback/';

  /// False in tests and in dev builds that were started without credentials.
  /// Every Supabase-touching code path is guarded by this so the app still
  /// runs fully offline/local-first when unconfigured.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasGoogleSignIn => googleWebClientId.isNotEmpty;
}
