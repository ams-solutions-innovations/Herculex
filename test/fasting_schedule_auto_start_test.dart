import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/data/fasting_notification_scheduler.dart';
import 'package:herculex/features/fasting/data/fasting_repository.dart';
import 'package:herculex/features/fasting/data/fasting_schedule_service.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/domain/fasting_schedule_occurrence.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  DateTime time;
  _FixedClock(this.time);
  @override
  DateTime now() => time;
}

class _MockNotificationScheduler implements FastingNotificationScheduler {
  bool scheduled = false;
  DateTime? scheduledTargetTime;
  String? scheduledPlanName;
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
  }) async {
    scheduled = true;
    scheduledTargetTime = targetTime;
    scheduledPlanName = planName;
  }
}

class _FakeNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FixedClock clock;
  late FastingRepository repo;
  late _MockNotificationScheduler mockScheduler;
  late FastingScheduleService scheduleService;

  setUp(() async {
    db = await openTestDatabase();
    clock = _FixedClock(DateTime(2026, 8, 14, 20, 30, 0)); // Friday 20:30
    repo = FastingRepository(db, clock);
    mockScheduler = _MockNotificationScheduler();
    scheduleService = FastingScheduleService(_FakeNotificationsPlugin());
  });

  tearDown(() async {
    await db.close();
  });

  group('FastingScheduleService checkAndAutoStartSchedules', () {
    test('auto-starts fast when current time is in scheduled window', () async {
      // Schedule: Friday 20:00, 16:8 (16h target), autoStart: true
      await repo.createSchedule(
        planName: FastingPlan.h16.name,
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 20 * 60,
        enabled: true,
        autoStart: true,
      );

      final now = DateTime(2026, 8, 14, 20, 30, 0); // Friday 20:30
      await scheduleService.checkAndAutoStartSchedules(
        repository: repo,
        notificationScheduler: mockScheduler,
        goalNotificationEnabled: true,
        now: now,
      );

      final active = await repo.activeSession();
      expect(active, isNotNull);
      expect(active!.startedAt, DateTime(2026, 8, 14, 20, 0, 0));
      expect(active.targetSeconds, 16 * 3600);
      expect(mockScheduler.scheduled, isTrue);
      expect(
        mockScheduler.scheduledTargetTime,
        DateTime(2026, 8, 14, 20, 0, 0).add(const Duration(hours: 16)),
      );
    });

    test('does not auto-start if an active fast is already ongoing', () async {
      await repo.createSchedule(
        planName: FastingPlan.h16.name,
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 20 * 60,
        enabled: true,
        autoStart: true,
      );

      // Start an existing fast earlier at 18:00
      final existingId = await repo.startSession(
        14 * 3600,
        customStartTime: DateTime(2026, 8, 14, 18, 0),
      );

      final now = DateTime(2026, 8, 14, 20, 30, 0);
      await scheduleService.checkAndAutoStartSchedules(
        repository: repo,
        notificationScheduler: mockScheduler,
        goalNotificationEnabled: true,
        now: now,
      );

      final active = await repo.activeSession();
      expect(active, isNotNull);
      expect(active!.id, existingId);
      expect(active.startedAt, DateTime(2026, 8, 14, 18, 0));
    });

    test(
      'does not auto-start if a session was already completed for this window',
      () async {
        await repo.createSchedule(
          planName: FastingPlan.h16.name,
          daysOfWeek: weekdayBit(DateTime.friday),
          startTimeMinutes: 20 * 60,
          enabled: true,
          autoStart: true,
        );

        // Start and end a fast for today's 20:00 schedule
        await repo.startSession(
          16 * 3600,
          customStartTime: DateTime(2026, 8, 14, 20, 0),
        );
        clock.time = DateTime(2026, 8, 14, 20, 20);
        await repo.endSession(completed: true);

        final now = DateTime(2026, 8, 14, 20, 30, 0);
        await scheduleService.checkAndAutoStartSchedules(
          repository: repo,
          notificationScheduler: mockScheduler,
          goalNotificationEnabled: true,
          now: now,
        );

        final active = await repo.activeSession();
        expect(active, isNull);
      },
    );

    test('does not auto-start if autoStart is false', () async {
      await repo.createSchedule(
        planName: FastingPlan.h16.name,
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 20 * 60,
        enabled: true,
        autoStart: false,
      );

      final now = DateTime(2026, 8, 14, 20, 30, 0);
      await scheduleService.checkAndAutoStartSchedules(
        repository: repo,
        notificationScheduler: mockScheduler,
        goalNotificationEnabled: true,
        now: now,
      );

      final active = await repo.activeSession();
      expect(active, isNull);
    });

    test('does not auto-start if schedule is disabled', () async {
      await repo.createSchedule(
        planName: FastingPlan.h16.name,
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 20 * 60,
        enabled: false,
        autoStart: true,
      );

      final now = DateTime(2026, 8, 14, 20, 30, 0);
      await scheduleService.checkAndAutoStartSchedules(
        repository: repo,
        notificationScheduler: mockScheduler,
        goalNotificationEnabled: true,
        now: now,
      );

      final active = await repo.activeSession();
      expect(active, isNull);
    });
  });
}
