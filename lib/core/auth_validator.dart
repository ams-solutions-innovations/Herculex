import 'dart:math';

/// Validation rules and character constraints for authentication inputs.
///
/// Designed to minimize spam, prevent DoS payload attacks, and enforce
/// safe character limits on usernames, emails, and passwords.
class AuthValidator {
  AuthValidator._();

  /// Standard RFC 5322 compliant regex pattern for email validation.
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  /// Alphanumeric with spaces, underscores, and hyphens.
  static final RegExp _usernameRegExp = RegExp(r'^[a-zA-Z0-9 _-]+$');

  /// Maximum allowed characters for username / display name.
  static const int maxUsernameLength = 30;

  /// Minimum required characters for username / display name.
  static const int minUsernameLength = 2;

  /// Maximum allowed characters for email (RFC 5321 standard).
  static const int maxEmailLength = 254;

  /// Minimum password length for security.
  static const int minPasswordLength = 8;

  /// Maximum password length to prevent bcrypt/argon2 hashing CPU DoS.
  static const int maxPasswordLength = 72;

  /// Validates an email address. Returns an error message if invalid, or null if valid.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address.';
    }
    final trimmed = value.trim();
    if (trimmed.length > maxEmailLength) {
      return 'Email must not exceed $maxEmailLength characters.';
    }
    if (!_emailRegExp.hasMatch(trimmed)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  /// Validates a password. Returns an error message if invalid, or null if valid.
  static String? validatePassword(String? value, {bool isRegistration = false}) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password.';
    }
    if (value.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters long.';
    }
    if (value.length > maxPasswordLength) {
      return 'Password must not exceed $maxPasswordLength characters.';
    }
    return null;
  }

  /// Validates a username / display name. Returns an error message if invalid, or null if valid.
  static String? validateUsername(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      if (required) return 'Please enter a username.';
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.length < minUsernameLength) {
      return 'Username must be at least $minUsernameLength characters.';
    }
    if (trimmed.length > maxUsernameLength) {
      return 'Username must not exceed $maxUsernameLength characters.';
    }
    if (!_usernameRegExp.hasMatch(trimmed)) {
      return 'Username can only contain letters, numbers, spaces, underscores, and hyphens.';
    }
    return null;
  }
}

/// Client-side rate limiter and anti-hammering guard.
///
/// Prevents automated bots and rapid-fire spam clicks from hammering the
/// auth endpoints and exhausting network or cloud rate limits.
class AuthRateLimiter {
  static const int maxConsecutiveFailures = 5;
  static const int baseCooldownSeconds = 30;

  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  int get failedAttempts => _failedAttempts;

  /// Checks whether an attempt is currently permitted.
  ///
  /// Returns `(true, 0)` if allowed, or `(false, secondsRemaining)` if locked out.
  (bool allowed, int secondsRemaining) canAttempt() {
    final now = DateTime.now();
    if (_lockoutUntil != null) {
      if (now.isBefore(_lockoutUntil!)) {
        final remaining = _lockoutUntil!.difference(now).inSeconds + 1;
        return (false, remaining);
      }
      // Lockout expired
      _lockoutUntil = null;
    }
    return (true, 0);
  }

  /// Records a failed authentication attempt. Enforces lockout if threshold exceeded.
  void recordFailure() {
    _failedAttempts++;
    if (_failedAttempts >= maxConsecutiveFailures) {
      // Exponential backoff factor for repeated lockout triggers: 30s, 60s, 120s...
      final multiplier = pow(2, min(_failedAttempts - maxConsecutiveFailures, 3)).toInt();
      final cooldown = baseCooldownSeconds * multiplier;
      _lockoutUntil = DateTime.now().add(Duration(seconds: cooldown));
    }
  }

  /// Resets failure counters upon successful authentication.
  void recordSuccess() {
    _failedAttempts = 0;
    _lockoutUntil = null;
  }
}
