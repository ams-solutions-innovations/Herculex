/// Thrown by a sign-in method that hands the browser over to an OAuth
/// provider (Google on the web) instead of completing in place.
///
/// Not a failure: the page is about to navigate away, and the session arrives
/// when the provider redirects back and supabase_flutter exchanges the code.
/// Callers show a "redirecting" state rather than an error.
class AuthRedirectStarted implements Exception {
  const AuthRedirectStarted(this.provider);

  final String provider;

  @override
  String toString() => 'Redirecting to $provider…';
}
