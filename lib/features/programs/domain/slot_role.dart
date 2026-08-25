/// The job a slot does inside a training day. Drives both the prescription
/// archetype (§6 of the Program Builder v3 design) and the rotation cadence
/// (§5) — a max-effort slot and a pump slot are not the same kind of thing and
/// must not be rotated or prescribed by the same rules.
enum SlotRole {
  /// The heavy lift the day is built around. Max-effort / competition lift.
  main('main', 'Main', 1),

  /// The second compound: builds the main lift, still heavy-ish.
  supplemental('supplemental', 'Supplemental', 2),

  /// Compound or machine work for volume.
  accessory('accessory', 'Accessory', 4),

  /// Single-joint work.
  isolation('isolation', 'Isolation', 8),

  /// Timed / distance work — carries, sled, cardio finishers.
  conditioning('conditioning', 'Conditioning', 16);

  const SlotRole(this.id, this.label, this.flag);

  final String id;
  final String label;

  /// Bit used in the [SlotRoleEligibility] mask.
  final int flag;

  static SlotRole fromId(String? id) =>
      values.firstWhere((r) => r.id == id, orElse: () => SlotRole.accessory);

  /// True when this role's work is heavy enough that the exercise choice is
  /// load-limited rather than fatigue-limited.
  bool get isHeavy => this == SlotRole.main || this == SlotRole.supplemental;
}

/// Which roles an exercise may legally fill.
///
/// This is deliberately separate from how much the user *likes* an exercise.
/// Affinity alone is not enough: a Leg Extension can be a favourite and must
/// still never be prescribed as "work up to a heavy single". Without this
/// gate the generator eventually produces nonsense.
///
/// The default mask is derived from catalog metadata and never asked for; the
/// user only ever sees and edits the override.
abstract final class SlotRoleEligibility {
  /// Every role — the permissive fallback for rows with no metadata.
  static const all = 1 | 2 | 4 | 8 | 16;

  static bool allows(int mask, SlotRole role) => mask & role.flag != 0;

  static int add(int mask, SlotRole role) => mask | role.flag;

  static int remove(int mask, SlotRole role) => mask & ~role.flag;

  static int of(Iterable<SlotRole> roles) =>
      roles.fold(0, (mask, r) => mask | r.flag);

  static List<SlotRole> toList(int mask) =>
      [for (final r in SlotRole.values) if (allows(mask, r)) r];

  /// Modalities where a true maximal single is both loadable and safe.
  static const _maxEffortModalities = {
    'barbell',
    'dumbbell',
    'smith',
    'machine_plate',
  };

  static const _timedMetrics = {'time', 'distance', 'time_distance'};

  /// Derives the default eligibility mask from `ExerciseCatalog` columns.
  ///
  /// - [mechanics]  `compound` | `isolation`
  /// - [modality]   `barbell` | `dumbbell` | `machine_selectorized` | …
  /// - [cnsScore]   1–10
  /// - [loggingMetric] `weight_reps` | `reps` | `time` | …
  static int derive({
    required String mechanics,
    required String modality,
    required int cnsScore,
    String loggingMetric = 'weight_reps',
    String category = 'strength',
  }) {
    final isCompound = mechanics == 'compound';
    final isTimed = _timedMetrics.contains(loggingMetric);

    var mask = 0;

    if (isTimed || category == 'cardio') {
      mask = add(mask, SlotRole.conditioning);
      // A loaded carry is still accessory work; a treadmill is not.
      if (isCompound && !isTimed) mask = add(mask, SlotRole.accessory);
      return mask;
    }

    // Everything liftable can at least be accessory work.
    mask = add(mask, SlotRole.accessory);

    if (isCompound) {
      mask = add(mask, SlotRole.supplemental);
      if (cnsScore >= 5 && _maxEffortModalities.contains(modality)) {
        mask = add(mask, SlotRole.main);
      }
    } else {
      mask = add(mask, SlotRole.isolation);
    }

    return mask;
  }
}
