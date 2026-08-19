/// What a set of a given exercise is actually measured in.
///
/// Stored in `exercise_catalog.logging_metric` as the [id] string, sourced from
/// `assets/data/exercises.json`. Before this registry existed the vocabulary was
/// three loose comments — a table comment, a const list in the custom-exercise
/// builder and a Python derivation — which drifted: `weight_distance` shipped on
/// Sled Push without ever being declared, `distance` was declared and unused,
/// and every carry was `weight_time` despite being scored over a set distance.
///
/// The set of [fields] is what makes this more than a label. The logger reads it
/// to decide which inputs to render, so a Plank asks for a duration and a Sled
/// Push asks for weight and metres, instead of both asking for weight × reps.
///
/// Rounds-based work (AMRAP, EMOM, For Time) is deliberately *not* here: those
/// are [SetType]s, scored per round in `set_entries.set_type_meta_json`, so they
/// compose with whatever metric the underlying movement uses.
library;

/// One input the logger can render for a set.
enum SetField {
  /// External load in kg. Added load only on weighted-bodyweight movements.
  weight,

  /// Repetitions, or steps on a walking movement.
  reps,

  /// Work duration in seconds — a hold, a carry, a cardio interval.
  duration,

  /// Distance covered in metres.
  distance,

  /// Calories, as reported by an erg or bike console.
  calories,
}

enum LoggingMetric {
  weightReps('weight_reps', 'Weight × Reps', [SetField.weight, SetField.reps]),
  reps('reps', 'Reps', [SetField.reps]),
  repsTime('reps_time', 'Reps & Time', [SetField.reps, SetField.duration]),
  time('time', 'Time', [SetField.duration]),
  distance('distance', 'Distance', [SetField.distance]),
  timeDistance(
    'time_distance',
    'Time & Distance',
    [SetField.duration, SetField.distance],
  ),
  weightTime('weight_time', 'Weight & Time', [
    SetField.weight,
    SetField.duration,
  ]),
  weightDistance('weight_distance', 'Weight & Distance', [
    SetField.weight,
    SetField.distance,
  ]),
  calories('calories', 'Calories', [SetField.calories]),
  timeCalories(
    'time_calories',
    'Time & Calories',
    [SetField.duration, SetField.calories],
  );

  const LoggingMetric(this.id, this.label, this.fields);

  /// Stable string persisted to the database and shipped in the catalog asset.
  final String id;

  /// Human label for the custom-exercise builder.
  final String label;

  /// Inputs the logger renders, in display order.
  final List<SetField> fields;

  bool has(SetField field) => fields.contains(field);

  /// True when reps are the unit of work, so rep-based progression, rep PRs and
  /// tonnage all apply. False for cardio and carries, where multiplying load by
  /// a rep count that was never entered would inflate volume.
  bool get isRepBased => has(SetField.reps);

  /// True when the set carries an external load that belongs in tonnage.
  bool get isLoaded => has(SetField.weight);

  /// Unknown ids fall back to the catalog default rather than throwing —
  /// a custom row written by an older build must still open.
  static LoggingMetric fromId(String? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => LoggingMetric.weightReps);

  /// Every id the catalog is allowed to contain. Used by the catalog
  /// validation test to keep the asset and this registry in step.
  static Set<String> get ids => {for (final m in values) m.id};
}
