import 'package:herculex/features/labs/domain/labs_models.dart';

/// A baseline/intervention comparison is explicitly descriptive. No causal
/// promotion is made for an unrandomised, unblinded personal experiment.
abstract final class LabsExperimentEvaluator {
  static Map<String, dynamic> evaluate(
    Map<String, dynamic> definition,
    List<LabsObservation> observations,
    DateTime asOf,
  ) {
    final start = DateTime.parse(definition['at']);
    final change = DateTime.parse(definition['baselineEnd']);
    final end = DateTime.parse(definition['end']);
    final stopped = DateTime.tryParse(definition['stoppedAt'] ?? '');
    final candidates = <String, List<LabsObservation>>{};
    for (final o in observations.where(
      (o) =>
          o.metric == definition['metric'] &&
          !o.at.isBefore(start) &&
          o.at.isBefore(end) &&
          o.at.isBefore(asOf) &&
          (stopped == null || o.at.isBefore(stopped)),
    )) {
      candidates.putIfAbsent(o.stratum, () => []).add(o);
    }
    var best = <LabsObservation>[];
    for (final key in candidates.keys.toList()..sort()) {
      if (candidates[key]!.length > best.length) best = candidates[key]!;
    }
    final before = _days(best.where((o) => o.at.isBefore(change)));
    final after = _days(best.where((o) => !o.at.isBefore(change)));
    final enough = before.length >= 3 && after.length >= 3;
    final a = before.isEmpty
        ? null
        : before.reduce((a, b) => a + b) / before.length;
    final b = after.isEmpty
        ? null
        : after.reduce((a, b) => a + b) / after.length;
    final delta = enough ? b! - a! : null;
    final direction = definition['direction'] == 'decrease' ? -1 : 1;
    final target = (definition['target'] as num).toDouble();
    return {
      ...definition,
      'evaluation': {
        'asOf': labsDate(asOf),
        'beforeDays': before.length,
        'afterDays': after.length,
        'before': a,
        'after': b,
        'delta': delta,
        'stratum': best.isEmpty ? '' : best.first.stratum,
        'state': definition['status'] == 'stopped'
            ? 'Stopped'
            : asOf.isBefore(change)
            ? 'Baseline'
            : asOf.isBefore(end)
            ? 'Change phase'
            : enough
            ? 'Descriptive result'
            : 'Insufficient comparable data',
        'targetMet':
            definition['status'] != 'stopped' &&
                !asOf.isBefore(end) &&
                delta != null
            ? delta * direction >= target
            : null,
        'limitation':
            'Unblinded baseline/intervention comparison. Adherence and simultaneous changes require review; this does not isolate the intervention effect.',
      },
    };
  }

  static List<double> _days(Iterable<LabsObservation> rows) {
    final groups = <String, List<double>>{};
    for (final o in rows) {
      groups.putIfAbsent(labsDate(o.at), () => []).add(o.value);
    }
    return groups.values
        .map((g) => g.reduce((a, b) => a + b) / g.length)
        .toList();
  }
}
