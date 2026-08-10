import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/services/active_workout_surface_sync_policy.dart';

void main() {
  test('does not clear while active session is still loading', () {
    expect(
      shouldClearOngoingWorkoutSurface<int>(const AsyncValue.loading()),
      isFalse,
    );
  });

  test('does not clear while active session lookup has an error', () {
    expect(
      shouldClearOngoingWorkoutSurface<int>(
        AsyncValue.error(Exception('db warming up'), StackTrace.empty),
      ),
      isFalse,
    );
  });

  test('clears only after active session resolves to none', () {
    expect(
      shouldClearOngoingWorkoutSurface<int>(const AsyncValue.data(null)),
      isTrue,
    );
  });

  test('does not clear while a session is active', () {
    expect(
      shouldClearOngoingWorkoutSurface<int>(const AsyncValue.data(42)),
      isFalse,
    );
  });
}
