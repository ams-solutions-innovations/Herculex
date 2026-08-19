import '../../../core/units.dart';
import '../../../data/local/database.dart';
import 'logging_metric.dart';

/// Parsing and rendering for the units a set can be measured in (EXR-05).
///
/// [LoggingMetric] says *which* fields a movement uses; this says what those
/// fields look like on screen and what a typed string means. Both the logger
/// and every history surface go through here, so a Plank reads `2:00` in the
/// set row, in the last-time hint and in the session log without three
/// separate formatters drifting apart — which is exactly how the metric
/// vocabulary itself drifted before 12-03.
class SetMetricFormat {
  const SetMetricFormat._();

  /// `45s`, `1:30`, `12:05`, `1:02:30`.
  ///
  /// Under a minute uses the bare-seconds form because that is how a hold is
  /// spoken ("a 45 second plank"); at or above a minute it switches to clock
  /// notation, which is how an interval is spoken.
  static String formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h == 0) return '$m:$ss';
    return '$h:${m.toString().padLeft(2, '0')}:$ss';
  }

  /// Accepts what [formatDuration] emits plus the way people actually type.
  ///
  /// `90` and `90s` are ninety seconds; `1:30` is also ninety seconds;
  /// `1:02:30` is an hour and change. Anything unparseable is null rather than
  /// zero — a set with no duration typed is not a zero-second set.
  static int? parseDuration(String raw) {
    final text = raw.trim().toLowerCase().replaceAll('s', '');
    if (text.isEmpty) return null;
    if (!text.contains(':')) {
      final bare = int.tryParse(text);
      return bare == null || bare < 0 ? null : bare;
    }
    final parts = text.split(':');
    if (parts.length > 3) return null;
    var total = 0;
    for (final part in parts) {
      final v = int.tryParse(part.isEmpty ? '0' : part);
      if (v == null || v < 0) return null;
      total = total * 60 + v;
    }
    return total;
  }

  /// The value the duration field shows for a stored set. Clock notation is
  /// re-typed exactly as it was rendered, so editing is lossless.
  static String durationFieldText(int? seconds) =>
      seconds == null || seconds == 0 ? '' : formatDuration(seconds);

  static String formatCalories(int kcal) => '$kcal kcal';

  /// Column header for one input, in the user's units.
  static String fieldLabel(
    SetField field, {
    required WeightFormat weight,
    required DistanceFormat distance,
  }) =>
      switch (field) {
        SetField.weight => weight.suffix.toUpperCase(),
        SetField.reps => 'REPS',
        SetField.duration => 'TIME',
        SetField.distance => distance.suffix.toUpperCase(),
        SetField.calories => 'KCAL',
      };

  /// One-line rendering of a logged set, in its own units.
  ///
  /// `60 kg × 8`, `2:00`, `40 kg · 20 m`, `250 kcal`. Only the fields the
  /// metric declares are read, so a `weight_reps` set produces the exact
  /// string the app rendered before this existed and history does not shift
  /// under existing users.
  static String summariseSet(
    SetEntryData set, {
    required LoggingMetric metric,
    required WeightFormat weight,
    required DistanceFormat distance,
  }) {
    // Weight × reps is the overwhelmingly common case and reads as a product,
    // not as a list of two measurements — keep its own separator.
    if (metric == LoggingMetric.weightReps) {
      return '${weight.format(set.weightKg)} × ${set.reps}';
    }
    final parts = <String>[];
    for (final field in metric.fields) {
      switch (field) {
        case SetField.weight:
          parts.add(weight.format(set.weightKg));
        case SetField.reps:
          parts.add('${set.reps} reps');
        case SetField.duration:
          if (set.durationSeconds != null) {
            parts.add(formatDuration(set.durationSeconds!));
          }
        case SetField.distance:
          if (set.distanceM != null) parts.add(distance.format(set.distanceM!));
        case SetField.calories:
          if (set.calories != null) parts.add(formatCalories(set.calories!));
      }
    }
    return parts.join(' · ');
  }
}
