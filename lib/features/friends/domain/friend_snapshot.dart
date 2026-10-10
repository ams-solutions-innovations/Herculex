import 'package:herculex/features/gamification/domain/strength_standards.dart';

/// Best known number on one benchmark lift.
class FriendLift {
  const FriendLift({
    required this.lift,
    required this.value,
    this.e1rmKg,
    this.lifterTopPct,
  });

  final StrengthLift lift;

  /// In the lift's measure: × bodyweight or reps.
  final double value;

  /// Estimated 1RM in kg, barbell lifts only.
  final double? e1rmKg;
  final double? lifterTopPct;

  Map<String, dynamic> toJson() => {
    'lift': lift.name,
    'value': value,
    'e1rmKg': ?e1rmKg,
    'topPct': ?lifterTopPct,
  };

  static FriendLift? fromJson(Map<String, dynamic> j) {
    final lift = StrengthLift.fromId(j['lift'] as String? ?? '');
    final value = (j['value'] as num?)?.toDouble();
    if (lift == null || value == null) return null;
    return FriendLift(
      lift: lift,
      value: value,
      e1rmKg: (j['e1rmKg'] as num?)?.toDouble(),
      lifterTopPct: (j['topPct'] as num?)?.toDouble(),
    );
  }
}

/// A recent estimated-1RM record on one exercise.
class FriendPr {
  const FriendPr({
    required this.exercise,
    required this.e1rmKg,
    required this.at,
  });

  final String exercise;
  final double e1rmKg;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'exercise': exercise,
    'e1rmKg': e1rmKg,
    'at': at.toUtc().toIso8601String(),
  };

  static FriendPr? fromJson(Map<String, dynamic> j) {
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    final kg = (j['e1rmKg'] as num?)?.toDouble();
    final name = j['exercise'] as String?;
    if (at == null || kg == null || name == null) return null;
    return FriendPr(exercise: name, e1rmKg: kg, at: at.toLocal());
  }
}

/// Bodyweight goal progress. [progress] is 0–1 from start to target.
class FriendGoal {
  const FriendGoal({
    required this.startKg,
    required this.currentKg,
    required this.targetKg,
  });

  final double startKg;
  final double currentKg;
  final double targetKg;

  double get progress {
    final span = targetKg - startKg;
    if (span.abs() < 0.1) return 1;
    return ((currentKg - startKg) / span).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'startKg': startKg,
    'currentKg': currentKg,
    'targetKg': targetKg,
  };

  static FriendGoal? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final s = (j['startKg'] as num?)?.toDouble();
    final c = (j['currentKg'] as num?)?.toDouble();
    final t = (j['targetKg'] as num?)?.toDouble();
    if (s == null || c == null || t == null) return null;
    return FriendGoal(startKg: s, currentKg: c, targetKg: t);
  }
}

/// One side's numbers from a workout done together.
class FriendBuddySession {
  const FriendBuddySession({
    required this.buddySessionId,
    required this.at,
    required this.tonnageKg,
    required this.sets,
    this.topExercise,
    this.topKg,
    this.topReps,
  });

  final String buddySessionId;
  final DateTime at;
  final double tonnageKg;
  final int sets;
  final String? topExercise;
  final double? topKg;
  final int? topReps;

  Map<String, dynamic> toJson() => {
    'id': buddySessionId,
    'at': at.toUtc().toIso8601String(),
    'tonnageKg': tonnageKg,
    'sets': sets,
    'topExercise': ?topExercise,
    'topKg': ?topKg,
    'topReps': ?topReps,
  };

  static FriendBuddySession? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    if (id == null || at == null) return null;
    return FriendBuddySession(
      buddySessionId: id,
      at: at.toLocal(),
      tonnageKg: (j['tonnageKg'] as num?)?.toDouble() ?? 0,
      sets: (j['sets'] as num?)?.toInt() ?? 0,
      topExercise: j['topExercise'] as String?,
      topKg: (j['topKg'] as num?)?.toDouble(),
      topReps: (j['topReps'] as num?)?.toInt(),
    );
  }
}

/// The summary a user publishes for friends. Deliberately small: no raw sets,
/// no bodyweight history, nothing a friend could not see across the gym.
class FriendSnapshot {
  const FriendSnapshot({
    required this.levelTitle,
    required this.completedWorkouts,
    required this.weekTonnageKg,
    required this.lifts,
    required this.recentPrs,
    required this.buddySessions,
    this.goal,
  });

  static const schemaVersion = 1;

  /// Recent PRs and buddy sessions are capped so the row stays small.
  static const maxPrs = 8;
  static const maxBuddySessions = 20;

  final String levelTitle;
  final int completedWorkouts;
  final double weekTonnageKg;
  final List<FriendLift> lifts;
  final List<FriendPr> recentPrs;
  final List<FriendBuddySession> buddySessions;
  final FriendGoal? goal;

  FriendLift? liftOf(StrengthLift lift) {
    for (final l in lifts) {
      if (l.lift == lift) return l;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'levelTitle': levelTitle,
    'completedWorkouts': completedWorkouts,
    'weekTonnageKg': weekTonnageKg,
    'lifts': [for (final l in lifts) l.toJson()],
    'recentPrs': [for (final p in recentPrs.take(maxPrs)) p.toJson()],
    'buddySessions': [
      for (final s in buddySessions.take(maxBuddySessions)) s.toJson(),
    ],
    'goal': ?goal?.toJson(),
  };

  /// Tolerant: a friend on an older or newer app version must never crash
  /// the list, so unknown or broken entries are dropped, not thrown.
  static FriendSnapshot fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T? Function(Map<String, dynamic>) parse) => [
      for (final e in (j[key] as List?) ?? const [])
        if (e is Map) ?parse(Map<String, dynamic>.from(e)),
    ];
    final goal = j['goal'];
    return FriendSnapshot(
      levelTitle: j['levelTitle'] as String? ?? '',
      completedWorkouts: (j['completedWorkouts'] as num?)?.toInt() ?? 0,
      weekTonnageKg: (j['weekTonnageKg'] as num?)?.toDouble() ?? 0,
      lifts: list('lifts', FriendLift.fromJson),
      recentPrs: list('recentPrs', FriendPr.fromJson),
      buddySessions: list('buddySessions', FriendBuddySession.fromJson),
      goal: goal is Map
          ? FriendGoal.fromJson(Map<String, dynamic>.from(goal))
          : null,
    );
  }
}
