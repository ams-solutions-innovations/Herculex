/// Rounding step (kg) for drop-set weight reduction, by equipment variant
/// (item 4). Different equipment moves in different increments — a barbell
/// only changes in full plate pairs, a cable stack in small pin steps.
double dropSetRoundingStepKg(String? equipmentVariant) {
  switch (equipmentVariant) {
    case 'barbell':
    case 'smith':
      return 5.0;
    case 'dumbbell':
    case 'kettlebell':
      return 2.5;
    case 'cable':
    case 'machine_plate':
    case 'machine_selectorized':
      return 2.0;
    case 'bodyweight':
    default:
      return 2.5;
  }
}
