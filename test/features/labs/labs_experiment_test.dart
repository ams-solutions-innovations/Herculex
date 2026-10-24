import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/labs/domain/labs_experiment_evaluator.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';

void main() {
  test(
    'experiment target waits for review and never crosses equipment strata',
    () {
      final definition = <String, dynamic>{
        'at': '2026-01-01',
        'baselineEnd': '2026-01-15',
        'end': '2026-01-29',
        'metric': 'e1rm',
        'target': 2,
        'direction': 'increase',
        'status': 'active',
      };
      final rows = [
        for (var i = 0; i < 28; i++)
          LabsObservation(
            id: '$i',
            category: LabsCategory.strength,
            metric: 'e1rm',
            at: DateTime(2026, 1, 1 + i),
            value: i < 14 ? 80 : 85,
            unit: 'kg',
            source: 'fixture',
            stratum: 'barbell',
          ),
      ];
      final during = LabsExperimentEvaluator.evaluate(
        definition,
        rows,
        DateTime(2026, 1, 20),
      )['evaluation'];
      expect(during['targetMet'], isNull);
      final done = LabsExperimentEvaluator.evaluate(
        definition,
        rows,
        DateTime(2026, 1, 29),
      )['evaluation'];
      expect(done['targetMet'], true);
      expect(done['delta'], 5);
      expect(done['state'], 'Descriptive result');
      final stopped = LabsExperimentEvaluator.evaluate(
        {...definition, 'status': 'stopped'},
        rows,
        DateTime(2026, 1, 29),
      )['evaluation'];
      expect(stopped['state'], 'Stopped');
      expect(stopped['targetMet'], isNull);
    },
  );
}
