import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/services/workout_notification_service.dart';

void main() {
  group('workout notification action payload', () {
    test('round-trips session and target set ids', () {
      final payload = workoutNotificationActionTargetPayload(
        sessionId: 42,
        setId: 1001,
      );

      final target = workoutNotificationActionTargetFromPayload(payload);

      expect(target.sessionId, 42);
      expect(target.setId, 1001);
    });

    test('keeps set id optional for generic active-session actions', () {
      final payload = workoutNotificationActionTargetPayload(sessionId: 42);

      final target = workoutNotificationActionTargetFromPayload(payload);

      expect(target.sessionId, 42);
      expect(target.setId, isNull);
    });

    test('ignores empty or malformed payloads', () {
      expect(
        workoutNotificationActionTargetFromPayload(null).sessionId,
        isNull,
      );
      expect(workoutNotificationActionTargetFromPayload('').setId, isNull);

      final target = workoutNotificationActionTargetFromPayload('{bad json');

      expect(target.sessionId, isNull);
      expect(target.setId, isNull);
    });
  });
}
