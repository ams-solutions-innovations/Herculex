/// Which equipment a given exercise can plausibly be performed with, and how
/// those modality ids are labelled.
///
/// Lives in the domain layer because both the phone's equipment prompt
/// (`EquipmentVariantSheet`) and the Wear OS catalog push need the same
/// answer — the watch previously offered a hardcoded ten-item list on every
/// exercise, which is why a Seated Leg Curl could be logged "on a barbell".
library;

import 'dart:convert';

import '../../../data/local/database.dart';

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
  if (exercise.loggingMetric != 'weight_reps' &&
      exercise.loggingMetric != 'reps') {
    return [base]; // time/distance work: no equipment swap.
  }
  // The movement layer knows which equipment this movement is actually
  // performed with, derived from the catalog rows that share it. Guessing a
  // generic free-weight family instead is what offered a Smith Machine
  // option on a selectorized hamstring curl.
  final allowed = decodeAllowedEquipment(exercise.allowedEquipment);
  if (allowed.isNotEmpty) {
    return [base, ...allowed.where((m) => m != base)];
  }
  if (base == 'bodyweight') {
    // Bodyweight movements can be loaded via band assistance or stay pure;
    // added weight is handled by the weighted-bodyweight field, not a
    // variant switch.
    return ['bodyweight', 'band'];
  }
  // No movement: the catalog row already encodes its equipment.
  return [base];
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
