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

  group('FastingRepository tests', () {
    late AppDatabase db;
    late _FixedClock clock;
    late FastingRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      clock = _FixedClock(DateTime(2026, 8, 14, 12, 0, 0));
      repo = FastingRepository(db, clock);
    });

    tearDown(() async {
      await db.close();
    });

    test('startSession creates an active session with targetSeconds and clock.now()', () async {
      final id = await repo.startSession(16 * 3600);
      expect(id, isPositive);

      final active = await repo.activeSession();
      expect(active, isNotNull);
      expect(active!.id, id);
      expect(active.targetSeconds, 16 * 3600);
      expect(active.startedAt, clock.now());
      expect(active.endedAt, isNull);
      expect(active.completed, isFalse);
    });

    test('startSession with customStartTime uses customStartTime', () async {
      final customTime = DateTime(2026, 8, 14, 8, 30, 0);
      final id = await repo.startSession(18 * 3600, customStartTime: customTime);

      final active = await repo.activeSession();
      expect(active, isNotNull);
      expect(active!.id, id);
      expect(active.startedAt, customTime);
      expect(active.targetSeconds, 18 * 3600);
    });

    test('starting a new session automatically closes any previously open active session', () async {
      final firstId = await repo.startSession(16 * 3600);
      clock.time = clock.time.add(const Duration(hours: 2));

      final secondId = await repo.startSession(14 * 3600);
      expect(secondId, isNot(equals(firstId)));

      final active = await repo.activeSession();
      expect(active!.id, secondId);

      // Verify first session was ended with completed = false
      final firstSession = await (db.select(db.fastingSessions)..where((t) => t.id.equals(firstId))).getSingle();
      expect(firstSession.endedAt, clock.now());
      expect(firstSession.completed, isFalse);
    });

    test('endSession closes active session with endedAt and completed status', () async {
      await repo.startSession(16 * 3600);
      clock.time = clock.time.add(const Duration(hours: 16));

      await repo.endSession(completed: true);

      final active = await repo.activeSession();
      expect(active, isNull);

      final history = await repo.watchHistory().first;
      expect(history, hasLength(1));
      expect(history.first.completed, isTrue);
      expect(history.first.endedAt, clock.now());
    });

    test('updateSessionStartTime and updateSessionTarget modify session fields', () async {
      final id = await repo.startSession(16 * 3600);
      final newStart = DateTime(2026, 8, 14, 6, 0, 0);

      await repo.updateSessionStartTime(id, newStart);
      await repo.updateSessionTarget(id, 20 * 3600);

      final active = await repo.activeSession();
      expect(active!.startedAt, newStart);
      expect(active.targetSeconds, 20 * 3600);
    });

    test('updateSessionCompletion updates completion status and optional endedAt', () async {
      final id = await repo.startSession(16 * 3600);
      await repo.endSession(completed: false);

      await repo.updateSessionCompletion(id, true);

      final history = await repo.watchHistory().first;
      expect(history.first.completed, isTrue);
    });

    test('deleteSession removes the session from database', () async {
      final id = await repo.startSession(16 * 3600);
      await repo.endSession(completed: true);

      var history = await repo.watchHistory().first;
      expect(history, hasLength(1));

      await repo.deleteSession(id);
      history = await repo.watchHistory().first;
      expect(history, isEmpty);
    });

    test('currentStreak calculates consecutive completed days accurately', () async {
      // Day 1: 2026-08-12
      clock.time = DateTime(2026, 8, 12, 10, 0, 0);
      await repo.startSession(16 * 3600);
      clock.time = DateTime(2026, 8, 12, 20, 0, 0);
      await repo.endSession(completed: true);

      // Day 2: 2026-08-13
      clock.time = DateTime(2026, 8, 13, 10, 0, 0);
      await repo.startSession(16 * 3600);
      clock.time = DateTime(2026, 8, 13, 20, 0, 0);
      await repo.endSession(completed: true);

      // Day 3: 2026-08-14 (Today)
      clock.time = DateTime(2026, 8, 14, 10, 0, 0);
      await repo.startSession(16 * 3600);
      clock.time = DateTime(2026, 8, 14, 20, 0, 0);
      await repo.endSession(completed: true);

      final streak = await repo.currentStreak();
      expect(streak, 3);
    });

    test('currentStreak returns 0 if last completed fast was more than 1 day ago', () async {
      // Fast ended 3 days ago
      clock.time = DateTime(2026, 8, 10, 10, 0, 0);
      await repo.startSession(16 * 3600);
      clock.time = DateTime(2026, 8, 10, 20, 0, 0);
      await repo.endSession(completed: true);

      // Today is 2026-08-14
      clock.time = DateTime(2026, 8, 14, 12, 0, 0);

      final streak = await repo.currentStreak();
      expect(streak, 0);
    });

    test('averageEatingWindow calculates average hours outside fasts', () async {
      // Fast 1: ended at 12:00
      clock.time = DateTime(2026, 8, 13, 0, 0, 0);
      await repo.startSession(12 * 3600);
      clock.time = DateTime(2026, 8, 13, 12, 0, 0);
      await repo.endSession(completed: true);

      // Fast 2: started at 20:00 (eating window was 8 hours between 12:00 and 20:00)
      clock.time = DateTime(2026, 8, 13, 20, 0, 0);
      await repo.startSession(12 * 3600);
      clock.time = DateTime(2026, 8, 14, 8, 0, 0);
      await repo.endSession(completed: true);

      clock.time = DateTime(2026, 8, 14, 12, 0, 0);
      final avg = await repo.averageEatingWindow(7);
      expect(avg, closeTo(8.0, 0.1));
    });
  });
}
