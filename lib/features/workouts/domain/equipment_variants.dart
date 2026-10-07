/// Which equipment a given exercise can plausibly be performed with, and how
/// those modality ids are labelled.
///
/// Lives in the domain layer because both the phone's equipment prompt
/// (`EquipmentVariantSheet`) and the Wear OS catalog push need the same
/// answer — the watch previously offered a hardcoded ten-item list on every
/// exercise, which is why a Seated Leg Curl could be logged "on a barbell".
library;

import 'dart:convert';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';

const _labels = <String, String>{
  'barbell': 'Barbell',
  'dumbbell': 'Dumbbell',
  'smith': 'Smith Machine',
  'cable': 'Cable',
  'machine_plate': 'Machine (Plate-Loaded)',
  'machine_selectorized': 'Machine (Selectorized)',
  'kettlebell': 'Kettlebell',
  'band': 'Band',
  'bodyweight': 'Bodyweight',
  'weighted': 'Weighted',
  'other': 'Other',
};

/// Display label for a modality id; unknown ids pass through unchanged.
String equipmentVariantLabel(String variant) => _labels[variant] ?? variant;

/// True when [variant] is a modality id this app knows about.
bool isKnownEquipmentVariant(String variant) => _labels.containsKey(variant);

/// Plausible equipment options for [exercise], catalog default first.
///
/// A single-element result means no choice is worth prompting for — a Seated
/// Leg Curl exists on exactly one machine.
List<String> equipmentVariantsFor(ExerciseCatalogData exercise) {
  final base = exercise.modality;
  // The movement layer knows which equipment this movement is actually
  // performed with, derived from the catalog rows that share it. Guessing a
  // generic free-weight family instead is what offered a Smith Machine
  // option on a selectorized hamstring curl.
  //
  // This is checked before the metric, because an authored list is a fact
  // about the movement regardless of how it is scored: a Farmer's Walk is
  // genuinely carried on either handles or dumbbells, and the previous
  // metric-first guard suppressed that swap purely because carries are not
  // measured in reps.
  final allowed = decodeAllowedEquipment(exercise.allowedEquipment);
  if (allowed.isNotEmpty) {
    final list = [base, ...allowed.where((m) => m != base)];
    if (exercise.supportsWeightedBodyweight &&
        (list.contains('bodyweight') || base == 'bodyweight') &&
        !list.contains('weighted')) {
      final bwIdx = list.indexOf('bodyweight');
      if (bwIdx != -1) {
        list.insert(bwIdx + 1, 'weighted');
      } else {
        list.add('weighted');
      }
    }
    if ((list.contains('bodyweight') || base == 'bodyweight') &&
        LoggingMetric.fromId(exercise.loggingMetric).isRepBased &&
        !list.contains('band')) {
      list.add('band');
    }
    return list;
  }
  if (base == 'bodyweight' &&
      LoggingMetric.fromId(exercise.loggingMetric).isRepBased) {
    // Bodyweight movements that support added weight offer pure bodyweight,
    // weighted (+ load) and band assistance. Timed holds are excluded —
    // there is no such thing as a band-assisted plank, and the movement layer
    // has no list to correct it.
    if (exercise.supportsWeightedBodyweight) {
      return ['bodyweight', 'weighted', 'band'];
    }
    return ['bodyweight', 'band'];
  }
  // No movement: the catalog row already encodes its equipment.
  return [base];
}

/// Resolves the effective [LoggingMetric] for an exercise when performed with
/// a specific [equipmentVariant].
///
/// For bodyweight/calisthenics exercises (e.g. Dips, Pull-Ups, Ring Dips),
/// performing as pure `bodyweight` or `band` logs reps only, while performing
/// as `weighted` enables the external load field (Weight × Reps).
LoggingMetric effectiveLoggingMetric({
  required ExerciseCatalogData exercise,
  String? equipmentVariant,
}) {
  final variant = equipmentVariant ?? exercise.modality;
  if (variant == 'weighted') {
    return LoggingMetric.weightReps;
  }
  if (variant == 'bodyweight' || variant == 'band') {
    final base = LoggingMetric.fromId(exercise.loggingMetric);
    if (base == LoggingMetric.weightReps) {
      return LoggingMetric.reps;
    }
    return base;
  }
  return LoggingMetric.fromId(exercise.loggingMetric);
}

/// Parses the `allowedEquipment` JSON blob, dropping anything that isn't a
/// modality id this app renders.
List<String> decodeAllowedEquipment(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final value in decoded)
        if (value is String && _labels.containsKey(value)) value,
    ];
  } catch (_) {
    return const [];
  }
}
