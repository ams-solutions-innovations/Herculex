import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/labs/domain/labs_diet_evaluator.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';

void main() {
  test(
    'diet periods show goal, adherence and observed weight without declaring a winning diet',
    () {
      final events = [
        {
          'at': '2026-01-01',
          'end': '2026-01-29',
          'category': 'nutrition',
          'title': 'Higher-protein diet',
          'details': {'kind': 'diet', 'goal': 'fat_loss'},
        },
      ];
      final period = LabsPeriod(DateTime(2026, 1), DateTime(2026, 2));
      final rows = [
        for (var i = 0; i < 28; i++) ...[
          LabsObservation(
            id: 'food:$i',
            category: LabsCategory.nutrition,
            metric: 'kcal',
            at: DateTime(2026, 1, 1 + i),
            value: 2200,
            unit: 'kcal',
            source: 'fixture',
          ),
          LabsObservation(
            id: 'weight:$i',
            category: LabsCategory.physique,
            metric: 'bodyweight',
            at: DateTime(2026, 1, 1 + i),
            value: 80 - i * .05,
            unit: 'kg',
            source: 'fixture',
          ),
        ],
      ];
      final f = LabsDietEvaluator.evaluate(events, rows, period).single;
      expect(f.support, 'Descriptive change');
      expect(f.delta, lessThan(0));
      expect(f.detail, contains('fat loss'));
      expect(f.detail, contains('no diet is declared best'));
      final missing = LabsDietEvaluator.evaluate(
        events,
        rows.where((o) => o.metric != 'bodyweight').toList(),
        period,
      ).single;
      expect(missing.support, 'Collecting data');
      expect(missing.delta, isNull);
    },
  );
}
