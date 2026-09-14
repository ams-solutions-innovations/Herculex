class GymEquipmentOption {
  const GymEquipmentOption(this.key, this.label, this.group);
  final String key;
  final String label;
  final String group;
}

abstract final class GymEquipmentCatalog {
  static const options = <GymEquipmentOption>[
    GymEquipmentOption('barbell', 'Barbells & plates', 'Free weights'),
    GymEquipmentOption('dumbbell', 'Dumbbells', 'Free weights'),
    GymEquipmentOption('kettlebell', 'Kettlebells', 'Free weights'),
    GymEquipmentOption('cable', 'Cable stations', 'Cables'),
    GymEquipmentOption('machine_plate', 'Plate-loaded machines', 'Machines'),
    GymEquipmentOption(
      'machine_selectorized',
      'Selectorized machines',
      'Machines',
    ),
    GymEquipmentOption('smith', 'Smith machine', 'Machines'),
    GymEquipmentOption('bodyweight', 'Bodyweight space', 'Bodyweight'),
    GymEquipmentOption('rings_trx', 'Rings / TRX', 'Bodyweight'),
    GymEquipmentOption(
      'safety_squat_bar',
      'Safety squat bar',
      'Specialty bars',
    ),
    GymEquipmentOption('cambered_bar', 'Cambered bar', 'Specialty bars'),
    GymEquipmentOption('swiss_bar', 'Swiss / football bar', 'Specialty bars'),
    GymEquipmentOption('duffalo_bar', 'Duffalo bar', 'Specialty bars'),
    GymEquipmentOption('axle_bar', 'Axle bar', 'Specialty bars'),
    GymEquipmentOption('trap_bar', 'Trap bar', 'Specialty bars'),
    GymEquipmentOption('chains', 'Chains', 'Accommodating resistance'),
    GymEquipmentOption('bands', 'Resistance bands', 'Accommodating resistance'),
    GymEquipmentOption('reverse_hyper', 'Reverse hyper', 'Special stations'),
    GymEquipmentOption('ghr', 'Glute-ham raise', 'Special stations'),
    GymEquipmentOption('belt_squat', 'Belt squat', 'Special stations'),
    GymEquipmentOption('sled', 'Sled', 'Strongman / athletic'),
    GymEquipmentOption('yoke', 'Yoke', 'Strongman / athletic'),
    GymEquipmentOption('other', 'Other standard equipment', 'Other'),
  ];

  static const quickPresets = <String, Set<String>>{
    'Free weights': {'barbell', 'dumbbell', 'kettlebell'},
    'Cables': {'cable'},
    'Machines': {'machine_plate', 'machine_selectorized', 'smith'},
    'Bodyweight': {'bodyweight', 'rings_trx'},
  };
}
