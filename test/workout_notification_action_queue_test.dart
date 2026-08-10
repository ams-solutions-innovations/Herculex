import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/data/workout_notification_action_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PendingWorkoutNotificationActionQueue', () {
    test('enqueues actions in order', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await PendingWorkoutNotificationActionQueue.enqueue(
        prefs,
        'workout.reps.up',
        sessionId: 42,
        setId: 101,
      );
      await PendingWorkoutNotificationActionQueue.enqueue(
        prefs,
        'workout.weight.down',
        sessionId: 42,
      );

      final actions = PendingWorkoutNotificationActionQueue.read(prefs);
      expect(actions.map((action) => action.actionId), [
        'workout.reps.up',
        'workout.weight.down',
      ]);
      expect(actions.map((action) => action.sessionId), [42, 42]);
      expect(actions.first.setId, 101);
    });

    test('replace clears storage when no actions remain', () async {
      SharedPreferences.setMockInitialValues({
        PendingWorkoutNotificationActionQueue.prefsKey: const [
          'workout.reps.up',
        ],
      });
      final prefs = await SharedPreferences.getInstance();

      await PendingWorkoutNotificationActionQueue.replace(prefs, const []);

      expect(PendingWorkoutNotificationActionQueue.read(prefs), isEmpty);
      expect(
        prefs.containsKey(PendingWorkoutNotificationActionQueue.prefsKey),
        isFalse,
      );
    });

    test('replace preserves unapplied actions', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await PendingWorkoutNotificationActionQueue.replace(prefs, [
        const PendingWorkoutNotificationAction(
          actionId: 'workout.set.complete',
          sessionId: 99,
          setId: 1001,
        ),
      ]);

      final actions = PendingWorkoutNotificationActionQueue.read(prefs);
      expect(actions.single.actionId, 'workout.set.complete');
      expect(actions.single.sessionId, 99);
      expect(actions.single.setId, 1001);
    });

    test(
      'drainForSession accepts matching actions and drops stale ones',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await PendingWorkoutNotificationActionQueue.enqueue(
          prefs,
          'workout.reps.up',
          sessionId: 42,
          setId: 7,
        );
        await PendingWorkoutNotificationActionQueue.enqueue(
          prefs,
          'workout.weight.up',
          sessionId: 43,
        );

        final drain = PendingWorkoutNotificationActionQueue.drainForSession(
          prefs,
          42,
        );

        expect(drain.actions.single.actionId, 'workout.reps.up');
        expect(drain.actions.single.sessionId, 42);
        expect(drain.actions.single.setId, 7);
        expect(drain.remaining, isEmpty);
        expect(drain.dropped, 1);
      },
    );

    test(
      'drainForSession preserves actions when no active session exists',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await PendingWorkoutNotificationActionQueue.enqueue(
          prefs,
          'workout.reps.up',
          sessionId: 42,
        );

        final drain = PendingWorkoutNotificationActionQueue.drainForSession(
          prefs,
          null,
        );

        expect(drain.actions, isEmpty);
        expect(drain.remaining.single.actionId, 'workout.reps.up');
        expect(drain.remaining.single.sessionId, 42);
        expect(drain.dropped, 0);
      },
    );

    test('read migrates legacy string actions as sessionless', () async {
      SharedPreferences.setMockInitialValues({
        PendingWorkoutNotificationActionQueue.prefsKey: const [
          'workout.reps.up',
        ],
      });
      final prefs = await SharedPreferences.getInstance();

      final actions = PendingWorkoutNotificationActionQueue.read(prefs);

      expect(actions.single.actionId, 'workout.reps.up');
      expect(actions.single.sessionId, isNull);
      expect(actions.single.setId, isNull);
    });
  });
}
