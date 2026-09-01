import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/data/fasting_notification_scheduler.dart';
import 'package:herculex/features/fasting/data/fasting_repository.dart';
import 'package:herculex/features/fasting/presentation/end_fast_dialog.dart';
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

  Widget buildTestApp() {
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
                onPressed: () => confirmEndFast(context, ref),
                child: const Text('TRIGGER'),
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets(
    'confirmEndFast dialog shows Save, Continue, and Discard options',
    (tester) async {
      await repo.startSession(16 * 3600);

      await tester.pumpWidget(buildTestApp());
      await tester.tap(find.text('TRIGGER'));
      await tester.pumpAndSettle();

      expect(find.text('End Fast'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    },
  );

  testWidgets('Tapping Save ends fast session and cancels notifications', (
    tester,
  ) async {
    await repo.startSession(16 * 3600);

    await tester.pumpWidget(buildTestApp());
    await tester.tap(find.text('TRIGGER'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(mockScheduler.cancelled, isTrue);

    final active = await repo.activeSession();
    expect(active, isNull);

    final history = await repo.history();
    expect(history, hasLength(1));
    expect(history.first.completed, isTrue);
  });

  testWidgets('Tapping Continue leaves fast running and dismisses dialog', (
    tester,
  ) async {
    final id = await repo.startSession(16 * 3600);

    await tester.pumpWidget(buildTestApp());
    await tester.tap(find.text('TRIGGER'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('End Fast'), findsNothing);

    final active = await repo.activeSession();
    expect(active, isNotNull);
    expect(active!.id, id);
  });

  testWidgets(
    'Tapping Discard deletes fast session and cancels notifications',
    (tester) async {
      await repo.startSession(16 * 3600);

      await tester.pumpWidget(buildTestApp());
      await tester.tap(find.text('TRIGGER'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(mockScheduler.cancelled, isTrue);

      final active = await repo.activeSession();
      expect(active, isNull);

      final history = await repo.history();
      expect(history, isEmpty);
    },
  );
}
