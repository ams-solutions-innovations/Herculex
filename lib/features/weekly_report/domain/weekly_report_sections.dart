/// Section value classes of the weekly report payload (D-01, RPT-01).
///
/// Each class is an immutable bundle of aggregates and short strings for one
/// card of the report. They are what gets frozen into
/// `weekly_reports.payload_json`, so they hold no raw health samples, no ids
/// and no free text. Parsing is strict: a wrong-typed or missing required field
/// throws [FormatException] because the JSON may have been pulled from the
/// cloud and is untrusted. There are deliberately no `!` casts on decoded data.
///
/// Pure Dart: no Flutter, drift or wall-clock reads.
library;

/// Strict JSON readers shared by the section classes and the payload.
///
/// Numeric readers accept any [num] (JSON `3` for a double field is normal) and
/// reject non-finite values. Optional readers treat an absent key and an
/// explicit `null` the same, but a present value of the wrong type still
/// throws.
abstract final class ReportJson {
  static Map<String, dynamic> map(Object? value, String what) {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw FormatException('Weekly report $what has a non-string key.');
        }
        out[key] = entry.value;
      }
      return out;
    }
    throw FormatException('Weekly report $what is not an object.');
  }

  static List<Object?> list(Object? value, String what) {
    if (value is List) return value;
    throw FormatException('Weekly report $what is not a list.');
  }

  static int requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num && value.isFinite) return value.toInt();
    throw FormatException('Weekly report is missing integer "$key".');
  }

  static int? optionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num && value.isFinite) return value.toInt();
    throw FormatException('Weekly report field "$key" is not an integer.');
  }

  static double requiredDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Weekly report is missing number "$key".');
  }

  static double? optionalDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Weekly report field "$key" is not a number.');
  }

  static bool requiredBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    throw FormatException('Weekly report is missing boolean "$key".');
  }

  static String requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Weekly report is missing string "$key".');
  }

  static String? optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('Weekly report field "$key" is not a string.');
  }

  static List<String> stringList(Map<String, dynamic> json, String key) {
    final raw = list(json[key], '"$key"');
    return [
      for (final item in raw)
        if (item is String)
          item
        else
          throw FormatException('Weekly report "$key" holds a non-string.'),
    ];
  }

  static List<T> objectList<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = list(json[key], '"$key"');
    return [for (final item in raw) parse(map(item, '"$key" element'))];
  }
}

/// One of the most-logged foods of the week.
class TopFood {
  const TopFood({required this.name, required this.count});

  /// Catalogue names are stored truncated to this many characters.
  static const int maxNameLength = 60;

  /// Builds a [TopFood] with [name] collapsed to [maxNameLength] characters.
  factory TopFood.truncated({required String name, required int count}) =>
      TopFood(name: _truncate(name, maxNameLength), count: count);

  factory TopFood.fromJson(Map<String, dynamic> json) => TopFood.truncated(
    name: ReportJson.requiredString(json, 'name'),
    count: ReportJson.requiredInt(json, 'count'),
  );

  final String name;
  final int count;

  Map<String, dynamic> toJson() => {'name': name, 'count': count};
}

/// Nutrition card: logged-day averages against the targets of the week.
class NutritionSection {
  const NutritionSection({
    required this.daysLogged,
    required this.avgKcal,
    required this.avgProteinG,
    required this.topFoods,
    this.targetKcal,
    this.targetProteinG,
    this.adherenceDays,
  });

  factory NutritionSection.fromJson(Map<String, dynamic> json) =>
      NutritionSection(
        daysLogged: ReportJson.requiredInt(json, 'daysLogged'),
        avgKcal: ReportJson.requiredInt(json, 'avgKcal'),
        avgProteinG: ReportJson.requiredInt(json, 'avgProteinG'),
        targetKcal: ReportJson.optionalInt(json, 'targetKcal'),
        targetProteinG: ReportJson.optionalInt(json, 'targetProteinG'),
        adherenceDays: ReportJson.optionalInt(json, 'adherenceDays'),
        topFoods: ReportJson.objectList(json, 'topFoods', TopFood.fromJson),
      );

  final int daysLogged;
  final int avgKcal;
  final int avgProteinG;
  final int? targetKcal;
  final int? targetProteinG;

  /// Days within the adherence band; null when there is no target.
  final int? adherenceDays;

  /// At most three, by entry count.
  final List<TopFood> topFoods;

  Map<String, dynamic> toJson() => {
    'daysLogged': daysLogged,
    'avgKcal': avgKcal,
    'avgProteinG': avgProteinG,
    'targetKcal': targetKcal,
    'targetProteinG': targetProteinG,
    'adherenceDays': adherenceDays,
    'topFoods': [for (final f in topFoods) f.toJson()],
  };
}

/// An exercise whose estimated 1RM moved this week.
class E1rmMover {
  const E1rmMover({
    required this.exerciseName,
    required this.e1rmKg,
    required this.deltaKg,
  });

  factory E1rmMover.fromJson(Map<String, dynamic> json) => E1rmMover(
    exerciseName: ReportJson.requiredString(json, 'exerciseName'),
    e1rmKg: ReportJson.requiredDouble(json, 'e1rmKg'),
    deltaKg: ReportJson.requiredDouble(json, 'deltaKg'),
  );

  final String exerciseName;
  final double e1rmKg;
  final double deltaKg;

  Map<String, dynamic> toJson() => {
    'exerciseName': exerciseName,
    'e1rmKg': e1rmKg,
    'deltaKg': deltaKg,
  };
}

/// Training card: sessions, volume and strength movers.
class TrainingSection {
  const TrainingSection({
    required this.sessions,
    required this.tonnageKg,
    required this.e1rmMovers,
    this.prevWeekTonnageKg,
  });

  factory TrainingSection.fromJson(Map<String, dynamic> json) =>
      TrainingSection(
        sessions: ReportJson.requiredInt(json, 'sessions'),
        tonnageKg: ReportJson.requiredDouble(json, 'tonnageKg'),
        prevWeekTonnageKg: ReportJson.optionalDouble(json, 'prevWeekTonnageKg'),
        e1rmMovers: ReportJson.objectList(
          json,
          'e1rmMovers',
          E1rmMover.fromJson,
        ),
      );

  final int sessions;
  final double tonnageKg;
  final double? prevWeekTonnageKg;

  /// At most three.
  final List<E1rmMover> e1rmMovers;

  Map<String, dynamic> toJson() => {
    'sessions': sessions,
    'tonnageKg': tonnageKg,
    'prevWeekTonnageKg': prevWeekTonnageKg,
    'e1rmMovers': [for (final m in e1rmMovers) m.toJson()],
  };
}

/// A pre-templated correlation sentence (RPT-05, D-12).
///
/// The statement is produced by a fixed template ("tended to go with"), never
/// by the model, so the relationship reaches the narrative as a fact.
class CorrelationLine {
  const CorrelationLine({
    required this.kind,
    required this.statement,
    required this.sampleSize,
  });

  factory CorrelationLine.fromJson(Map<String, dynamic> json) =>
      CorrelationLine(
        kind: ReportJson.requiredString(json, 'kind'),
        statement: ReportJson.requiredString(json, 'statement'),
        sampleSize: ReportJson.requiredInt(json, 'sampleSize'),
      );

  /// `sleep_rpe` or `hr_tonnage`.
  final String kind;
  final String statement;
  final int sampleSize;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'statement': statement,
    'sampleSize': sampleSize,
  };
}

/// Recovery, sleep and activity card.
class RecoverySection {
  const RecoverySection({
    required this.cnsDeloadSuggested,
    required this.recoveryWarnings,
    required this.correlations,
    this.avgSleepHours,
    this.avgSteps,
    this.avgRestingHr,
    this.cnsReadinessPct,
  });

  factory RecoverySection.fromJson(Map<String, dynamic> json) =>
      RecoverySection(
        avgSleepHours: ReportJson.optionalDouble(json, 'avgSleepHours'),
        avgSteps: ReportJson.optionalInt(json, 'avgSteps'),
        avgRestingHr: ReportJson.optionalDouble(json, 'avgRestingHr'),
        cnsReadinessPct: ReportJson.optionalInt(json, 'cnsReadinessPct'),
        cnsDeloadSuggested: ReportJson.requiredBool(json, 'cnsDeloadSuggested'),
        recoveryWarnings: ReportJson.stringList(json, 'recoveryWarnings'),
        correlations: ReportJson.objectList(
          json,
          'correlations',
          CorrelationLine.fromJson,
        ),
      );

  final double? avgSleepHours;
  final int? avgSteps;
  final double? avgRestingHr;
  final int? cnsReadinessPct;
  final bool cnsDeloadSuggested;
  final List<String> recoveryWarnings;
  final List<CorrelationLine> correlations;

  Map<String, dynamic> toJson() => {
    'avgSleepHours': avgSleepHours,
    'avgSteps': avgSteps,
    'avgRestingHr': avgRestingHr,
    'cnsReadinessPct': cnsReadinessPct,
    'cnsDeloadSuggested': cnsDeloadSuggested,
    'recoveryWarnings': recoveryWarnings,
    'correlations': [for (final c in correlations) c.toJson()],
  };
}

/// Physique card: the newest check-in verdict and bodyweight movement.
class PhysiqueSection {
  const PhysiqueSection({
    this.checkInVerdict,
    this.checkInConfidence,
    this.checkInDateIso,
    this.bodyweightKg,
    this.bodyweightDeltaKg,
  });

  factory PhysiqueSection.fromJson(Map<String, dynamic> json) =>
      PhysiqueSection(
        checkInVerdict: ReportJson.optionalString(json, 'checkInVerdict'),
        checkInConfidence: ReportJson.optionalString(json, 'checkInConfidence'),
        checkInDateIso: ReportJson.optionalString(json, 'checkInDateIso'),
        bodyweightKg: ReportJson.optionalDouble(json, 'bodyweightKg'),
        bodyweightDeltaKg: ReportJson.optionalDouble(json, 'bodyweightDeltaKg'),
      );

  /// Wire value: `on_track`, `off_track` or `inconclusive`.
  final String? checkInVerdict;
  final String? checkInConfidence;
  final String? checkInDateIso;
  final double? bodyweightKg;
  final double? bodyweightDeltaKg;

  Map<String, dynamic> toJson() => {
    'checkInVerdict': checkInVerdict,
    'checkInConfidence': checkInConfidence,
    'checkInDateIso': checkInDateIso,
    'bodyweightKg': bodyweightKg,
    'bodyweightDeltaKg': bodyweightDeltaKg,
  };
}

/// TDEE drift card. Derived from `tdee_estimates` history, not from data
/// logged in the week; the actionable card shows only when [material] (D-11).
class TdeeSection {
  const TdeeSection({
    required this.oldKcal,
    required this.newKcal,
    required this.deltaKcal,
    required this.material,
    required this.confidence,
  });

  factory TdeeSection.fromJson(Map<String, dynamic> json) => TdeeSection(
    oldKcal: ReportJson.requiredInt(json, 'oldKcal'),
    newKcal: ReportJson.requiredInt(json, 'newKcal'),
    deltaKcal: ReportJson.requiredInt(json, 'deltaKcal'),
    material: ReportJson.requiredBool(json, 'material'),
    confidence: ReportJson.requiredString(json, 'confidence'),
  );

  final int oldKcal;
  final int newKcal;
  final int deltaKcal;
  final bool material;
  final String confidence;

  Map<String, dynamic> toJson() => {
    'oldKcal': oldKcal,
    'newKcal': newKcal,
    'deltaKcal': deltaKcal,
    'material': material,
    'confidence': confidence,
  };
}

String _truncate(String s, int max) {
  if (s.length <= max) return s;
  return s.substring(0, max);
}
