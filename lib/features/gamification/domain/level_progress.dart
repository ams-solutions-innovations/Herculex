/// A deterministic, training-only progression ladder.
///
/// Levels reflect app activity and logged training signals, not a judgement of
/// someone's physique, health, or athletic potential.
enum LevelBand { novice, intermediate, advanced }

class TrainingLevel {
  const TrainingLevel({
    required this.number,
    required this.band,
    required this.bandRank,
    required this.xpAtLevel,
    required this.title,
  });

  final int number;
  final LevelBand band;
  final int bandRank;
  final int xpAtLevel;
  final String title;
}

/// Kept in one immutable list so progress never changes based on locale,
/// profile fields, or an opaque recommendation model.
const trainingLevels = <TrainingLevel>[
  TrainingLevel(
    number: 1,
    band: LevelBand.novice,
    bandRank: 1,
    xpAtLevel: 0,
    title: 'Novice I',
  ),
  TrainingLevel(
    number: 2,
    band: LevelBand.novice,
    bandRank: 2,
    xpAtLevel: 100,
    title: 'Novice II',
  ),
  TrainingLevel(
    number: 3,
    band: LevelBand.novice,
    bandRank: 3,
    xpAtLevel: 250,
    title: 'Novice III',
  ),
  TrainingLevel(
    number: 4,
    band: LevelBand.novice,
    bandRank: 4,
    xpAtLevel: 450,
    title: 'Novice IV',
  ),
  TrainingLevel(
    number: 5,
    band: LevelBand.novice,
    bandRank: 5,
    xpAtLevel: 700,
    title: 'Novice V',
  ),
  TrainingLevel(
    number: 6,
    band: LevelBand.intermediate,
    bandRank: 1,
    xpAtLevel: 1000,
    title: 'Intermediate I',
  ),
  TrainingLevel(
    number: 7,
    band: LevelBand.intermediate,
    bandRank: 2,
    xpAtLevel: 1400,
    title: 'Intermediate II',
  ),
  TrainingLevel(
    number: 8,
    band: LevelBand.intermediate,
    bandRank: 3,
    xpAtLevel: 1900,
    title: 'Intermediate III',
  ),
  TrainingLevel(
    number: 9,
    band: LevelBand.intermediate,
    bandRank: 4,
    xpAtLevel: 2500,
    title: 'Intermediate IV',
  ),
  TrainingLevel(
    number: 10,
    band: LevelBand.intermediate,
    bandRank: 5,
    xpAtLevel: 3200,
    title: 'Intermediate V',
  ),
  TrainingLevel(
    number: 11,
    band: LevelBand.advanced,
    bandRank: 1,
    xpAtLevel: 4000,
    title: 'Advanced I',
  ),
  TrainingLevel(
    number: 12,
    band: LevelBand.advanced,
    bandRank: 2,
    xpAtLevel: 5000,
    title: 'Advanced II',
  ),
  TrainingLevel(
    number: 13,
    band: LevelBand.advanced,
    bandRank: 3,
    xpAtLevel: 6200,
    title: 'Advanced III',
  ),
  TrainingLevel(
    number: 14,
    band: LevelBand.advanced,
    bandRank: 4,
    xpAtLevel: 7600,
    title: 'Advanced IV',
  ),
  TrainingLevel(
    number: 15,
    band: LevelBand.advanced,
    bandRank: 5,
    xpAtLevel: 9200,
    title: 'Advanced V',
  ),
];

class LevelProgress {
  const LevelProgress({required this.totalXp, required this.completedWorkouts});

  final int totalXp;
  final int completedWorkouts;

  TrainingLevel get level => trainingLevels.lastWhere(
    (candidate) => candidate.xpAtLevel <= totalXp,
    orElse: () => trainingLevels.first,
  );

  TrainingLevel? get nextLevel {
    final index = trainingLevels.indexOf(level);
    return index + 1 < trainingLevels.length ? trainingLevels[index + 1] : null;
  }

  int get xpIntoLevel => totalXp - level.xpAtLevel;
  int? get xpForNextLevel =>
      nextLevel == null ? null : nextLevel!.xpAtLevel - level.xpAtLevel;
  int? get xpRemaining =>
      nextLevel == null ? null : nextLevel!.xpAtLevel - totalXp;
  double get progressToNext =>
      nextLevel == null ? 1 : (xpIntoLevel / xpForNextLevel!).clamp(0.0, 1.0);
}

class XpLedgerEntry {
  const XpLedgerEntry({
    required this.id,
    required this.awardedAt,
    required this.xp,
    required this.reasons,
  });

  final String id;
  final DateTime awardedAt;
  final int xp;
  final List<String> reasons;

  Map<String, Object> toJson() => {
    'id': id,
    'awardedAt': awardedAt.toUtc().toIso8601String(),
    'xp': xp,
    'reasons': reasons,
  };

  factory XpLedgerEntry.fromJson(Map<String, dynamic> json) => XpLedgerEntry(
    id: json['id'] as String,
    awardedAt: DateTime.parse(json['awardedAt'] as String).toLocal(),
    xp: (json['xp'] as num).toInt(),
    reasons: (json['reasons'] as List<dynamic>? ?? const []).cast<String>(),
  );
}

class XpAward {
  const XpAward({required this.xp, required this.reasons});
  final int xp;
  final List<String> reasons;
}
