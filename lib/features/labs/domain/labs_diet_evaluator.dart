import 'package:herculex/features/labs/domain/labs_models.dart';

abstract final class LabsDietEvaluator {
  static List<LabsFinding> evaluate(
    List<Map<String, dynamic>> events,
    List<LabsObservation> observations,
    LabsPeriod window,
  ) {
    final results = <LabsFinding>[];
    for (final event in events) {
      final details = event['details'] as Map? ?? {};
      if (event['category'] != 'nutrition' || details['kind'] != 'diet') {
        continue;
      }
      final start = DateTime.parse(event['at']);
      final requestedEnd = DateTime.tryParse(event['end'] ?? '') ?? window.end;
      final end = requestedEnd.isAfter(window.end) ? window.end : requestedEnd;
      if (!start.isBefore(end) || !end.isAfter(window.start)) continue;
      final days = DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      final data = observations
          .where((o) => !o.at.isBefore(start) && o.at.isBefore(end))
          .toList();
      final intake = data.where((o) => o.metric == 'kcal').toList();
      final weights = data.where((o) => o.metric == 'bodyweight').toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      final hunger = data
          .where((o) => o.metric == 'hunger')
          .map((o) => o.value)
          .toList();
      final complete =
          days >= 14 &&
          intake.map((o) => labsDate(o.at)).toSet().length >= 10 &&
          weights.map((o) => labsDate(o.at)).toSet().length >= 4;
      final midpoint = DateTime(start.year, start.month, start.day + days ~/ 2);
      final first = weights
          .where((o) => o.at.isBefore(midpoint))
          .map((o) => o.value)
          .toList();
      final last = weights
          .where((o) => !o.at.isBefore(midpoint))
          .map((o) => o.value)
          .toList();
      final before = first.isEmpty ? null : _mean(first),
          after = last.isEmpty ? null : _mean(last);
      final delta = complete && before != null && after != null
          ? after - before
          : null;
      final goal = details['goal'] ?? 'maintenance';
      results.add(
        LabsFinding(
          id: 'diet:${event['at']}:${event['title']}',
          category: LabsCategory.nutrition,
          title: 'Diet period · ${event['title']}',
          detail:
              'Goal: ${goal.toString().replaceAll('_', ' ')}. ${intake.length} days with recorded intake over $days calendar days. '
              '${delta == null ? 'More consistent intake and weigh-ins are needed.' : 'Observed bodyweight difference: ${delta.toStringAsFixed(1)} kg between period halves.'}'
              '${hunger.isEmpty ? '' : ' Average reported hunger ${_mean(hunger).toStringAsFixed(1)}/5.'}'
              ' Compare progress, hunger and adherence across periods with the same goal; no diet is declared best from one period.',
          support: complete ? 'Descriptive change' : 'Collecting data',
          points: weights,
          before: before,
          after: after,
          delta: delta,
          unit: 'kg',
          comparisonStart: start,
          comparisonEnd: end,
          coverage: days <= 0 ? 0 : (intake.length / days).clamp(0, 1),
          method: 'diet-period-descriptive-v1',
          limitations: [
            'Recorded intake may be incomplete.',
            'Bodyweight includes fluid and other non-fat changes.',
            'Diet composition, supplements, training and sleep can change together.',
            'Product screening minimum: 14 days, 10 logged intake days and 4 weigh-in days; not proof of a diet effect.',
          ],
        ),
      );
    }
    return results;
  }

  static double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
}
