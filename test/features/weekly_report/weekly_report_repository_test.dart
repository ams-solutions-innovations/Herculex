import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const week = IsoWeek(2026, 40);
  const otherWeek = IsoWeek(2026, 39);

  late AppDatabase db;
  late FakeClock clock;
  late WeeklyReportRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 4, 18));
    repo = WeeklyReportRepository(db, clock);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertRaw({
    required IsoWeek w,
    required String payload,
    required DateTime generatedAt,
    DateTime? deletedAt,
  }) {
    return db
        .into(db.weeklyReports)
        .insert(
          WeeklyReportsCompanion.insert(
            isoYear: w.isoYear,
            isoWeek: w.isoWeek,
            weekStartIso: w.startIso,
            payloadJson: payload,
            generatedAt: Value(generatedAt),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  group('insertSnapshot', () {
    test(
      'stores the payload with clock time and empty write-once fields',
      () async {
        final r = await repo.insertSnapshot(
          week: week,
          payloadVersion: 1,
          payloadJson: '{"a":1}',
        );
        expect(r.week, week);
        expect(r.weekStartIso, week.startIso);
        expect(r.payloadVersion, 1);
        expect(r.payloadJson, '{"a":1}');
        expect(r.narrativeAttempts, 0);
        expect(r.narrativeJson, isNull);
        expect(r.tdeeDecision, isNull);
        expect(r.tdeeDecisionKcal, isNull);
        expect(r.viewedAt, isNull);
        // Drift stores DateTime at second resolution.
        expect(r.generatedAt, DateTime(2026, 10, 4, 18));
      },
    );

    test(
      'second call for the same week returns the original, one row',
      () async {
        await repo.insertSnapshot(
          week: week,
          payloadVersion: 1,
          payloadJson: '{"a":1}',
        );
        clock.advance(const Duration(hours: 3));
        final second = await repo.insertSnapshot(
          week: week,
          payloadVersion: 1,
          payloadJson: '{"a":2}',
        );
        expect(second.payloadJson, '{"a":1}');
        expect(await db.select(db.weeklyReports).get(), hasLength(1));
      },
    );

    test('a different week is a separate row', () async {
      await repo.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{"a":1}',
      );
      await repo.insertSnapshot(
        week: otherWeek,
        payloadVersion: 1,
        payloadJson: '{"b":1}',
      );
      expect(await db.select(db.weeklyReports).get(), hasLength(2));
    });

    test('a tombstoned-only week is replaced by a fresh row', () async {
      await insertRaw(
        w: week,
        payload: '{"old":true}',
        generatedAt: DateTime(2026, 10, 1),
        deletedAt: DateTime(2026, 10, 2),
      );
      final r = await repo.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{"fresh":true}',
      );
      expect(r.payloadJson, '{"fresh":true}');
      final rows = await db.select(db.weeklyReports).get();
      expect(rows, hasLength(1));
      expect(rows.single.deletedAt, isNull);
    });

    test('a live row is never rewritten even beside a tombstone', () async {
      await insertRaw(
        w: week,
        payload: '{"gone":true}',
        generatedAt: DateTime(2026, 10, 1),
        deletedAt: DateTime(2026, 10, 2),
      );
      await insertRaw(
        w: week,
        payload: '{"live":true}',
        generatedAt: DateTime(2026, 10, 3),
      );
      final r = await repo.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{"new":true}',
      );
      expect(r.payloadJson, '{"live":true}');
    });
  });

  group('reads', () {
    test('forWeek is null for an unknown week', () async {
      expect(await repo.forWeek(week), isNull);
    });

    test('soft-deleted rows are invisible to every read', () async {
      await insertRaw(
        w: week,
        payload: '{}',
        generatedAt: DateTime(2026, 10, 1),
        deletedAt: DateTime(2026, 10, 2),
      );
      expect(await repo.forWeek(week), isNull);
      expect(await repo.watchWeek(week).first, isNull);
      expect(await repo.watchHistory().first, isEmpty);
    });

    test('duplicates resolve to the earliest by generatedAt then id', () async {
      await insertRaw(
        w: week,
        payload: '{"late":true}',
        generatedAt: DateTime(2026, 10, 5),
      );
      await insertRaw(
        w: week,
        payload: '{"early":true}',
        generatedAt: DateTime(2026, 10, 4),
      );
      expect((await repo.forWeek(week))!.payloadJson, '{"early":true}');
      expect((await repo.watchWeek(week).first)!.payloadJson, '{"early":true}');
      final history = await repo.watchHistory().first;
      expect(history, hasLength(1));
      expect(history.single.payloadJson, '{"early":true}');
    });

    test('equal generatedAt falls back to the lowest id', () async {
      final t = DateTime(2026, 10, 4);
      await insertRaw(w: week, payload: '{"first":true}', generatedAt: t);
      await insertRaw(w: week, payload: '{"second":true}', generatedAt: t);
      expect((await repo.forWeek(week))!.payloadJson, '{"first":true}');
    });

    test('watchHistory is newest week first', () async {
      for (final w in const [
        IsoWeek(2026, 38),
        IsoWeek(2027, 2),
        IsoWeek(2026, 40),
        IsoWeek(2026, 52),
      ]) {
        await repo.insertSnapshot(
          week: w,
          payloadVersion: 1,
          payloadJson: '{"w":"$w"}',
        );
      }
      final history = await repo.watchHistory().first;
      expect(history.map((r) => r.week).toList(), const [
        IsoWeek(2027, 2),
        IsoWeek(2026, 52),
        IsoWeek(2026, 40),
        IsoWeek(2026, 38),
      ]);
    });

    test('a malformed payload string does not make reads throw', () async {
      await insertRaw(
        w: week,
        payload: '{not json',
        generatedAt: DateTime(2026, 10, 4),
      );
      final r = await repo.forWeek(week);
      expect(r!.payloadJson, '{not json');
      expect(await repo.watchHistory().first, hasLength(1));
    });
  });

  group('saveNarrative', () {
    test('writes once, then returns false and changes nothing', () async {
      await repo.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{"a":1}',
      );
      final first = await repo.saveNarrative(
        week,
        narrativeJson: '{"summary":"one"}',
        knowledgeVersion: 'kb-1',
        modelVersion: 'm-1',
      );
      expect(first, isTrue);
      final second = await repo.saveNarrative(
        week,
        narrativeJson: '{"summary":"two"}',
        knowledgeVersion: 'kb-2',
        modelVersion: 'm-2',
      );
      expect(second, isFalse);
      final r = (await repo.forWeek(week))!;
      expect(r.narrativeJson, '{"summary":"one"}');
      expect(r.knowledgeVersion, 'kb-1');
      expect(r.modelVersion, 'm-1');
      expect(r.payloadJson, '{"a":1}');
    });

    test('returns false for a week with no row', () async {
      expect(await repo.saveNarrative(week, narrativeJson: '{}'), isFalse);
    });
  });

  group('recordTdeeDecision', () {
    setUp(() async {
      await repo.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{"a":1}',
      );
    });

    test('is write-once and keeps the first outcome', () async {
      expect(
        await repo.recordTdeeDecision(week, decision: 'updated', kcal: 2600),
        isTrue,
      );
      expect(await repo.recordTdeeDecision(week, decision: 'kept'), isFalse);
      final r = (await repo.forWeek(week))!;
      expect(r.tdeeDecision, 'updated');
      expect(r.tdeeDecisionKcal, 2600);
    });

    test('kept without kcal stores a null kcal', () async {
      expect(await repo.recordTdeeDecision(week, decision: 'kept'), isTrue);
      final r = (await repo.forWeek(week))!;
      expect(r.tdeeDecision, 'kept');
      expect(r.tdeeDecisionKcal, isNull);
    });

    test('rejects unknown vocabulary before any write', () async {
      expect(
        () => repo.recordTdeeDecision(week, decision: 'maybe'),
        throwsArgumentError,
      );
      expect((await repo.forWeek(week))!.tdeeDecision, isNull);
    });

    test('rejects kcal outside 800..6000 before any write', () async {
      for (final kcal in const [799, 6001, -1, 0]) {
        expect(
          () => repo.recordTdeeDecision(week, decision: 'updated', kcal: kcal),
          throwsArgumentError,
        );
      }
      expect((await repo.forWeek(week))!.tdeeDecision, isNull);
      // Boundaries are inclusive.
      expect(
        await repo.recordTdeeDecision(week, decision: 'updated', kcal: 800),
        isTrue,
      );
    });
  });

  group('incrementNarrativeAttempts', () {
    test('counts up and touches nothing else', () async {
      final before = await repo.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{"a":1}',
      );
      expect(await repo.incrementNarrativeAttempts(week), 1);
      expect(await repo.incrementNarrativeAttempts(week), 2);
      final after = (await repo.forWeek(week))!;
      expect(after.narrativeAttempts, 2);
      expect(after.payloadJson, before.payloadJson);
      expect(after.narrativeJson, isNull);
      expect(after.tdeeDecision, isNull);
      expect(after.viewedAt, isNull);
    });
  });

  group('markViewed', () {
    test('sets viewedAt once and keeps the first value', () async {
      await repo.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{"a":1}',
      );
      await repo.markViewed(week);
      final first = (await repo.forWeek(week))!.viewedAt;
      expect(first, DateTime(2026, 10, 4, 18));
      clock.advance(const Duration(days: 1));
      await repo.markViewed(week);
      expect((await repo.forWeek(week))!.viewedAt, first);
    });
  });

  test('no mutator changes the frozen payload or week start', () async {
    await repo.insertSnapshot(
      week: week,
      payloadVersion: 1,
      payloadJson: '{"a":1,"nested":{"b":[1,2,3]}}',
    );
    await repo.incrementNarrativeAttempts(week);
    await repo.saveNarrative(
      week,
      narrativeJson: '{"summary":"x"}',
      knowledgeVersion: 'kb',
      modelVersion: 'm',
    );
    await repo.recordTdeeDecision(week, decision: 'updated', kcal: 2500);
    await repo.markViewed(week);
    await repo.insertSnapshot(
      week: week,
      payloadVersion: 1,
      payloadJson: '{"overwrite":true}',
    );

    final rows = await db.select(db.weeklyReports).get();
    expect(rows, hasLength(1));
    expect(rows.single.payloadJson, '{"a":1,"nested":{"b":[1,2,3]}}');
    expect(rows.single.weekStartIso, week.startIso);
    expect(rows.single.isoYear, 2026);
    expect(rows.single.isoWeek, 40);
  });
}
