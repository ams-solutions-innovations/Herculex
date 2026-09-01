class FastingStage {
  final int hour;
  final String stageName;
  final String stageCategory;
  final String shortMessage;
  final String? detail;
  final String? icon;

  const FastingStage({
    required this.hour,
    required this.stageName,
    required this.stageCategory,
    required this.shortMessage,
    this.detail,
    this.icon,
  });

  factory FastingStage.fromJson(Map<String, dynamic> json) {
    return FastingStage(
      hour: json['hour'] as int,
      stageName: json['stageName'] as String,
      stageCategory: json['stageCategory'] as String,
      shortMessage: json['shortMessage'] as String,
      detail: json['detail'] as String?,
      icon: json['icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'stageName': stageName,
    'stageCategory': stageCategory,
    'shortMessage': shortMessage,
    'detail': detail,
    'icon': icon,
  };

  /// Returns the matching stage for the given elapsed fasting duration.
  /// Finds the highest hour milestone that is <= elapsed.inHours (minimum 1, capped at 72).
  static FastingStage resolveForElapsed(
    Duration elapsed,
    List<FastingStage> stages,
  ) {
    if (stages.isEmpty) {
      return const FastingStage(
        hour: 1,
        stageName: 'Prebava in absorpcija',
        stageCategory: 'Prebava',
        shortMessage:
            'Telo prebavlja zadnji obrok; glukoza in inzulin v krvi narasteta.',
      );
    }

    final elapsedHours = elapsed.inHours;
    final targetHour = elapsedHours.clamp(1, 72);

    // Find exact or closest preceding hour milestone
    FastingStage? match;
    for (final s in stages) {
      if (s.hour <= targetHour) {
        if (match == null || s.hour > match.hour) {
          match = s;
        }
      }
    }
    return match ?? stages.first;
  }
}
