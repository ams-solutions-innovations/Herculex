import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/labs/domain/labs_engine.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';

LabsObservation observation(
  int day,
  double value, {
  String metric = 'bodyweight',
  LabsCategory category = LabsCategory.physique,
  String? id,
}) => LabsObservation(
  id: id ?? '$metric:$day',
  category: category,
  metric: metric,
  at: DateTime(2026, 1, 1 + day),
  value: value,
  unit: 'kg',
  source: 'fixture',
);

void main() {
  final period = LabsPeriod(DateTime(2026, 1), DateTime(2026, 2));
  test(
    'descriptive change preserves explicit zero and deduplicates source rows',
    () {
      final rows = [
        for (var i = 0; i < 31; i++) observation(i, i < 15 ? 0 : 10),
      ];
      final f = LabsEngine.analyze(
        [...rows, ...rows],
        period,
        {LabsCategory.physique},
      ).single;
      expect(f.n, 31);
      expect(f.before, 0);
      expect(f.after, 10);
      expect(f.delta, 10);
      expect(f.support, 'Descriptive change');
      expect(f.coverage, 1);
    },
  );
  test('missing and nonfinite samples do not produce a conclusion', () {
    final f = LabsEngine.analyze(
      [observation(0, 80), observation(15, double.nan)],
      period,
      {LabsCategory.physique},
    ).single;
    expect(f.n, 1);
    expect(f.delta, isNull);
    expect(f.support, 'Collecting data');
  });
  test('revoked categories excluded from all outputs', () {
    expect(LabsEngine.analyze([observation(0, 80)], period, {}), isEmpty);
  });
  test(
    'future data and other equipment strata cannot contaminate comparisons',
    () {
      final findings = LabsEngine.analyze(
        [observation(0, 80), observation(50, 100)],
        period,
        {LabsCategory.physique},
      );
      expect(findings.single.n, 1);
    },
  );
  test('pure linear time trends do not become an exploratory association', () {
    final rows = <LabsObservation>[];
    for (var day = 0; day < 140; day++) {
      rows.add(
        observation(
          day,
          6 + day / 100,
          metric: 'sleep_hours',
          category: LabsCategory.sleep,
        ),
      );
      rows.add(
        observation(
          day,
          50 + day.toDouble(),
          metric: 'e1rm',
          category: LabsCategory.strength,
        ),
      );
    }
    final results = LabsEngine.analyze(
      rows,
      LabsPeriod(DateTime(2026, 4), DateTime(2026, 6)),
      {LabsCategory.sleep, LabsCategory.strength},
    );
    expect(results.where((f) => f.id.startsWith('association:')), isEmpty);
  });
  test(
    'known lagged association is deterministic with corrected q and uncertainty',
    () {
      final random = Random(71), rows = <LabsObservation>[];
      final x = List.generate(160, (_) => random.nextDouble());
      for (var day = 0; day < 150; day++) {
        rows.add(
          observation(
            day,
            6 + x[day] * 3,
            metric: 'sleep_hours',
            category: LabsCategory.sleep,
          ),
        );
        rows.add(
          observation(
            day,
            50 + x[day] * 20 + random.nextDouble(),
            metric: 'e1rm',
            category: LabsCategory.strength,
          ),
        );
      }
      final p = LabsPeriod(DateTime(2026, 4), DateTime(2026, 6));
      final one = LabsEngine.analyze(rows, p, {
        LabsCategory.sleep,
        LabsCategory.strength,
      });
      final two = LabsEngine.analyze(rows, p, {
        LabsCategory.sleep,
        LabsCategory.strength,
      });
      final f = one.singleWhere(
        (f) => f.id.startsWith('association:sleep-performance'),
      );
      expect(f.q, lessThan(.05));
      expect(f.intervalLow, greaterThan(.8));
      expect(
        one.map((f) => f.toJson()).toString(),
        two.map((f) => f.toJson()).toString(),
      );
    },
  );
  test('too few weekly blocks never produce an association', () {
    final rows = [
      for (var i = 0; i < 30; i++) ...[
        observation(
          i,
          (i % 5).toDouble(),
          metric: 'sleep_hours',
          category: LabsCategory.sleep,
        ),
        observation(
          i,
          (i % 5).toDouble(),
          metric: 'e1rm',
          category: LabsCategory.strength,
        ),
      ],
    ];
    expect(
      LabsEngine.analyze(rows, period, {
        LabsCategory.sleep,
        LabsCategory.strength,
      }).where((f) => f.p != null),
      isEmpty,
    );
  });
  test('calendar schedule handles month, leap year and year boundaries', () {
    expect(LabsPeriod.nextReport(DateTime(2026, 12, 16)), DateTime(2027));
    final due = LabsPeriod.due(DateTime(2024, 2, 12), DateTime(2024, 3, 1));
    expect(due.length, 2);
    expect(due.last.end, DateTime(2024, 3));
    expect(
      LabsPeriod.due(DateTime(2026, 1, 1), DateTime(2026, 1, 15)),
      isEmpty,
    );
  });
  test('snapshot roundtrip retains provenance, intervals and revision', () {
    final s = LabsSnapshot(
      period: period,
      generatedAt: DateTime(2026, 2),
      revision: 2,
      findings: LabsEngine.analyze(
        [observation(0, 80)],
        period,
        {LabsCategory.physique},
      ),
    );
    final copy = LabsSnapshot.fromJson(s.toJson());
    expect(copy.fingerprint, s.fingerprint);
    expect(copy.revision, 2);
    expect(copy.findings.single.points.single.source, 'fixture');
  });
}
