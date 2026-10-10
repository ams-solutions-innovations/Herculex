import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// How a [StrengthLift] is scored against its standard.
enum StrengthMeasure {
  /// Estimated 1RM divided by bodyweight.
  bodyweightRatio,

  /// Most strict, unassisted reps in one set.
  reps,
}

enum StrengthGroup { barbell, calisthenics }

/// The benchmark lifts that gate the Herculex rank bands.
///
/// The barbell slugs match `PrimaryLift.preferredSlugs`
/// (`programs/domain/primary_lift_specialization.dart`); the calisthenics set
/// adds the common variants so a chin-up or ring dip still counts.
enum StrengthLift {
  squat('Squat', StrengthGroup.barbell, {'barbell-back-squat'}),
  bench('Bench press', StrengthGroup.barbell, {'barbell-bench-press'}),
  deadlift('Deadlift', StrengthGroup.barbell, {'conventional-deadlift'}),
  overheadPress('Overhead press', StrengthGroup.barbell, {'overhead-press'}),
  pullUp('Pull-ups', StrengthGroup.calisthenics, {
    'pull-up',
    'pull-up-wide-grip',
    'chin-up-supinated',
  }),
  dip('Dips', StrengthGroup.calisthenics, {'chest-dips', 'ring-dips'}),
  pushUp('Push-ups', StrengthGroup.calisthenics, {'standard-push-up'}),
  muscleUp('Muscle-ups', StrengthGroup.calisthenics, {
    'strict-muscle-up',
    'bar-muscle-up',
    'ring-muscle-up',
  });

  const StrengthLift(this.label, this.group, this.slugs);

  final String label;
  final StrengthGroup group;
  final Set<String> slugs;

  StrengthMeasure get measure => group == StrengthGroup.barbell
      ? StrengthMeasure.bodyweightRatio
      : StrengthMeasure.reps;

  static StrengthLift? forSlug(String slug) {
    for (final lift in values) {
      if (lift.slugs.contains(slug)) return lift;
    }
    return null;
  }

  static StrengthLift? fromId(String id) {
    for (final lift in values) {
      if (lift.name == id) return lift;
    }
    return null;
  }
}

/// Entry thresholds for one lift. Each list is `[intermediate, advanced,
/// elite]`; `null` means the lift does not gate that band on its own and the
/// next band's threshold applies instead (a single muscle-up is already an
/// Advanced skill, so it also clears Intermediate).
class StrengthStandard {
  const StrengthStandard(this.lift, {required this.male, required this.female});

  final StrengthLift lift;
  final List<double?> male;
  final List<double?> female;

  /// The threshold printed for [band], or null when the lift is not listed
  /// for it. Novice has no threshold.
  double? listedThreshold(LevelBand band, BiologicalSex? sex) {
    if (band == LevelBand.novice) return null;
    final row = sex == BiologicalSex.female ? female : male;
    return row[band.index - 1];
  }

  /// The value that must be reached to count towards [band].
  double? effectiveThreshold(LevelBand band, BiologicalSex? sex) {
    for (var b = band.index; b < LevelBand.values.length; b++) {
      final value = listedThreshold(LevelBand.values[b], sex);
      if (value != null) return value;
    }
    return null;
  }
}

/// Herculex rank standards. The textbook defines training level by behaviour,
/// not by numbers on the bar, so these are a game rule only and never feed
/// program dosing. Barbell values are e1RM × bodyweight, calisthenics values
/// are strict reps. The explainer page renders this same list.
const strengthStandards = <StrengthStandard>[
  StrengthStandard(
    StrengthLift.squat,
    male: [1.25, 1.75, 2.25],
    female: [0.90, 1.30, 1.70],
  ),
  StrengthStandard(
    StrengthLift.bench,
    male: [1.00, 1.35, 1.75],
    female: [0.60, 0.90, 1.15],
  ),
  StrengthStandard(
    StrengthLift.deadlift,
    male: [1.50, 2.00, 2.60],
    female: [1.10, 1.60, 2.00],
  ),
  StrengthStandard(
    StrengthLift.overheadPress,
    male: [0.65, 0.85, 1.05],
    female: [0.40, 0.55, 0.70],
  ),
  StrengthStandard(StrengthLift.pullUp, male: [8, 15, 22], female: [3, 8, 15]),
  StrengthStandard(StrengthLift.dip, male: [15, 25, 40], female: [6, 15, 25]),
  StrengthStandard(
    StrengthLift.pushUp,
    male: [30, 50, 70],
    female: [12, 25, 40],
  ),
  StrengthStandard(
    StrengthLift.muscleUp,
    male: [null, 1, 10],
    female: [null, 1, 5],
  ),
];

/// How many benchmark lifts must clear a band's threshold to enter it.
const liftsNeededPerBand = 2;
