import 'package:herculex/features/gamification/domain/strength_standards.dart';

enum TrainingStyle {
  weights,
  calisthenics,
  both;

  String get label => switch (this) {
    TrainingStyle.weights => 'Weights',
    TrainingStyle.calisthenics => 'Calisthenics',
    TrainingStyle.both => 'Both',
  };

  bool includes(StrengthGroup group) => switch (this) {
    TrainingStyle.weights => group == StrengthGroup.barbell,
    TrainingStyle.calisthenics => group == StrengthGroup.calisthenics,
    TrainingStyle.both => true,
  };
}

/// One self-reported lift: a load × reps set for barbell lifts, or max reps
/// for calisthenics (where [weightKg] stays null).
class SurveyLiftEntry {
  const SurveyLiftEntry({this.weightKg, required this.reps});

  final double? weightKg;
  final int reps;

  Map<String, dynamic> toJson() => {'weightKg': weightKg, 'reps': reps};

  factory SurveyLiftEntry.fromJson(Map<String, dynamic> json) =>
      SurveyLiftEntry(
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        reps: (json['reps'] as num?)?.toInt() ?? 0,
      );
}

/// The optional onboarding strength check. Self-reported, so it can place
/// someone up to Advanced but never into Elite.
class StrengthSurvey {
  const StrengthSurvey({required this.style, required this.lifts});

  final TrainingStyle style;
  final Map<StrengthLift, SurveyLiftEntry> lifts;

  bool get isEmpty => lifts.isEmpty;

  Map<String, dynamic> toJson() => {
    'style': style.name,
    'lifts': {
      for (final entry in lifts.entries) entry.key.name: entry.value.toJson(),
    },
  };

  factory StrengthSurvey.fromJson(Map<String, dynamic> json) {
    final rawLifts = json['lifts'] as Map<String, dynamic>? ?? const {};
    final lifts = <StrengthLift, SurveyLiftEntry>{};
    for (final entry in rawLifts.entries) {
      final lift = StrengthLift.fromId(entry.key);
      if (lift == null || entry.value is! Map<String, dynamic>) continue;
      lifts[lift] = SurveyLiftEntry.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return StrengthSurvey(
      style: TrainingStyle.values.firstWhere(
        (s) => s.name == json['style'],
        orElse: () => TrainingStyle.both,
      ),
      lifts: lifts,
    );
  }
}
