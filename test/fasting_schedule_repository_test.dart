import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/data/fasting_repository.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  DateTime time;
  _FixedClock(this.time);
  @override
  DateTime now() => time;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FastingRepository schedule CRUD', () {
    late AppDatabase db;
    late FastingRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = FastingRepository(db, _FixedClock(DateTime(2026, 8, 14, 12)));
    });

    tearDown(() async {
      await db.close();
    });

    test('createSchedule persists all fields and defaults enabled to true', () async {
      final id = await repo.createSchedule(
        planName: 'h16',
        daysOfWeek: 0x1F,
        startTimeMinutes: 20 * 60,
        autoStart: true,
      );

      final saved = await repo.schedule(id);
      expect(saved, isNotNull);
      expect(saved!.planName, 'h16');
      expect(saved.customTargetSeconds, isNull);
      expect(saved.daysOfWeek, 0x1F);
      expect(saved.startTimeMinutes, 20 * 60);
      expect(saved.enabled, isTrue);
      expect(saved.autoStart, isTrue);
    });

    test('createSchedule stores customTargetSeconds for a custom plan', () async {
      final id = await repo.createSchedule(
        planName: 'custom',
        customTargetSeconds: 20 * 3600,
        daysOfWeek: 0x7F,
        startTimeMinutes: 6 * 60,
      );

      final saved = await repo.schedule(id);
      expect(saved!.customTargetSeconds, 20 * 3600);
    });

    test('watchSchedules orders by startTimeMinutes', () async {
      await repo.createSchedule(
        planName: 'h18',
        daysOfWeek: 0x7F,
        startTimeMinutes: 22 * 60,
      );
      await repo.createSchedule(
        planName: 'h16',
        daysOfWeek: 0x7F,
        startTimeMinutes: 6 * 60,
      );

      final schedules = await repo.watchSchedules().first;
      expect(schedules, hasLength(2));
      expect(schedules.first.startTimeMinutes, 6 * 60);
      expect(schedules.last.startTimeMinutes, 22 * 60);
    });

    test('updateSchedule overwrites every field', () async {
      final id = await repo.createSchedule(
        planName: 'h16',
        daysOfWeek: 0x1F,
        startTimeMinutes: 20 * 60,
      );

      await repo.updateSchedule(
        id,
        planName: 'd1',
        customTargetSeconds: null,
        daysOfWeek: 0x60,
        startTimeMinutes: 8 * 60,
        enabled: false,
        autoStart: true,
      );

      final saved = await repo.schedule(id);
      expect(saved!.planName, 'd1');
      expect(saved.daysOfWeek, 0x60);
      expect(saved.startTimeMinutes, 8 * 60);
      expect(saved.enabled, isFalse);
      expect(saved.autoStart, isTrue);
    });

    test('setScheduleEnabled toggles only the enabled flag', () async {
      final id = await repo.createSchedule(
        planName: 'h16',
        daysOfWeek: 0x1F,
        startTimeMinutes: 20 * 60,
      );

      await repo.setScheduleEnabled(id, false);
      var saved = await repo.schedule(id);
      expect(saved!.enabled, isFalse);
      expect(saved.daysOfWeek, 0x1F); // untouched

      await repo.setScheduleEnabled(id, true);
      saved = await repo.schedule(id);
      expect(saved!.enabled, isTrue);
    });

    test('deleteSchedule removes the row', () async {
      final id = await repo.createSchedule(
        planName: 'h16',
        daysOfWeek: 0x1F,
        startTimeMinutes: 20 * 60,
      );

      await repo.deleteSchedule(id);
      expect(await repo.schedule(id), isNull);
    });

    test('schedule returns null for an id that does not exist', () async {
      expect(await repo.schedule(999), isNull);
    });
  });
}
