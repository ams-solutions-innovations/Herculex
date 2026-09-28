import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/tdee_estimates_repository.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  DateTime time;
  _FixedClock(this.time);
  @override
  DateTime now() => time;
}

TdeeEstimateResult _result({
  int kcal = 2500,
  TdeeMethod method = TdeeMethod.observed,
  TdeeConfidence confidence = TdeeConfidence.medium,
  int windowDays = 28,
  bool observedQualified = true,
  Map<String, Object?> inputs = const {'span_days': 27, 'mean_intake': 2400.5},
  DateTime? estimatedAt,
}) => TdeeEstimateResult(
  kcal: kcal,
  method: method,
  confidence: confidence,
  windowDays: windowDays,
  observedQualified: observedQualified,
  inputs: inputs,
  estimatedAt: estimatedAt ?? DateTime(2026, 9, 28, 8),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TdeeEstimatesRepository', () {
    late AppDatabase db;
    late _FixedClock clock;
    late TdeeEstimatesRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      clock = _FixedClock(DateTime(2026, 9, 28, 12));
      repo = TdeeEstimatesRepository(db, clock);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'record stores dateIso from the Clock and estimatedAt from result',
      () async {
        // Result stamped a different day than the clock: dateIso follows Clock.
        await repo.record(_result(estimatedAt: DateTime(2026, 9, 20, 6)));

        final rows = await db.select(db.tdeeEstimates).get();
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row.dateIso, '2026-09-28');
        expect(row.estimatedAt, DateTime(2026, 9, 20, 6));
        expect(row.method, 'observed');
        expect(row.confidence, 'medium');
        expect(row.windowDays, 28);
        expect(row.kcal, 2500);
        expect(row.observedQualified, isTrue);
        expect(row.inputsJson, contains('span_days'));
      },
    );

    test(
      'latest is null and watchLatest emits null on an empty table',
      () async {
        expect(await repo.latest(), isNull);
        expect(await repo.watchLatest().first, isNull);
      },
    );

    test('watchLatest emits null then the new row after record', () async {
      final emissions = <TdeeEstimateResult?>[];
      final sub = repo.watchLatest().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.record(_result(kcal: 2600));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emissions.first, isNull);
      expect(emissions.last, isNotNull);
      expect(emissions.last!.kcal, 2600);
    });

    test(
      'latest returns newest by estimatedAt then id, deletedAt null only',
      () async {
        await repo.record(
          _result(kcal: 2000, estimatedAt: DateTime(2026, 9, 1)),
        );
        await repo.record(
          _result(kcal: 2100, estimatedAt: DateTime(2026, 9, 10)),
        );
        await repo.record(
          _result(kcal: 2200, estimatedAt: DateTime(2026, 9, 10)),
        );

        final latest = await repo.latest();
        expect(latest!.kcal, 2200); // same estimatedAt, higher id wins
      },
    );

    test(
      'recent is newest-first, limited, ties broken by highest id',
      () async {
        for (var i = 0; i < 10; i++) {
          await repo.record(
            _result(kcal: 2000 + i, estimatedAt: DateTime(2026, 9, 1 + i ~/ 2)),
          );
        }
        final recent = await repo.recent(limit: 4);
        expect(recent, hasLength(4));
        expect(recent.map((r) => r.kcal), [2009, 2008, 2007, 2006]);

        final defaults = await repo.recent();
        expect(defaults, hasLength(8));
      },
    );

    test('round trip preserves every field', () async {
      final original = _result(
        kcal: 2734,
        method: TdeeMethod.classifier,
        confidence: TdeeConfidence.low,
        windowDays: 14,
        observedQualified: false,
        inputs: const {'steps_avg': 8123.5, 'workouts_per_week': 3},
        estimatedAt: DateTime(2026, 9, 27, 7, 30),
      );
      await repo.record(original);

      final back = (await repo.latest())!;
      expect(back.kcal, 2734);
      expect(back.method, TdeeMethod.classifier);
      expect(back.confidence, TdeeConfidence.low);
      expect(back.windowDays, 14);
      expect(back.observedQualified, isFalse);
      expect(back.inputs, original.inputs);
      expect(back.estimatedAt, DateTime(2026, 9, 27, 7, 30));
    });

    test('coldStart and held rows persist and read back', () async {
      await repo.record(
        _result(
          method: TdeeMethod.coldStart,
          confidence: TdeeConfidence.low,
          windowDays: 0,
          observedQualified: false,
          inputs: const {},
          estimatedAt: DateTime(2026, 9, 1),
        ),
      );
      await repo.record(
        _result(
          method: TdeeMethod.observed,
          observedQualified: false,
          estimatedAt: DateTime(2026, 9, 2),
        ),
      );
      final rows = await repo.recent();
      expect(rows.first.isHeld, isTrue);
      expect(rows.last.method, TdeeMethod.coldStart);
    });

    test(
      'unknown method / confidence and corrupt inputsJson read safely',
      () async {
        await db
            .into(db.tdeeEstimates)
            .insert(
              TdeeEstimatesCompanion.insert(
                dateIso: '2026-09-28',
                method: 'garbage',
                confidence: 'garbage',
                windowDays: 7,
                kcal: 2300,
                inputsJson: 'not json',
                estimatedAt: Value(DateTime(2026, 9, 28)),
              ),
            );

        final r = (await repo.latest())!;
        expect(r.method, TdeeMethod.coldStart);
        expect(r.confidence, TdeeConfidence.low);
        expect(r.inputs, isEmpty);
      },
    );

    test(
      'inputsJson that is valid JSON but not an object reads as empty',
      () async {
        await db
            .into(db.tdeeEstimates)
            .insert(
              TdeeEstimatesCompanion.insert(
                dateIso: '2026-09-28',
                method: 'observed',
                confidence: 'high',
                windowDays: 7,
                kcal: 2300,
                inputsJson: '[1,2,3]',
              ),
            );
        final r = (await repo.latest())!;
        expect(r.inputs, isEmpty);
      },
    );

    test('record rejects out-of-range kcal and negative windowDays', () async {
      expect(() => repo.record(_result(kcal: 0)), throwsArgumentError);
      expect(() => repo.record(_result(kcal: -5)), throwsArgumentError);
      expect(() => repo.record(_result(kcal: 10001)), throwsArgumentError);
      expect(() => repo.record(_result(windowDays: -1)), throwsArgumentError);
      expect(await db.select(db.tdeeEstimates).get(), isEmpty);

      // Boundary values are accepted.
      await repo.record(_result(kcal: 10000, windowDays: 0));
      expect(await db.select(db.tdeeEstimates).get(), hasLength(1));
    });

    test('soft-deleted rows are excluded from latest and recent', () async {
      await repo.record(_result(kcal: 2000, estimatedAt: DateTime(2026, 9, 1)));
      await repo.record(
        _result(kcal: 2900, estimatedAt: DateTime(2026, 9, 20)),
      );
      await (db.update(
        db.tdeeEstimates,
      )..where((t) => t.kcal.equals(2900))).write(
        TdeeEstimatesCompanion(deletedAt: Value(DateTime(2026, 9, 21))),
      );

      expect((await repo.latest())!.kcal, 2000);
      expect((await repo.recent()).map((r) => r.kcal), [2000]);
      expect((await repo.watchLatest().first)!.kcal, 2000);
    });

    test('record never touches nutrition_targets', () async {
      final before = await db.select(db.nutritionTargets).get();
      await repo.record(_result());
      final after = await db.select(db.nutritionTargets).get();
      expect(after.length, before.length);
    });
  });
}
