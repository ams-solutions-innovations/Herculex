import 'dart:math';
import 'package:herculex/features/labs/domain/labs_models.dart';

class LabsAnalysisRule {
  const LabsAnalysisRule(
    this.id,
    this.category,
    this.exposure,
    this.outcome,
    this.label, {
    this.lagDays = 0,
    this.minimumWeeks = 8,
  });
  final String id, exposure, outcome, label;
  final LabsCategory category;
  final int lagDays, minimumWeeks;
}

/// Fixed hypotheses, rather than mining every possible metric pair.
const labsAnalysisCatalog = [
  LabsAnalysisRule(
    'sleep-performance',
    LabsCategory.sleep,
    'sleep_hours',
    'e1rm',
    'Sleep & comparable strength',
  ),
  LabsAnalysisRule(
    'training-sleep',
    LabsCategory.sleep,
    'training_minutes',
    'sleep_hours',
    'Training duration & following sleep',
    lagDays: 1,
  ),
  LabsAnalysisRule(
    'protein-strength',
    LabsCategory.nutrition,
    'protein_g_kg',
    'e1rm',
    'Protein intake & comparable strength',
    lagDays: 1,
  ),
  LabsAnalysisRule(
    'energy-weight',
    LabsCategory.nutrition,
    'kcal',
    'bodyweight',
    'Recorded intake & bodyweight',
    lagDays: 7,
  ),
  LabsAnalysisRule(
    'fasting-performance',
    LabsCategory.fasting,
    'fasting_hours',
    'e1rm',
    'Fasting duration & comparable strength',
  ),
  LabsAnalysisRule(
    'fasting-hunger',
    LabsCategory.fasting,
    'fasting_hours',
    'hunger',
    'Fasting duration & hunger',
  ),
  LabsAnalysisRule(
    'stress-sleep',
    LabsCategory.context,
    'stress',
    'sleep_hours',
    'Stress & following sleep',
    lagDays: 1,
  ),
  LabsAnalysisRule(
    'steps-sleep',
    LabsCategory.context,
    'steps',
    'sleep_hours',
    'Steps & following sleep',
    lagDays: 1,
  ),
  LabsAnalysisRule(
    'technique-fatigue',
    LabsCategory.techniques,
    'advanced_fraction',
    'pain',
    'Advanced techniques & next-day soreness',
    lagDays: 1,
  ),
  LabsAnalysisRule(
    'density-energy',
    LabsCategory.training,
    'density',
    'energy',
    'Training density & next-day energy',
    lagDays: 1,
  ),
  LabsAnalysisRule(
    'superset-efficiency',
    LabsCategory.techniques,
    'superset_fraction',
    'density',
    'Supersets & training density',
  ),
  LabsAnalysisRule(
    'training-time-sleep',
    LabsCategory.sleep,
    'training_hour',
    'sleep_hours',
    'Training time & following sleep',
    lagDays: 1,
  ),
  LabsAnalysisRule(
    'fiber-hunger',
    LabsCategory.nutrition,
    'fiber',
    'hunger',
    'Recorded fibre & hunger',
  ),
  LabsAnalysisRule(
    'fasting-weight',
    LabsCategory.fasting,
    'fasting_hours',
    'bodyweight',
    'Fasting duration & later bodyweight',
    lagDays: 7,
  ),
];

const labsSources = {
  'N-of-1 design, trends and carryover':
      'https://effectivehealthcare.ahrq.gov/products/n-1-trials/research-2014-5',
  'Individual resistance-training responses and measurement variability':
      'https://pubmed.ncbi.nlm.nih.gov/38878117/',
};

const labsMetricLabels = {
  'exercise_load': 'Progression through load',
  'exercise_reps': 'Progression through repetitions',
  'exercise_sets': 'Progression through working sets',
  'supplement_dose': 'Recorded supplement dose',
  'muscle_sets': 'Primary-muscle working sets',
  'set_type': 'Working sets by technique',
  'rep_band_1_5': 'Low-rep working sets (1–5)',
  'rep_band_6_12': 'Moderate-rep working sets (6–12)',
  'rep_band_13_30': 'High-rep working sets (13–30)',
  'e1rm': 'Estimated 1RM',
  'bodyweight': 'Bodyweight',
  'sleep_hours': 'Sleep duration',
  'training_minutes': 'Training duration',
  'working_sets': 'Working sets',
  'reps': 'Repetitions',
  'rpe': 'Recorded effort',
  'density': 'Working sets per minute',
  'advanced_fraction': 'Advanced-set share',
  'superset_fraction': 'Superset share',
  'kcal': 'Recorded energy intake',
  'protein': 'Recorded protein',
  'protein_g_kg': 'Protein per kg',
  'carbs': 'Recorded carbohydrates',
  'fat': 'Recorded fat',
  'fiber': 'Recorded fibre',
  'fasting_hours': 'Fasting duration',
  'steps': 'Steps',
  'water_ml': 'Water',
  'resting_hr': 'Resting heart rate',
  'energy': 'Energy',
  'stress': 'Stress',
  'pain': 'Soreness',
  'hunger': 'Hunger',
  'digestion': 'Digestive discomfort',
  'physique_checkin': 'Physique check-in',
  'training_hour': 'Training start time',
  'rep_mean': 'Mean reps per working set',
  'sleep_quality': 'Sleep quality',
  'caffeine_mg': 'Caffeine',
  'alcohol_units': 'Alcohol',
};

/// Pure, deterministic engine. Descriptive metrics never imply causality.
abstract final class LabsEngine {
  static List<LabsFinding> analyze(
    List<LabsObservation> input,
    LabsPeriod period,
    Set<LabsCategory> categories,
  ) {
    // Dedupe exact source identities, retain explicit zero and reject NaN.
    final unique = <String, LabsObservation>{};
    for (final o in input) {
      if (o.value.isFinite &&
          categories.contains(o.category) &&
          o.at.isBefore(period.end)) {
        unique[o.id] = o;
      }
    }
    final observations = unique.values.toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final groups = <String, List<LabsObservation>>{};
    for (final o in observations.where((o) => period.contains(o.at))) {
      groups.putIfAbsent('${o.metric}|${o.stratum}', () => []).add(o);
    }
    final findings = <LabsFinding>[];
    final midpoint = DateTime(
      period.start.year,
      period.start.month,
      period.start.day + (_days(period.start, period.end) ~/ 2),
    );
    for (final entry in groups.entries) {
      final rows = _daily(entry.value);
      final first = rows
          .where((o) => o.at.isBefore(midpoint))
          .map((o) => o.value)
          .toList();
      final last = rows
          .where((o) => !o.at.isBefore(midpoint))
          .map((o) => o.value)
          .toList();
      final enough = first.length >= 3 && last.length >= 3;
      final a = first.isEmpty ? null : _mean(first);
      final b = last.isEmpty ? null : _mean(last);
      final metric = rows.first.metric;
      findings.add(
        LabsFinding(
          id: 'trend:${entry.key}',
          category: rows.first.category,
          title:
              '${labsMetricLabels[metric] ?? metric}${rows.first.stratum.isEmpty ? '' : ' · ${rows.first.stratum}'}',
          detail: enough
              ? 'Recorded average: ${a!.toStringAsFixed(1)} → ${b!.toStringAsFixed(1)} ${rows.first.unit}. Descriptive change within this period.'
              : 'Collect observations in both halves of this period (at least 3 days each).',
          support: enough ? 'Descriptive change' : 'Collecting data',
          points: rows,
          coverage: min(
            1,
            rows.length / max(1, _days(period.start, period.end)),
          ),
          before: a,
          after: b,
          delta: enough ? b! - a! : null,
          unit: rows.first.unit,
          comparisonStart: period.start,
          comparisonEnd: period.end,
          limitations: [
            'Logged days may not represent unlogged days.',
            if (rows.any((r) => r.quality == 'estimated'))
              'Includes estimates, not direct measurements.',
            if (rows.first.category == LabsCategory.nutrition)
              'Food logging can be incomplete; recorded intake is not confirmed total intake.',
            'This change does not identify its cause.',
          ],
        ),
      );
    }
    final candidates = <_Association>[];
    final rules = [...labsAnalysisCatalog];
    // Every supplement identity is a separate prespecified exposure.
    for (final metric
        in observations
            .where((o) => o.metric.startsWith('supplement:'))
            .map((o) => o.metric)
            .toSet()
            .toList()
          ..sort()) {
      rules.add(
        LabsAnalysisRule(
          '$metric-strength',
          LabsCategory.supplements,
          metric,
          'e1rm',
          '${metric.substring(11)} & comparable strength',
          lagDays: 7,
        ),
      );
      rules.add(
        LabsAnalysisRule(
          '$metric-weight',
          LabsCategory.supplements,
          metric,
          'bodyweight',
          '${metric.substring(11)} & bodyweight',
          lagDays: 7,
        ),
      );
      rules.add(
        LabsAnalysisRule(
          '$metric-sleep',
          LabsCategory.supplements,
          metric,
          'sleep_hours',
          '${metric.substring(11)} & following sleep',
          lagDays: 1,
        ),
      );
    }
    for (final rule in rules.where((r) => categories.contains(r.category))) {
      final result = _association(observations, rule, period);
      if (result != null) candidates.add(result);
    }
    // Benjamini-Hochberg correction across every tested hypothesis/stratum.
    candidates.sort((a, b) => a.p.compareTo(b.p));
    var previous = 1.0;
    for (var i = candidates.length - 1; i >= 0; i--) {
      final c = candidates[i];
      final q = min(previous, c.p * candidates.length / (i + 1));
      previous = q;
      findings.add(
        LabsFinding(
          id: 'association:${c.rule.id}:${c.stratum}',
          category: c.rule.category,
          title: '${c.rule.label}${c.stratum.isEmpty ? '' : ' · ${c.stratum}'}',
          detail:
              'Time-adjusted weekly association r=${c.r.toStringAsFixed(2)}; '
              '${c.weeks} weekly blocks, lag ${c.rule.lagDays} day(s). '
              '${q <= .05 ? 'Exploratory signal after multiple-comparison correction.' : 'No clear signal after multiple-comparison correction.'}',
          support: q <= .05 ? 'Exploratory association' : 'Inconclusive',
          points: c.points,
          coverage: c.coverage,
          p: c.p,
          q: q,
          intervalLow: c.low,
          intervalHigh: c.high,
          comparisonStart: c.points.first.at,
          comparisonEnd: period.end,
          method: 'weekly-detrended-block-permutation-bh-v1',
          limitations: [
            'Observational association; does not establish causation.',
            'Weekly blocks reduce serial dependence but cannot remove all carryover.',
            'Other simultaneous changes may explain the association.',
            '95% moving-block bootstrap interval describes the association, not an intervention effect.',
            if (c.rule.category == LabsCategory.supplements)
              'Unknown intake days excluded. No dose-response or washout claim.',
          ],
        ),
      );
    }
    for (final category in categories) {
      if (!findings.any((f) => f.category == category)) {
        findings.add(
          LabsFinding(
            id: 'empty:${category.name}',
            category: category,
            title: category.label,
            detail:
                'No supported observations in this period. Add records in the existing tracker.',
            support: 'Collecting data',
            points: const [],
            coverage: 0,
            comparisonStart: period.start,
            comparisonEnd: period.end,
          ),
        );
      }
    }
    findings.sort((a, b) {
      int rank(LabsFinding f) => f.support == 'Exploratory association'
          ? 0
          : f.delta != null
          ? 1
          : 2;
      final order = rank(a).compareTo(rank(b));
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return findings;
  }

  static _Association? _association(
    List<LabsObservation> obs,
    LabsAnalysisRule rule,
    LabsPeriod period,
  ) {
    // At most 180 calendar days ending at this snapshot boundary.
    final start = DateTime(
      period.end.year,
      period.end.month,
      period.end.day - 180,
    );
    final xs = <String, List<double>>{};
    for (final o in obs.where(
      (o) => o.metric == rule.exposure && !o.at.isBefore(start),
    )) {
      xs.putIfAbsent(labsDate(o.at), () => []).add(o.value);
    }
    final outcomes = obs.where(
      (o) => o.metric == rule.outcome && !o.at.isBefore(start),
    );
    final strata = outcomes.map((o) => o.stratum).toSet().toList()..sort();
    // Separate equipment/exercise/effort strata. One result per rule is chosen
    // by coverage only, before evaluating any outcome association.
    List<LabsObservation> best = [];
    for (final s in strata) {
      final paired = _daily(outcomes.where((o) => o.stratum == s).toList())
          .where(
            (o) => xs.containsKey(
              labsDate(
                DateTime(o.at.year, o.at.month, o.at.day - rule.lagDays),
              ),
            ),
          )
          .toList();
      if (paired.length > best.length) best = paired;
    }
    if (best.isEmpty) return null;
    final blocks = <int, List<(double, double, double)>>{};
    for (final o in best) {
      final date = DateTime.utc(o.at.year, o.at.month, o.at.day);
      final week = date.difference(DateTime.utc(1970, 1, 5)).inDays ~/ 7;
      final x = _mean(
        xs[labsDate(DateTime(o.at.year, o.at.month, o.at.day - rule.lagDays))]!,
      );
      blocks.putIfAbsent(week, () => []).add((
        x,
        o.value,
        date.millisecondsSinceEpoch / 86400000,
      ));
    }
    if (blocks.length < rule.minimumWeeks) return null;
    final keys = blocks.keys.toList()..sort();
    final t = keys
        .map((k) => _mean(blocks[k]!.map((v) => v.$3).toList()))
        .toList();
    final x = _detrend(
      t,
      keys.map((k) => _mean(blocks[k]!.map((v) => v.$1).toList())).toList(),
    );
    final y = _detrend(
      t,
      keys.map((k) => _mean(blocks[k]!.map((v) => v.$2).toList())).toList(),
    );
    if (_variance(x) < 1e-9 || _variance(y) < 1e-9) return null;
    final r = _correlation(x, y);
    final random = Random(1701);
    var extreme = 1;
    final boot = <double>[];
    for (var i = 0; i < 999; i++) {
      final chunks = <List<double>>[
        for (var j = 0; j < y.length; j += 2)
          y.sublist(j, min(j + 2, y.length)),
      ]..shuffle(random);
      final shuffled = chunks.expand((v) => v).toList();
      if (_correlation(x, shuffled).abs() >= r.abs()) extreme++;
      final indices = <int>[];
      while (indices.length < x.length) {
        final start = random.nextInt(x.length);
        indices.add(start);
        if (indices.length < x.length) indices.add((start + 1) % x.length);
      }
      final bx = indices.map((j) => x[j]).toList();
      final by = indices.map((j) => y[j]).toList();
      if (_variance(bx) > 1e-9 && _variance(by) > 1e-9) {
        boot.add(_correlation(bx, by));
      }
    }
    boot.sort();
    return _Association(
      rule,
      r,
      extreme / 1000,
      best,
      blocks.length,
      min(1, best.length / max(1, _days(start, period.end))),
      boot.isEmpty ? -1 : boot[(boot.length * .025).floor()],
      boot.isEmpty
          ? 1
          : boot[min(boot.length - 1, (boot.length * .975).floor())],
    );
  }

  static List<LabsObservation> _daily(List<LabsObservation> rows) {
    final groups = <String, List<LabsObservation>>{};
    for (final row in rows) {
      groups.putIfAbsent(labsDate(row.at), () => []).add(row);
    }
    return groups.values
        .map(
          (g) => LabsObservation(
            id: g.first.id,
            category: g.first.category,
            metric: g.first.metric,
            at: labsDay(g.first.at),
            value: _aggregate(g),
            unit: g.first.unit,
            source: g.first.source,
            quality: g.first.quality,
            stratum: g.first.stratum,
          ),
        )
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  static double _aggregate(List<LabsObservation> rows) {
    final values = rows.map((o) => o.value).toList();
    final metric = rows.first.metric;
    if (metric == 'e1rm') return values.reduce(max);
    if ([
          'working_sets',
          'reps',
          'training_minutes',
          'muscle_sets',
          'set_type',
        ].contains(metric) ||
        metric.startsWith('rep_band_')) {
      return values.reduce((a, b) => a + b);
    }
    return _mean(values);
  }

  static int _days(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  static double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
  static double _variance(List<double> v) {
    final m = _mean(v);
    return v.fold(0.0, (s, x) => s + pow(x - m, 2));
  }

  static double _correlation(List<double> x, List<double> y) {
    final a = _mean(x), b = _mean(y);
    final den = sqrt(_variance(x) * _variance(y));
    if (den == 0) return 0;
    var sum = 0.0;
    for (var i = 0; i < x.length; i++) {
      sum += (x[i] - a) * (y[i] - b);
    }
    return (sum / den).clamp(-1, 1);
  }

  static List<double> _detrend(List<double> t, List<double> v) {
    final tm = _mean(t), vm = _mean(v);
    var cov = 0.0;
    for (var i = 0; i < t.length; i++) {
      cov += (t[i] - tm) * (v[i] - vm);
    }
    final variance = _variance(t);
    final slope = variance == 0 ? 0 : cov / variance;
    return List.generate(v.length, (i) => v[i] - vm - slope * (t[i] - tm));
  }
}

class _Association {
  _Association(
    this.rule,
    this.r,
    this.p,
    this.points,
    this.weeks,
    this.coverage,
    this.low,
    this.high,
  );
  final LabsAnalysisRule rule;
  final double r, p, coverage, low, high;
  final int weeks;
  final List<LabsObservation> points;
  String get stratum => points.first.stratum;
}
