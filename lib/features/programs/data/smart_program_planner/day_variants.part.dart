part of '../smart_program_planner.dart';

/// `Upper B` → 1, `Full Body C` → 2. A label without a suffix is variant 0, so
/// a lone `Full Body` day keeps the first template.
int _dayVariant(String label) =>
    switch (label.trim().toLowerCase().split(' ').last) {
      'b' => 1,
      'c' => 2,
      _ => 0,
    };

/// The slots of one strength day. Repeated days use complementary templates,
/// not one template twice: each variant leads with a different movement while
/// the week still covers push, pull, knee and hinge (Blueprint SPLIT-DAYS-01 to
/// 04 and the `gpp` module's "complementary full-body sessions").
List<_SlotNeed> _strengthNeedsFor(String label) {
  final value = label.toLowerCase();
  final variant = _dayVariant(label);
  if (value.contains('push') || value.contains('chest')) {
    return variant == 0
        ? const [
            _SlotNeed('horizontal_push', null, SlotRole.main),
            _SlotNeed('vertical_push', null, SlotRole.supplemental),
            _SlotNeed('horizontal_push', null, SlotRole.accessory),
            _SlotNeed(null, 'tricep', SlotRole.isolation),
            _SlotNeed(null, 'shoulder', SlotRole.isolation),
          ]
        : const [
            _SlotNeed('vertical_push', null, SlotRole.main),
            _SlotNeed('horizontal_push', null, SlotRole.supplemental),
            _SlotNeed('horizontal_push', null, SlotRole.accessory),
            _SlotNeed(null, 'shoulder', SlotRole.isolation),
            _SlotNeed(null, 'tricep', SlotRole.isolation),
          ];
  }
  if (value.contains('pull') || value.contains('back')) {
    return variant == 0
        ? const [
            _SlotNeed('horizontal_pull', null, SlotRole.main),
            _SlotNeed('vertical_pull', null, SlotRole.supplemental),
            _SlotNeed('horizontal_pull', null, SlotRole.accessory),
            _SlotNeed(null, 'bicep', SlotRole.isolation),
            _SlotNeed(null, 'rear', SlotRole.isolation),
          ]
        : const [
            _SlotNeed('vertical_pull', null, SlotRole.main),
            _SlotNeed('horizontal_pull', null, SlotRole.supplemental),
            _SlotNeed('vertical_pull', null, SlotRole.accessory),
            _SlotNeed(null, 'rear', SlotRole.isolation),
            _SlotNeed(null, 'bicep', SlotRole.isolation),
          ];
  }
  if (value.contains('leg') || value.contains('lower')) {
    return variant == 0
        ? const [
            _SlotNeed('squat', null, SlotRole.main),
            _SlotNeed('hinge', null, SlotRole.supplemental),
            _SlotNeed('lunge', null, SlotRole.accessory),
            _SlotNeed(null, 'quad', SlotRole.isolation),
            _SlotNeed(null, 'hamstring', SlotRole.isolation),
            _SlotNeed(null, 'cal', SlotRole.isolation),
          ]
        : const [
            _SlotNeed('hinge', null, SlotRole.main),
            _SlotNeed('squat', null, SlotRole.supplemental),
            _SlotNeed('lunge', null, SlotRole.accessory),
            _SlotNeed(null, 'hamstring', SlotRole.isolation),
            _SlotNeed(null, 'quad', SlotRole.isolation),
            _SlotNeed(null, 'cal', SlotRole.isolation),
          ];
  }
  if (value.contains('upper')) {
    return variant == 0
        ? const [
            _SlotNeed('horizontal_push', null, SlotRole.main),
            _SlotNeed('horizontal_pull', null, SlotRole.supplemental),
            _SlotNeed('vertical_push', null, SlotRole.accessory),
            _SlotNeed('vertical_pull', null, SlotRole.accessory),
            _SlotNeed(null, 'bicep', SlotRole.isolation),
            _SlotNeed(null, 'tricep', SlotRole.isolation),
          ]
        : const [
            _SlotNeed('vertical_push', null, SlotRole.main),
            _SlotNeed('vertical_pull', null, SlotRole.supplemental),
            _SlotNeed('horizontal_push', null, SlotRole.accessory),
            _SlotNeed('horizontal_pull', null, SlotRole.accessory),
            _SlotNeed(null, 'tricep', SlotRole.isolation),
            _SlotNeed(null, 'bicep', SlotRole.isolation),
          ];
  }
  if (value.contains('arm')) {
    return const [
      _SlotNeed(null, 'bicep', SlotRole.accessory),
      _SlotNeed(null, 'tricep', SlotRole.accessory),
      _SlotNeed(null, 'shoulder', SlotRole.isolation),
    ];
  }
  if (value.contains('shoulder')) {
    return const [
      _SlotNeed('vertical_push', null, SlotRole.main),
      _SlotNeed(null, 'shoulder', SlotRole.isolation),
      _SlotNeed(null, 'rear', SlotRole.isolation),
    ];
  }
  return switch (variant) {
    1 => const [
      _SlotNeed('hinge', null, SlotRole.main),
      _SlotNeed('vertical_push', null, SlotRole.supplemental),
      _SlotNeed('vertical_pull', null, SlotRole.accessory),
      _SlotNeed('lunge', null, SlotRole.accessory),
      _SlotNeed(null, 'bicep', SlotRole.isolation),
    ],
    2 => const [
      _SlotNeed('horizontal_push', null, SlotRole.main),
      _SlotNeed('vertical_pull', null, SlotRole.supplemental),
      _SlotNeed('squat', null, SlotRole.accessory),
      _SlotNeed(null, 'hamstring', SlotRole.isolation),
      _SlotNeed(null, 'tricep', SlotRole.isolation),
    ],
    _ => const [
      _SlotNeed('squat', null, SlotRole.main),
      _SlotNeed('horizontal_push', null, SlotRole.supplemental),
      _SlotNeed('horizontal_pull', null, SlotRole.accessory),
      _SlotNeed('hinge', null, SlotRole.accessory),
      _SlotNeed(null, 'shoulder', SlotRole.isolation),
    ],
  };
}

/// Remembers what each differently named day already uses, so B avoids A.
///
/// Exclusions come only from labels first seen earlier. A day that occurs twice
/// (A-B-A) therefore sees the same exclusions both times and resolves to the
/// same exercises, even though its second occurrence has another stress role.
class _DayExerciseMemory {
  final _labels = <String>[];
  final _used = <String, Set<int>>{};

  Set<int> exclusionsFor(String label) {
    if (!_labels.contains(label)) _labels.add(label);
    return {
      for (final earlier in _labels.take(_labels.indexOf(label)))
        ...?_used[earlier],
    };
  }

  void record(String label, Iterable<int> exerciseIds) =>
      (_used[label] ??= {}).addAll(exerciseIds);
}

/// Rear-delt flies are catalogued under `horizontal_pull`, which makes them
/// "compound" by pattern. They are single-joint work in every way that matters
/// to a slot, and the only exercises a `rear` slot can use.
bool _isRearDeltFly(ExerciseCatalogData exercise) {
  final name = exercise.name.toLowerCase();
  return exercise.cnsScore <= 3 &&
      (name.contains('rear') ||
          name.contains('reverse pec') ||
          name.contains('face pull'));
}

/// Whether [exercise] fits the slot's movement, before role eligibility.
bool _matchesNeed(ExerciseCatalogData exercise, _SlotNeed need) {
  if (need.pattern != null && exercise.movementPattern != need.pattern) {
    return false;
  }
  // A row slot means a row, not a rear-delt fly that shares its pattern.
  if (need.pattern == 'horizontal_pull' &&
      need.muscle == null &&
      _isRearDeltFly(exercise)) {
    return false;
  }
  if (need.muscle == 'rear' && _isRearDeltFly(exercise)) return true;
  return need.muscle == null ||
      exercise.primaryMuscle.toLowerCase().contains(need.muscle!);
}

int _roleMaskOf(ExerciseCatalogData exercise) {
  final mask = SlotRoleEligibility.derive(
    mechanics: exercise.mechanics,
    modality: exercise.modality,
    cnsScore: exercise.cnsScore,
    loggingMetric: exercise.loggingMetric,
    category: exercise.category,
  );
  return _isRearDeltFly(exercise)
      ? SlotRoleEligibility.add(mask, SlotRole.isolation)
      : mask;
}

/// The heaviest role the movement can actually fill. Pulldowns and pull-ups are
/// never `main`-eligible, and without this a Pull day's main slot relaxed its
/// *pattern* instead and could land on a squat. Keeping the movement and easing
/// the role is the right way round.
SlotRole _availableRole(
  _SlotNeed need,
  Iterable<ExerciseCatalogData> eligible,
) {
  if (need.role != SlotRole.main || need.segment != null) return need.role;
  final masks = [
    for (final exercise in eligible)
      if (_matchesNeed(exercise, need)) _roleMaskOf(exercise),
  ];
  final mainFits = masks.any(
    (mask) => SlotRoleEligibility.allows(mask, SlotRole.main),
  );
  final supplementalFits = masks.any(
    (mask) => SlotRoleEligibility.allows(mask, SlotRole.supplemental),
  );
  return !mainFits && supplementalFits ? SlotRole.supplemental : SlotRole.main;
}

/// The order slots choose in. A metcon is what a CrossFit day is for, and the
/// novice pool is small, so it picks before warm-up, skill and strength can use
/// the same few movements. Each entry keeps its position in the session.
List<(int, _SlotNeed)> _selectionOrder(List<_SlotNeed> needs) {
  final entries = needs.indexed.toList(growable: false);
  bool isMetcon((int, _SlotNeed) entry) =>
      entry.$2.segment == SessionSegment.metcon;
  return [...entries.where(isMetcon), ...entries.whereNot(isMetcon)];
}

/// Someone who opted into time-saving techniques needs isolation work on
/// equipment those techniques are safe on, or the opt-in does nothing.
double _timeSavingBonus(
  ExerciseCatalogData exercise,
  SlotRole role,
  SmartProgramConfiguration configuration,
) =>
    configuration.allowTimeSavingSetTechniques &&
        role == SlotRole.isolation &&
        (TimeSavingPolicy.stableModalities.contains(exercise.modality) ||
            const {'dumbbell', 'band'}.contains(exercise.modality))
    ? 0.5
    : 0;

/// The standard lift of each competition pattern. A close-grip bench shares
/// the bench anchor but is not what a main bench slot should default to.
const _benchmarkSlugs = {
  'barbell-back-squat',
  'barbell-bench-press',
  'conventional-deadlift',
  'overhead-press',
};

/// Intensity focus is ignored where it cannot apply, so a stale builder choice
/// or a rebuilt block can never prescribe RPE 9 to a novice.
bool _intensityFocusActive(
  SmartProgramConfiguration configuration,
  PeriodizationModel model,
) =>
    configuration.trainingFocus == TrainingFocus.intensity &&
    TrainingFocus.isAvailable(
      experience: configuration.experience,
      isMaxEffortModel: model == PeriodizationModel.maxEffort,
      style: configuration.trainingStyle,
    );

/// Two working sets for compounds at RPE 9, three for isolations. Rep ranges,
/// rest and isolation effort keep the slot role's values.
_Target _intensityTargetFor(SlotRole role, ExerciseCatalogData exercise) {
  final base = SmartProgramPlanner._targetFor(
    role,
    SlotTrainingMethod.intensityFocus,
    'medium',
    null,
  );
  final isCompound =
      exercise.mechanics == 'compound' && !_isRearDeltFly(exercise);
  return _Target(
    isCompound ? 2 : 3,
    base.repsMin,
    base.repsMax,
    isCompound ? 1 : base.rir,
    base.restSeconds,
  );
}

/// Whether the user chose a set technique for isolation work. Intensity focus
/// keeps three plain sets unless they did.
bool _wantsIsolationTechnique(
  SmartProgramConfiguration configuration,
  SlotRole role,
) =>
    role == SlotRole.isolation &&
    configuration.allowTimeSavingSetTechniques &&
    configuration.timeSavingTechnique != TimeSavingTechnique.automatic;

/// The one place a generated slot's rotation is decided, for filled and empty
/// slots alike.
RotationPolicy _rotationPolicyFor({
  required SlotTrainingMethod method,
  required SlotRole role,
  required PeriodizationModel model,
  required List<ProgramWeekData> weeks,
  required SmartProgramConfiguration configuration,
}) {
  final userChoice = configuration.effectiveRotationWeeks;
  if (userChoice == null &&
      method == SlotTrainingMethod.maxEffort &&
      role == SlotRole.main &&
      configuration.experience == ExperienceLevel.advanced) {
    return const RotationPolicy(everyWeeks: 1, minGapWeeks: 4, minPoolSize: 3);
  }
  return RotationPolicy.forProgram(
    model: model,
    role: role,
    blockPhase: weeks.firstOrNull?.blockPhase,
    userRotationWeeks: userChoice,
    isMaxEffortMethod: method == SlotTrainingMethod.maxEffort,
  );
}
