import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/auth_validator.dart';

void main() {
  group('AuthValidator Email Validation', () {
    test('rejects empty or whitespace-only email', () {
      expect(AuthValidator.validateEmail(null), isNotNull);
      expect(AuthValidator.validateEmail(''), isNotNull);
      expect(AuthValidator.validateEmail('   '), isNotNull);
    });

    test('rejects emails exceeding max RFC 5321 length', () {
      final longEmail = '${'a' * 245}@example.com';
      expect(longEmail.length, greaterThan(AuthValidator.maxEmailLength));
      expect(AuthValidator.validateEmail(longEmail), contains('exceed'));
    });

    test('rejects invalid email formats without @ or domain', () {
      expect(AuthValidator.validateEmail('plainaddress'), isNotNull);
      expect(AuthValidator.validateEmail('@missingusername.com'), isNotNull);
      expect(AuthValidator.validateEmail('user@.com'), isNotNull);
      expect(AuthValidator.validateEmail('user@domain'), isNotNull);
      expect(AuthValidator.validateEmail('user@domain.'), isNotNull);
    });

    test('accepts valid email addresses', () {
      expect(AuthValidator.validateEmail('user@example.com'), isNull);
      expect(AuthValidator.validateEmail('john.doe+test@gmail.com'), isNull);
      expect(AuthValidator.validateEmail('  athlete@herculex.app  '), isNull);
    });
  });

  group('AuthValidator Password Validation', () {
    test('rejects empty password', () {
      expect(AuthValidator.validatePassword(null), isNotNull);
      expect(AuthValidator.validatePassword(''), isNotNull);
    });

    test('rejects short passwords (< 8 characters)', () {
      expect(AuthValidator.validatePassword('1234567'), contains('at least 8'));
      expect(AuthValidator.validatePassword('abc'), contains('at least 8'));
    });

    test('rejects oversized passwords (> 72 characters) to prevent CPU DoS', () {
      final longPass = 'A' * (AuthValidator.maxPasswordLength + 1);
      expect(AuthValidator.validatePassword(longPass), contains('exceed'));
    });

    test('accepts valid passwords', () {
      expect(AuthValidator.validatePassword('StrongPass123!'), isNull);
      expect(AuthValidator.validatePassword('8charsok'), isNull);
    });
  });

  group('AuthValidator Username Validation', () {
    test('allows null or empty when not required', () {
      expect(AuthValidator.validateUsername(null, required: false), isNull);
      expect(AuthValidator.validateUsername('', required: false), isNull);
      expect(AuthValidator.validateUsername('   ', required: false), isNull);
    });

    test('rejects empty when required', () {
      expect(AuthValidator.validateUsername('', required: true), isNotNull);
      expect(AuthValidator.validateUsername(null, required: true), isNotNull);
    });

    test('rejects short username (< 2 characters)', () {
      expect(AuthValidator.validateUsername('a'), contains('at least 2'));
    });

    test('rejects oversized username (> 30 characters)', () {
      final longName = 'A' * (AuthValidator.maxUsernameLength + 1);
      expect(AuthValidator.validateUsername(longName), contains('exceed'));
    });

    test('rejects disallowed special characters (scripts, html, quotes)', () {
      expect(AuthValidator.validateUsername('<script>'), isNotNull);
      expect(AuthValidator.validateUsername('user@name'), isNotNull);
      expect(AuthValidator.validateUsername('name; DROP TABLE'), isNotNull);
    });

    test('accepts clean usernames', () {
      expect(AuthValidator.validateUsername('John Doe'), isNull);
      expect(AuthValidator.validateUsername('Alex_99'), isNull);
      expect(AuthValidator.validateUsername('Fit-Coach'), isNull);
    });
  });

  group('AuthRateLimiter (Anti-Bot / Anti-Spam)', () {
    late AuthRateLimiter rateLimiter;

    setUp(() {
      rateLimiter = AuthRateLimiter();
    });

    test('initially allows attempts', () {
      final (allowed, remaining) = rateLimiter.canAttempt();
      expect(allowed, isTrue);
      expect(remaining, equals(0));
    });

    test('locks out after 5 consecutive failures', () {
      for (int i = 0; i < 4; i++) {
        rateLimiter.recordFailure();
        expect(rateLimiter.canAttempt().$1, isTrue);
      }

      // 5th failure triggers lockout
      rateLimiter.recordFailure();
      final (allowed, remaining) = rateLimiter.canAttempt();
      expect(allowed, isFalse);
      expect(remaining, greaterThan(0));
      expect(remaining, lessThanOrEqualTo(AuthRateLimiter.baseCooldownSeconds));
    });

    test('resets lockout on success', () {
      for (int i = 0; i < 5; i++) {
        rateLimiter.recordFailure();
      }
      expect(rateLimiter.canAttempt().$1, isFalse);

      rateLimiter.recordSuccess();
      final (allowed, remaining) = rateLimiter.canAttempt();
      expect(allowed, isTrue);
      expect(remaining, equals(0));
      expect(rateLimiter.failedAttempts, equals(0));
    });
  });
}
