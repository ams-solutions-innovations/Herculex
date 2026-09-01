/// Registry of advanced set types (V2 §15). Stored in `set_entries.set_type`
/// as the [id] string so new types can ship without a schema migration.
///
/// [volumeFactor] scales tonnage for types whose effective work per logged rep
/// differs from a standard rep (partials, negatives, …). [cnsFactor] feeds the
/// CNS engine for grinding/overloading techniques.
enum SetType {
  standard('standard', 'Standard'),
  drop('drop', 'Drop Set', metaKeys: ['dropPercent', 'drops']),
  restPause(
    'rest_pause',
    'Rest-Pause',
    metaKeys: ['restSeconds', 'miniSets'],
    cnsFactor: 1.2,
  ),
  partials('partials', 'Partials', volumeFactor: 0.5),
  myoReps('myo_reps', 'Myo Reps', metaKeys: ['activationReps', 'miniSets']),
  pyramid('pyramid', 'Pyramid Set'),
  forced(
    'forced',
    'Forced Reps',
    metaKeys: ['forcedReps', 'extraReps'],
    cnsFactor: 1.3,
  ),
  cheat(
    'cheat',
    'Cheat Reps',
    metaKeys: ['cheatReps', 'extraReps'],
    volumeFactor: 0.85,
    cnsFactor: 1.25,
  ),
  negatives('negatives', 'Negatives', volumeFactor: 0.75, cnsFactor: 1.3),
  pause('pause', 'Pause Reps', metaKeys: ['pauseSeconds'], cnsFactor: 1.1),
  mechanicalDrop('mechanical_drop', 'Mechanical Drop Set'),
  giant('giant', 'Giant Set'),
  preExhaustion('pre_exhaustion', 'Pre-Exhaustion'),
  twentyOnes('twenty_ones', '21s'),
  volume20x60('volume_20x60', '20 Sets @ 60%', metaKeys: ['percent']),
  downSets('down_sets', 'Down Sets', metaKeys: ['startReps', 'decrement']),
  // CrossFit structures (V2 §13) — logged per round/minute.
  amrap('amrap', 'AMRAP', metaKeys: ['capSeconds', 'rounds']),
  emom('emom', 'EMOM', metaKeys: ['minutes', 'repsPerMinute']),
  forTime('for_time', 'For Time', metaKeys: ['elapsedSeconds']);

  const SetType(
    this.id,
    this.label, {
    this.metaKeys = const [],
    this.volumeFactor = 1.0,
    this.cnsFactor = 1.0,
  });

  /// Stable string persisted to the database.
  final String id;
  final String label;

  /// Keys this type expects inside `set_entries.set_type_meta_json`.
  final List<String> metaKeys;

  /// Tonnage multiplier per logged rep relative to a standard rep.
  final double volumeFactor;

  /// CNS load multiplier relative to a standard set.
  final double cnsFactor;

  static SetType fromId(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => SetType.standard);
}

/// Standard pause durations offered by the pause-rep picker (V2 §15).
const pauseRepSecondsOptions = [2, 3, 5];
