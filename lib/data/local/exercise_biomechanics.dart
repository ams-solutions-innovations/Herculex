/// Pure derivations that map the Exercise Intelligence attributes
/// (category / movement pattern / granular muscles) onto the legacy
/// biomechanics columns (`mechanics`, `force`, `plane`, coarse `primaryMuscle`)
/// the substitution engine and old analytics still rely on.
///
/// Shared by [ExerciseImporter] and the custom-exercise builder so both produce
/// consistent rows.
class ExerciseBiomechanics {
  const ExerciseBiomechanics._();

  /// Granular muscle → coarse legacy group (Chest|Back|Shoulders|…).
  static const coarseGroup = <String, String>{
    'Chest': 'Chest',
    'Serratus': 'Chest',
    'Lats': 'Back',
    'Rhomboids': 'Back',
    'Traps': 'Back',
    'Erectors': 'Back',
    'Front Delts': 'Shoulders',
    'Side Delts': 'Shoulders',
    'Rear Delts': 'Shoulders',
    'Biceps': 'Biceps',
    'Brachialis': 'Biceps',
    'Triceps': 'Triceps',
    'Forearms': 'Forearms',
    'Quads': 'Quads',
    'Hamstrings': 'Hamstrings',
    'Glutes': 'Glutes',
    'Calves': 'Calves',
    'Tibialis': 'Calves',
    'Adductors': 'Adductors',
    'Abductors': 'Abductors',
    'Abs': 'Abs',
    'Obliques': 'Abs',
    'Hip Flexors': 'Abs',
    'Core': 'Abs',
    'Neck': 'Neck',
  };

  static String coarseMuscle(String granular) =>
      coarseGroup[granular] ?? granular;

  static String mechanics(String? pattern, String category) {
    if (category == 'hypertrophy') return 'isolation';
    if (pattern == 'isolation' || pattern == 'core') return 'isolation';
    return 'compound';
  }

  static String force(String? pattern, String primaryMuscle) {
    switch (pattern) {
      case 'horizontal_push':
      case 'vertical_push':
      case 'squat':
      case 'lunge':
      case 'carry':
        return 'push';
      case 'horizontal_pull':
      case 'vertical_pull':
      case 'hinge':
        return 'pull';
      case 'core':
        return 'static';
    }
    const pull = {'Back', 'Biceps', 'Hamstrings', 'Forearms'};
    const stat = {'Abs', 'Neck'};
    if (pull.contains(primaryMuscle)) return 'pull';
    if (stat.contains(primaryMuscle)) return 'static';
    return 'push';
  }

  static String plane(String? pattern) {
    switch (pattern) {
      case 'squat':
      case 'hinge':
      case 'carry':
      case 'lunge':
        return 'axial';
      case 'horizontal_push':
      case 'horizontal_pull':
        return 'horizontal';
      case 'vertical_push':
      case 'vertical_pull':
        return 'vertical';
      default:
        return 'none';
    }
  }
}
