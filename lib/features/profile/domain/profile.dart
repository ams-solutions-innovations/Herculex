import 'dart:convert';

enum FitnessGoal {
  weightLoss,
  muscleGain,
  maintenance,
  improveHealth;

  String get label => switch (this) {
    FitnessGoal.weightLoss => 'Weight Loss',
    FitnessGoal.muscleGain => 'Muscle Gain',
    FitnessGoal.maintenance => 'Maintenance',
    FitnessGoal.improveHealth => 'Improve Health',
  };

  static FitnessGoal fromLabel(String label) => FitnessGoal.values.firstWhere(
    (g) => g.label == label,
    orElse: () => FitnessGoal.maintenance,
  );
}

enum ActivityLevel {
  sedentary,
  lightlyActive,
  active,
  veryActive;

  String get label => switch (this) {
    ActivityLevel.sedentary => 'Sedentary',
    ActivityLevel.lightlyActive => 'Lightly Active',
    ActivityLevel.active => 'Active',
    ActivityLevel.veryActive => 'Very Active',
  };

  static ActivityLevel fromLabel(String label) =>
      ActivityLevel.values.firstWhere(
        (a) => a.label == label,
        orElse: () => ActivityLevel.lightlyActive,
      );
}

enum BiologicalSex {
  male,
  female;

  String get label => switch (this) {
    BiologicalSex.male => 'Male',
    BiologicalSex.female => 'Female',
  };
}

enum MeasurementUnit {
  metric,
  imperial;

  String get label => switch (this) {
    MeasurementUnit.metric => 'Metric (kg, cm)',
    MeasurementUnit.imperial => 'Freedom (lb, in)',
  };
}

class Profile {
  final String? name;
  final FitnessGoal goal;
  final ActivityLevel activityLevel;
  final int? ageYears;
  final double? weightKg;
  final double? targetWeightKg;
  final double? heightCm;
  final BiologicalSex? sex;
  final MeasurementUnit preferredUnit;
  final bool countBurnedCalories;
  final String herculTone;

  const Profile({
    this.name,
    required this.goal,
    required this.activityLevel,
    this.ageYears,
    this.weightKg,
    this.targetWeightKg,
    this.heightCm,
    this.sex,
    this.preferredUnit = MeasurementUnit.metric,
    this.countBurnedCalories = false,
    this.herculTone = 'normal',
  });

  bool get isComplete =>
      ageYears != null && weightKg != null && heightCm != null && sex != null;

  Profile copyWith({
    String? name,
    FitnessGoal? goal,
    ActivityLevel? activityLevel,
    int? ageYears,
    double? weightKg,
    double? targetWeightKg,
    double? heightCm,
    BiologicalSex? sex,
    MeasurementUnit? preferredUnit,
    bool? countBurnedCalories,
    String? herculTone,
  }) {
    return Profile(
      name: name ?? this.name,
      goal: goal ?? this.goal,
      activityLevel: activityLevel ?? this.activityLevel,
      ageYears: ageYears ?? this.ageYears,
      weightKg: weightKg ?? this.weightKg,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      heightCm: heightCm ?? this.heightCm,
      sex: sex ?? this.sex,
      preferredUnit: preferredUnit ?? this.preferredUnit,
      countBurnedCalories: countBurnedCalories ?? this.countBurnedCalories,
      herculTone: herculTone ?? this.herculTone,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'goal': goal.name,
    'activityLevel': activityLevel.name,
    'ageYears': ageYears,
    'weightKg': weightKg,
    'targetWeightKg': targetWeightKg,
    'heightCm': heightCm,
    'sex': sex?.name,
    'preferredUnit': preferredUnit.name,
    'countBurnedCalories': countBurnedCalories,
    'herculTone': herculTone,
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    name: (json['name'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['name'] as String).trim(),
    goal: FitnessGoal.values.byName(json['goal'] as String),
    activityLevel: ActivityLevel.values.byName(json['activityLevel'] as String),
    ageYears: json['ageYears'] as int?,
    weightKg:
        (json['weightKg'] as num?)?.toDouble() ??
        (json['weight_kg'] as num?)?.toDouble(),
    targetWeightKg:
        (json['targetWeightKg'] as num?)?.toDouble() ??
        (json['target_weight_kg'] as num?)?.toDouble(),
    heightCm:
        (json['heightCm'] as num?)?.toDouble() ??
        (json['height_cm'] as num?)?.toDouble(),
    sex: json['sex'] == null
        ? null
        : BiologicalSex.values.byName(json['sex'] as String),
    preferredUnit: json['preferredUnit'] == null
        ? MeasurementUnit.metric
        : MeasurementUnit.values.byName(json['preferredUnit'] as String),
    countBurnedCalories: json['countBurnedCalories'] as bool? ?? false,
    herculTone: json['herculTone'] as String? ?? 'normal',
  );

  String encode() => jsonEncode(toJson());
  static Profile decode(String raw) =>
      Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
