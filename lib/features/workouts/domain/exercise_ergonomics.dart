class ExerciseErgonomics {
  /// The movement slug, e.g. 'squat', 'deadlift', 'bench_press'
  final String movementSlug;
  /// Ergonomic guidance keyed by anthropometric ratio (e.g. 'long_femur', 'short_torso')
  final Map<String, ErgonomicGuidance> guidanceByRatio;

  const ExerciseErgonomics({
    required this.movementSlug,
    required this.guidanceByRatio,
  });

  factory ExerciseErgonomics.fromJson(Map<String, dynamic> json) {
    return ExerciseErgonomics(
      movementSlug: json['movementSlug'] as String,
      guidanceByRatio: (json['guidanceByRatio'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, ErgonomicGuidance.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

class ErgonomicGuidance {
  final String guidance;
  final List<String> sources;

  const ErgonomicGuidance({
    required this.guidance,
    required this.sources,
  });

  factory ErgonomicGuidance.fromJson(Map<String, dynamic> json) {
    return ErgonomicGuidance(
      guidance: json['guidance'] as String,
      sources: (json['sources'] as List<dynamic>).map((e) => e as String).toList(),
    );
  }
}
