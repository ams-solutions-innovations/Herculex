import 'dart:convert';

enum CoachingKind {
  reduceSets,
  goalGap,
  exerciseOrder,
  equipment,
  shorterWorkout,
  catchUp,
}

class CoachingObservation {
  CoachingObservation(this.data);
  final Map<String, dynamic> data;
  factory CoachingObservation.decode(String raw) =>
      CoachingObservation(jsonDecode(raw) as Map<String, dynamic>);
  String get session => data['session'] as String;
  String? get program => data['program'] as String?;
  String get day => data['day'] as String? ?? '';
  DateTime get at => DateTime.parse(data['at'] as String);
  List<Map<String, dynamic>> get original => (data['original'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> get actual => (data['actual'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  bool get reliable =>
      data['known'] == true &&
      data['corrected'] != true &&
      data['trial'] != true &&
      data['deload'] != true;
  String get policy => data['policy'] as String? ?? 'unknown';
  int get minutes => data['minutes'] as int? ?? 0;
  Map<String, dynamic>? actualFor(Map<String, dynamic> original) =>
      actual.where((a) => a['row'] == original['row']).firstOrNull;
  static String key(Map<String, dynamic> e) =>
      '${e['slot'] ?? '${e['exercise']}|${e['order']}'}|${e['variant']}|${e['method']}|${e['planned']}|${e['machine']}|${e['prescription']}';
}

class CoachingSignal {
  const CoachingSignal({
    required this.kind,
    required this.key,
    required this.title,
    required this.detail,
    required this.evidence,
    required this.source,
    this.exercise,
    this.targetSets,
    this.replacement,
    this.muscle,
    this.oneOff = false,
  });
  final CoachingKind kind;
  final String key, title, detail;
  final List<String> evidence;
  final CoachingObservation source;
  final Map<String, dynamic>? exercise, replacement;
  final int? targetSets;
  final String? muscle;
  final bool oneOff;
  Map<String, Object?> toJson() => {
    'version': 1,
    'kind': kind.name,
    'key': key,
    'title': title,
    'detail': detail,
    'evidence': evidence,
    'source': source.data,
    'exercise': exercise,
    'targetSets': targetSets,
    'replacement': replacement,
    'muscle': muscle,
    'oneOff': oneOff,
  };
  factory CoachingSignal.fromJson(Map<String, dynamic> j) => CoachingSignal(
    kind: CoachingKind.values.byName(j['kind'] as String),
    key: j['key'] as String,
    title: j['title'] as String,
    detail: j['detail'] as String,
    evidence: List<String>.from(j['evidence'] as List),
    source: CoachingObservation(Map<String, dynamic>.from(j['source'] as Map)),
    exercise: j['exercise'] == null
        ? null
        : Map<String, dynamic>.from(j['exercise'] as Map),
    replacement: j['replacement'] == null
        ? null
        : Map<String, dynamic>.from(j['replacement'] as Map),
    targetSets: j['targetSets'] as int?,
    muscle: j['muscle'] as String?,
    oneOff: j['oneOff'] == true,
  );
}

/// Counts behaviour, not inferred motivation. Clinical/physiological claims
/// are intentionally absent; reasons gate actions separately.
abstract final class TrainingCoachingEngine {
  static const lookback = Duration(days: 84);
  static const requiredOccurrences = 3;
  static const comparisonWindow = 4;

  static List<CoachingSignal> detect({
    required List<CoachingObservation> observations,
    required DateTime now,
    Set<String> priorityMuscles = const {},
  }) {
    final all =
        observations
            .where(
              (o) =>
                  o.reliable &&
                  !o.at.isAfter(now) &&
                  !o.at.isBefore(now.subtract(lookback)),
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    if (all.isEmpty) return [];
    final signals = <CoachingSignal>[];
    final groups = <String, List<CoachingObservation>>{};
    for (final o in all) {
      groups
          .putIfAbsent(
            '${o.program}|${o.day}|${o.data['gym']}|${o.data['phase']}',
            () => [],
          )
          .add(o);
    }
    for (final group in groups.values) {
      final recent = group.take(comparisonWindow).toList();
      final latest = recent.first;
      for (final e in latest.original) {
        final comparable = group
            .where(
              (o) => o.original.any(
                (p) => CoachingObservation.key(p) == CoachingObservation.key(e),
              ),
            )
            .take(comparisonWindow)
            .toList();
        if (comparable.length < comparisonWindow) continue;
        final reductions = comparable.where((o) {
          final p = o.original.firstWhere(
            (p) => CoachingObservation.key(p) == CoachingObservation.key(e),
          );
          final a = o.actualFor(p);
          return (a == null || a['exercise'] == p['exercise']) &&
              (a?['completed'] as int? ?? 0) < (p['planned'] as int? ?? 0);
        }).toList();
        if (reductions.length >= requiredOccurrences) {
          final counts = reductions.map((o) {
            final p = o.original.firstWhere(
              (p) => CoachingObservation.key(p) == CoachingObservation.key(e),
            );
            return o.actualFor(p)?['completed'] as int? ?? 0;
          }).toList()..sort();
          final count = counts[counts.length ~/ 2];
          final timeReasons = reductions
              .where((o) => o.policy == 'time')
              .length;
          final isLate =
              (e['order'] as int? ?? 0) >= latest.original.length ~/ 2;
          signals.add(
            CoachingSignal(
              kind: timeReasons >= requiredOccurrences && isLate
                  ? CoachingKind.exerciseOrder
                  : CoachingKind.reduceSets,
              key:
                  '${latest.program}|${latest.day}|${CoachingObservation.key(e)}|omission',
              title: timeReasons >= requiredOccurrences && isLate
                  ? 'Make room for ${e['name']}'
                  : 'Review ${e['name']} volume',
              detail:
                  '${reductions.length} of the last 4 comparable workouts included fewer than ${e['planned']} planned working sets. '
                  '${timeReasons >= requiredOccurrences ? 'You reported limited time.' : 'Fewer sets alone do not explain the cause.'}',
              evidence: comparable.map((o) => o.session).toList(),
              source: latest,
              exercise: e,
              targetSets: count > 0 ? count : 1,
            ),
          );
        }
        final declines = comparable.where((o) {
          final p = o.original.firstWhere(
            (p) => CoachingObservation.key(p) == CoachingObservation.key(e),
          );
          return o.actualFor(p)?['declined'] == true;
        }).length;
        if (declines >= requiredOccurrences &&
            reductions.length < requiredOccurrences &&
            (e['planned'] as int) > 1) {
          signals.add(
            CoachingSignal(
              kind: CoachingKind.reduceSets,
              key:
                  '${latest.program}|${latest.day}|${CoachingObservation.key(e)}|performance',
              title: 'Review workload for ${e['name']}',
              detail:
                  'Comparable performance declined in $declines of the last 4 exposures. '
                  'Review your recovery and test one small reduction; the recorded pattern does not establish its cause.',
              evidence: comparable.map((o) => o.session).toList(),
              source: latest,
              exercise: e,
              targetSets: (e['planned'] as int) - 1,
            ),
          );
        }
        final replacements =
            <String, List<(CoachingObservation, Map<String, dynamic>)>>{};
        for (final o in comparable.where((o) => o.policy == 'equipment')) {
          final p = o.original.firstWhere(
            (p) => CoachingObservation.key(p) == CoachingObservation.key(e),
          );
          final a = o.actualFor(p);
          if (a != null &&
              (a['exercise'] != p['exercise'] ||
                  a['variant'] != p['variant'])) {
            replacements
                .putIfAbsent('${a['exercise']}|${a['variant']}', () => [])
                .add((o, a));
          }
        }
        for (final r in replacements.values.where(
          (v) => v.length >= requiredOccurrences,
        )) {
          signals.add(
            CoachingSignal(
              kind: CoachingKind.equipment,
              key: '${latest.program}|${CoachingObservation.key(e)}|equipment',
              title: 'Use your available equipment',
              detail:
                  'You chose ${r.first.$2['name']} with this setup in ${r.length} of the last 4 comparable workouts.',
              evidence: comparable.map((o) => o.session).toList(),
              source: latest,
              exercise: e,
              replacement: r.first.$2,
            ),
          );
        }
      }
      if (recent.length == comparisonWindow) {
        final additions =
            <String, List<(CoachingObservation, Map<String, dynamic>)>>{};
        for (final o in recent) {
          final muscles = <String>{};
          for (final a in o.actual.where(
            (a) =>
                (a['completed'] as int? ?? 0) > 0 &&
                !o.original.any(
                  (p) => p['row'] == a['row'] || p['exercise'] == a['exercise'],
                ),
          )) {
            final muscle = a['muscle'] as String? ?? '';
            if (o.original.any((p) => p['muscle'] == muscle) ||
                !muscles.add(muscle))
              continue;
            additions.putIfAbsent(muscle, () => []).add((o, a));
          }
        }
        for (final entry in additions.entries.where(
          (e) => e.value.length >= requiredOccurrences,
        )) {
          final priority = priorityMuscles.contains(entry.key);
          signals.add(
            CoachingSignal(
              kind: CoachingKind.goalGap,
              key: '${latest.program}|${latest.day}|${entry.key}|addition',
              title: 'Make ${entry.key} part of your plan',
              detail:
                  'You added ${entry.key} work in ${entry.value.length} of the last 4 workouts.'
                  '${priority ? ' This matches a confirmed physique priority.' : ' Review whether this is a lasting preference.'}',
              evidence: recent.map((o) => o.session).toList(),
              source: latest,
              replacement: entry.value.first.$2,
              muscle: entry.key,
            ),
          );
        }
        final shortened = recent
            .where(
              (o) =>
                  o.policy == 'time' &&
                  o.actual.fold<int>(
                        0,
                        (n, e) => n + (e['completed'] as int? ?? 0),
                      ) <
                      o.original.fold<int>(
                        0,
                        (n, e) => n + (e['planned'] as int? ?? 0),
                      ),
            )
            .toList();
        if (shortened.length >= requiredOccurrences)
          signals.add(
            CoachingSignal(
              kind: CoachingKind.shorterWorkout,
              key: '${latest.program}|${latest.day}|time',
              title: 'Fit training into your available time',
              detail:
                  'You shortened ${shortened.length} of the last 4 workouts because of time. Keep the main lifts and trim optional work.',
              evidence: recent.map((o) => o.session).toList(),
              source: latest,
            ),
          );
      }
    }
    // One confirmed time constraint is enough for a one-time redistribution.
    final latest = all.first;
    if (latest.policy == 'time' &&
        now.difference(latest.at) <= const Duration(days: 2) &&
        latest.original.any(
          (p) =>
              (latest.actualFor(p)?['completed'] as int? ?? 0) <
              (p['planned'] as int? ?? 0),
        )) {
      signals.add(
        CoachingSignal(
          kind: CoachingKind.catchUp,
          key: '${latest.session}|catchup',
          title: 'Time for the work you left out?',
          detail:
              'You reported limited time. Review a small redistribution or an optional short workout; recovery and upcoming sessions must allow it.',
          evidence: [latest.session],
          source: latest,
          oneOff: true,
        ),
      );
    }
    return signals;
  }
}
