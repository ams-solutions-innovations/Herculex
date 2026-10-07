import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/services/platform/active_workout_surface_sync_policy.dart';

/// Stand-in for `WorkoutSessionData` — the policy is generic over the session
/// type precisely so it can be reasoned about without the Drift row.
class _Session {
  const _Session();
}

void main() {
  group('shouldShowWorkoutBubble', () {
    const session = AsyncData<_Session?>(_Session());
    const noSession = AsyncData<_Session?>(null);
    const loading = AsyncLoading<_Session?>();

    bool show({
      AsyncValue<_Session?> activeSession = session,
      bool enabled = true,
      bool appBackgrounded = true,
      bool permissionGranted = true,
    }) => shouldShowWorkoutBubble(
      activeSession: activeSession,
      enabled: enabled,
      appBackgrounded: appBackgrounded,
      permissionGranted: permissionGranted,
    );

    test('shows when a workout is live, backgrounded, enabled and granted', () {
      expect(show(), isTrue);
    });

    test('hides while the app is in the foreground', () {
      expect(show(appBackgrounded: false), isFalse);
    });

    test('hides when the setting is off', () {
      expect(show(enabled: false), isFalse);
    });

    test('hides when the overlay permission is not granted', () {
      expect(show(permissionGranted: false), isFalse);
    });

    test('hides when there is no active workout', () {
      expect(show(activeSession: noSession), isFalse);
    });

    test('hides while the session is still loading', () {
      // A loading session is neither "there is a workout" nor "there is none".
      // Showing a bubble here would flash one on every cold start.
      expect(show(activeSession: loading), isFalse);
    });

    test('every condition is individually necessary', () {
      expect(show(enabled: false, appBackgrounded: false), isFalse);
      expect(show(activeSession: noSession, permissionGranted: false), isFalse);
    });

    test('stays up when the provider errors but retains a session', () {
      // An errored AsyncValue that carries a previous value is `hasValue`, but
      // its `asData` is null. Reading the session through `asData` here would
      // both disagree with this policy and null-crash the caller.
      final errored = const AsyncData<_Session?>(
        _Session(),
      ).copyWithPrevious(const AsyncData<_Session?>(_Session()));
      final withError = AsyncError<_Session?>(
        StateError('transient'),
        StackTrace.empty,
      ).copyWithPrevious(errored);

      expect(withError.hasValue, isTrue);
      expect(withError.asData, isNull);
      expect(show(activeSession: withError), isTrue);
    });

    test('hides when the provider errors with no session to fall back on', () {
      final withError = AsyncError<_Session?>(
        StateError('transient'),
        StackTrace.empty,
      ).copyWithPrevious(const AsyncData<_Session?>(null));

      expect(show(activeSession: withError), isFalse);
    });
  });

  group('shouldClearOngoingWorkoutSurface', () {
    test('clears only on a resolved null session', () {
      expect(
        shouldClearOngoingWorkoutSurface(const AsyncData<_Session?>(null)),
        isTrue,
      );
      expect(
        shouldClearOngoingWorkoutSurface(
          const AsyncData<_Session?>(_Session()),
        ),
        isFalse,
      );
      expect(
        shouldClearOngoingWorkoutSurface(const AsyncLoading<_Session?>()),
        isFalse,
      );
    });
  });
}
