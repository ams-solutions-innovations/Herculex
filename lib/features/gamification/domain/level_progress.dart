/// A deterministic progression ladder.
///
/// The band comes from benchmark lifts (`strength_tier_evaluator.dart`) and
/// is both floor and ceiling; XP earned by training only moves the rank
/// within it, I to V. It is a game rank, not a judgement of someone's
/// physique, health or athletic potential, and not the programming
/// `ExperienceLevel`.
enum LevelBand {
  novice('Novice'),
  intermediate('Intermediate'),
  advanced('Advanced'),
  elite('Elite');

  const LevelBand(this.label);
  final String label;

  LevelBand? get next => index + 1 < values.length ? values[index + 1] : null;
}

class TrainingLevel {
  const TrainingLevel({
    required this.number,
    required this.band,
    required this.bandRank,
    required this.xpIntoBand,
    required this.title,
  });

  final int number;
  final LevelBand band;
  final int bandRank;

  /// XP earned since entering [band] needed to hold this rank.
  final int xpIntoBand;
  final String title;
}

const _rankNumerals = ['I', 'II', 'III', 'IV', 'V'];

/// XP into the band for ranks I–V. Higher bands take longer per rank.
const _bandRankXp = <LevelBand, List<int>>{
  LevelBand.novice: [0, 100, 250, 450, 700],
  LevelBand.intermediate: [0, 200, 450, 750, 1100],
  LevelBand.advanced: [0, 300, 650, 1050, 1500],
  LevelBand.elite: [0, 400, 900, 1500, 2200],
};

/// Kept in one immutable list so progress never changes based on locale or
/// an opaque recommendation model.
final List<TrainingLevel> trainingLevels = List.unmodifiable([
  for (final band in LevelBand.values)
    for (var rank = 1; rank <= _rankNumerals.length; rank++)
      TrainingLevel(
        number: band.index * _rankNumerals.length + rank,
        band: band,
        bandRank: rank,
        xpIntoBand: _bandRankXp[band]![rank - 1],
        title: '${band.label} ${_rankNumerals[rank - 1]}',
      ),
]);

/// Raw ledger totals, before a band is applied.
class XpTotals {
  const XpTotals({required this.totalXp, required this.completedWorkouts});

  final int totalXp;
  final int completedWorkouts;
}

class LevelProgress {
  const LevelProgress({
    required this.band,
    required this.xpInBand,
    this.totalXp = 0,
    this.completedWorkouts = 0,
  });

  final LevelBand band;
  final int xpInBand;
  final int totalXp;
  final int completedWorkouts;

  TrainingLevel get level => trainingLevels.lastWhere(
    (candidate) => candidate.band == band && candidate.xpIntoBand <= xpInBand,
  );

  /// The next rank inside the band; null at V, where only strength moves on.
  TrainingLevel? get nextLevel {
    final index = trainingLevels.indexOf(level);
    final candidate = index + 1 < trainingLevels.length
        ? trainingLevels[index + 1]
        : null;
    return candidate?.band == band ? candidate : null;
  }

  bool get isBandMaxed => nextLevel == null;

  int get xpIntoLevel => xpInBand - level.xpIntoBand;
  int? get xpForNextLevel =>
      nextLevel == null ? null : nextLevel!.xpIntoBand - level.xpIntoBand;
  int? get xpRemaining =>
      nextLevel == null ? null : nextLevel!.xpIntoBand - xpInBand;
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
