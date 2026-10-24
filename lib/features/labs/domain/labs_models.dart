import 'dart:convert';

enum LabsCategory {
  strength('Strength & overload'),
  training('Training configuration'),
  techniques('Advanced techniques'),
  supplements('Supplements'),
  nutrition('Nutrition'),
  fasting('Fasting'),
  sleep('Sleep & recovery'),
  physique('Body & Dream Physique'),
  context('Daily context');

  const LabsCategory(this.label);
  final String label;
}

String labsDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime labsDay(DateTime d) => DateTime(d.year, d.month, d.day);

class LabsConsent {
  const LabsConsent({
    this.enabled = false,
    this.categories = const {},
    this.history = false,
    this.ai = false,
    this.since,
  });
  final bool enabled, history, ai;
  final Set<LabsCategory> categories;
  final DateTime? since;
  bool allows(LabsCategory c) => enabled && categories.contains(c);
  Map<String, dynamic> toJson() => {
    'version': 1,
    'enabled': enabled,
    'categories': categories.map((c) => c.name).toList(),
    'history': history,
    'ai': ai,
    'since': since?.toIso8601String(),
  };
  factory LabsConsent.fromJson(Map<String, dynamic> j) => LabsConsent(
    enabled: j['enabled'] == true,
    history: j['history'] == true,
    ai: j['ai'] == true,
    since: DateTime.tryParse(j['since'] as String? ?? ''),
    categories: LabsCategory.values
        .where((c) => (j['categories'] as List? ?? []).contains(c.name))
        .toSet(),
  );
}

/// One independent daily/session observation. Source rows are never mutated.
class LabsObservation {
  const LabsObservation({
    required this.id,
    required this.category,
    required this.metric,
    required this.at,
    required this.value,
    required this.unit,
    required this.source,
    this.quality = 'recorded',
    this.stratum = '',
    this.context = const {},
  });
  final String id, metric, unit, source, quality, stratum;
  final LabsCategory category;
  final DateTime at;
  final double value;
  final Map<String, double> context;
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'metric': metric,
    'at': at.toIso8601String(),
    'value': value,
    'unit': unit,
    'source': source,
    'quality': quality,
    'stratum': stratum,
    'context': context,
  };
  factory LabsObservation.fromJson(Map<String, dynamic> j) => LabsObservation(
    id: j['id'],
    category: LabsCategory.values.byName(j['category']),
    metric: j['metric'],
    at: DateTime.parse(j['at']),
    value: (j['value'] as num).toDouble(),
    unit: j['unit'],
    source: j['source'],
    quality: j['quality'],
    stratum: j['stratum'] ?? '',
    context: (j['context'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ),
  );
}

class LabsFinding {
  const LabsFinding({
    required this.id,
    required this.category,
    required this.title,
    required this.detail,
    required this.support,
    required this.points,
    required this.coverage,
    this.before,
    this.after,
    this.delta,
    this.p,
    this.q,
    this.intervalLow,
    this.intervalHigh,
    this.limitations = const [],
    this.method = 'labs-1',
    this.comparisonStart,
    this.comparisonEnd,
    this.unit = '',
  });
  final String id, title, detail, support, method, unit;
  final LabsCategory category;
  final List<LabsObservation> points;
  final double coverage;
  final double? before, after, delta, p, q, intervalLow, intervalHigh;
  final DateTime? comparisonStart, comparisonEnd;
  final List<String> limitations;
  int get n => points.length;
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'title': title,
    'detail': detail,
    'support': support,
    'points': points.map((p) => p.toJson()).toList(),
    'coverage': coverage,
    'before': before,
    'after': after,
    'delta': delta,
    'p': p,
    'q': q,
    'intervalLow': intervalLow,
    'intervalHigh': intervalHigh,
    'limitations': limitations,
    'method': method,
    'unit': unit,
    'comparisonStart': comparisonStart?.toIso8601String(),
    'comparisonEnd': comparisonEnd?.toIso8601String(),
  };
  factory LabsFinding.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return LabsFinding(
      id: j['id'],
      category: LabsCategory.values.byName(j['category']),
      title: j['title'],
      detail: j['detail'],
      support: j['support'],
      points: (j['points'] as List)
          .map((p) => LabsObservation.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      coverage: d('coverage')!,
      before: d('before'),
      after: d('after'),
      delta: d('delta'),
      p: d('p'),
      q: d('q'),
      intervalLow: d('intervalLow'),
      intervalHigh: d('intervalHigh'),
      unit: j['unit'] ?? '',
      limitations: List<String>.from(j['limitations']),
      method: j['method'],
      comparisonStart: DateTime.tryParse(j['comparisonStart'] ?? ''),
      comparisonEnd: DateTime.tryParse(j['comparisonEnd'] ?? ''),
    );
  }
}

class LabsPeriod {
  const LabsPeriod(this.start, this.end);
  final DateTime start, end; // End exclusive, local calendar boundaries.
  String get id => labsDate(start);
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  static LabsPeriod containing(DateTime d) => d.day < 16
      ? LabsPeriod(DateTime(d.year, d.month), DateTime(d.year, d.month, 16))
      : LabsPeriod(
          DateTime(d.year, d.month, 16),
          DateTime(d.year, d.month + 1),
        );
  static DateTime nextReport(DateTime now) => containing(now).end;
  static List<LabsPeriod> due(DateTime since, DateTime now) {
    final out = <LabsPeriod>[];
    var p = containing(since);
    while (!p.end.isAfter(now)) {
      out.add(p);
      p = containing(p.end);
    }
    return out;
  }
}

class LabsSnapshot {
  const LabsSnapshot({
    required this.period,
    required this.generatedAt,
    required this.findings,
    this.revision = 1,
    this.partial = false,
    this.events = const [],
    this.experiments = const [],
  });
  final LabsPeriod period;
  final DateTime generatedAt;
  final List<LabsFinding> findings;
  final int revision;
  final bool partial;
  final List<Map<String, dynamic>> events, experiments;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'engine': 'labs-1',
    'start': period.start.toIso8601String(),
    'end': period.end.toIso8601String(),
    'generatedAt': generatedAt.toIso8601String(),
    'revision': revision,
    'partial': partial,
    'findings': findings.map((f) => f.toJson()).toList(),
    'events': events,
    'experiments': experiments,
  };
  factory LabsSnapshot.fromJson(Map<String, dynamic> j) => LabsSnapshot(
    period: LabsPeriod(DateTime.parse(j['start']), DateTime.parse(j['end'])),
    generatedAt: DateTime.parse(j['generatedAt']),
    revision: j['revision'],
    partial: j['partial'] == true,
    findings: (j['findings'] as List)
        .map((f) => LabsFinding.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
    events: (j['events'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
    experiments: (j['experiments'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
  );
  String get fingerprint => jsonEncode({
    'findings': findings.map((f) => f.toJson()).toList(),
    'events': events,
    'experiments': experiments,
    'partial': partial,
  });
}
