import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/data/fasting_notification_scheduler.dart';
import 'package:herculex/features/fasting/data/fasting_repository.dart';
import 'package:herculex/features/fasting/presentation/fasting_food_log_dialog.dart';
import 'package:herculex/features/fasting/presentation/fasting_providers.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  DateTime time;
  _FixedClock(this.time);
  @override
  DateTime now() => time;
}

class _MockNotificationScheduler implements FastingNotificationScheduler {
  bool cancelled = false;

  @override
  Future<void> cancelFastingGoal() async {
    cancelled = true;
  }

  @override
  Future<void> scheduleFastingGoal(
    DateTime targetTime, {
    String planName = 'Fasting',
    bool enabled = true,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FixedClock clock;
  late FastingRepository repo;
  late _MockNotificationScheduler mockScheduler;

  setUp(() async {
    db = await openTestDatabase();
    clock = _FixedClock(DateTime(2026, 8, 14, 12, 0, 0));
    repo = FastingRepository(db, clock);
    mockScheduler = _MockNotificationScheduler();
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestApp({required void Function(bool? result) onResult}) {
    return ProviderScope(
      overrides: [
        fastingRepositoryProvider.overrideWithValue(repo),
        fastingNotificationSchedulerProvider.overrideWithValue(mockScheduler),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, child) {
              return ElevatedButton(
                onPressed: () async {
                  final res = await confirmEndFastOnFoodLog(context, ref);
                  onResult(res);
                },
                child: const Text('TRIGGER'),
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets(
    'confirmEndFastOnFoodLog returns true immediately when no active fast',
    (tester) async {
      bool? dialogResult;
      await tester.pumpWidget(
        buildTestApp(onResult: (res) => dialogResult = res),
      );
      await tester.tap(find.text('TRIGGER'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
      expect(find.text('Active Fast'), findsNothing);
    },
  );

  testWidgets(
    'confirmEndFastOnFoodLog shows prompt when active fast is running',
    (tester) async {
      await repo.startSession(16 * 3600);

      await tester.pumpWidget(buildTestApp(onResult: (_) {}));
      await tester.tap(find.text('TRIGGER'));
      await tester.pumpAndSettle();

      expect(find.text('Active Fast'), findsOneWidget);
      expect(find.text('End Fast & Save'), findsOneWidget);
      expect(find.text('Keep Fasting'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping End Fast & Save ends active fast session and returns true',
    (tester) async {
      await repo.startSession(16 * 3600);

      bool? dialogResult;
      await tester.pumpWidget(
        buildTestApp(onResult: (res) => dialogResult = res),
      );
      await tester.tap(find.text('TRIGGER'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('End Fast & Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
      expect(mockScheduler.cancelled, isTrue);

      final active = await repo.activeSession();
      expect(active, isNull);

      final history = await repo.history();
      expect(history, hasLength(1));
      expect(history.first.completed, isTrue);
    },
  );

  testWidgets(
    'Tapping Keep Fasting keeps active fast running and returns true',
    (tester) async {
      final id = await repo.startSession(16 * 3600);

      bool? dialogResult;
      await tester.pumpWidget(
        buildTestApp(onResult: (res) => dialogResult = res),
      );
      await tester.tap(find.text('TRIGGER'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep Fasting'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);

      final active = await repo.activeSession();
      expect(active, isNotNull);
      expect(active!.id, id);
    },
  );

  testWidgets('Tapping Cancel keeps active fast running and returns false', (
    tester,
  ) async {
    final id = await repo.startSession(16 * 3600);

    bool? dialogResult;
    await tester.pumpWidget(
      buildTestApp(onResult: (res) => dialogResult = res),
    );
    await tester.tap(find.text('TRIGGER'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(dialogResult, isFalse);

    final active = await repo.activeSession();
    expect(active, isNotNull);
    expect(active!.id, id);
  });
}
