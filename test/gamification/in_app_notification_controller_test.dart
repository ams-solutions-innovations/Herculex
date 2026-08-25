import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/notifications/in_app_notification_controller.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/core/notifications/in_app_notification_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InAppNotificationNotifier', () {
    late InAppNotificationNotifier notifier;

    setUp(() {
      notifier = InAppNotificationNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('shows immediate notification when queue is empty', () {
      final item = InAppNotificationItem.weightPr(
        exerciseName: 'Bench Press',
        weightFormatted: '140 kg',
      );

      notifier.show(item);

      expect(notifier.state.current, isNotNull);
      expect(notifier.state.current?.id, item.id);
      expect(notifier.state.queue.isEmpty, isTrue);
    });

    test('queues subsequent notifications if one is currently visible', () {
      final item1 = InAppNotificationItem.weightPr(
        exerciseName: 'Bench Press',
        weightFormatted: '140 kg',
      );
      final item2 = InAppNotificationItem.muscleGroupVolumePr(
        muscleGroup: 'Chest',
        volumeFormatted: '5,000 kg',
      );

      notifier.show(item1);
      notifier.show(item2);

      expect(notifier.state.current?.id, item1.id);
      expect(notifier.state.queue.length, 1);
      expect(notifier.state.queue.first.id, item2.id);
    });

    test('InAppNotificationNotifier dismiss removes current item and sets isDismissing', () {
      final notifier = InAppNotificationNotifier();
      final item = InAppNotificationItem.weightPr(
        exerciseName: 'Bench Press',
        weightFormatted: '140 kg',
      );

      notifier.show(item);
      expect(notifier.state.current?.id, item.id);
      expect(notifier.state.isDismissing, isFalse);

      notifier.dismiss();
      expect(notifier.state.isDismissing, isTrue);
    });
  });

  testWidgets('InAppNotificationHost renders pill HUD without overflow for long content', (tester) async {
    final notifier = InAppNotificationNotifier();
    final item = InAppNotificationItem.exerciseTonnagePr(
      exerciseName: 'Extra Long Incline Dumbbell Bench Press with Chains and Bands',
      volumeFormatted: '18,450 kg',
      diffFormatted: '2,400 kg',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inAppNotificationControllerProvider.overrideWith((ref) => notifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: InAppNotificationHost(
              child: Center(child: Text('Content')),
            ),
          ),
        ),
      ),
    );

    notifier.show(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.textContaining('new volume PR'), findsOneWidget);
    expect(find.textContaining('18,450 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
