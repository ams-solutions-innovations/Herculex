import 'dart:convert';

/// Represents a friend / training partner profile with strength benchmarks and goal progress.
class GymBuddyProfile {
  final String id;
  final String name;
  final String? avatarId;
  final String levelTitle;
  final int levelNumber;
  final String goalPhase;
  final double? currentWeightKg;
  final double? targetWeightKg;
  final double goalProgressPercent;
  final Map<String, double> benchmarkLifts;
  final String lastWorkout;
  final bool isUser;
  final String? inviteCode;

  const GymBuddyProfile({
    required this.id,
    required this.name,
    this.avatarId,
    required this.levelTitle,
    required this.levelNumber,
    required this.goalPhase,
    this.currentWeightKg,
    this.targetWeightKg,
    required this.goalProgressPercent,
    required this.benchmarkLifts,
    required this.lastWorkout,
    this.isUser = false,
    this.inviteCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatarId': avatarId,
      'levelTitle': levelTitle,
      'levelNumber': levelNumber,
      'goalPhase': goalPhase,
      'currentWeightKg': currentWeightKg,
      'targetWeightKg': targetWeightKg,
      'goalProgressPercent': goalProgressPercent,
      'benchmarkLifts': benchmarkLifts,
      'lastWorkout': lastWorkout,
      'isUser': isUser,
      'inviteCode': inviteCode,
    };
  }

  factory GymBuddyProfile.fromMap(Map<String, dynamic> map) {
    return GymBuddyProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarId: map['avatarId'] as String?,
      levelTitle: map['levelTitle'] as String? ?? 'Novice I',
      levelNumber: (map['levelNumber'] as num?)?.toInt() ?? 1,
      goalPhase: map['goalPhase'] as String? ?? 'Maintenance',
      currentWeightKg: (map['currentWeightKg'] as num?)?.toDouble(),
      targetWeightKg: (map['targetWeightKg'] as num?)?.toDouble(),
      goalProgressPercent:
          (map['goalProgressPercent'] as num?)?.toDouble() ?? 0.0,
      benchmarkLifts:
          (map['benchmarkLifts'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          const {},
      lastWorkout: map['lastWorkout'] as String? ?? 'Today',
      isUser: map['isUser'] as bool? ?? false,
      inviteCode: map['inviteCode'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory GymBuddyProfile.fromJson(String source) =>
      GymBuddyProfile.fromMap(json.decode(source) as Map<String, dynamic>);

  GymBuddyProfile copyWith({
    String? id,
    String? name,
    String? avatarId,
    String? levelTitle,
    int? levelNumber,
    String? goalPhase,
    double? currentWeightKg,
    double? targetWeightKg,
    double? goalProgressPercent,
    Map<String, double>? benchmarkLifts,
    String? lastWorkout,
    bool? isUser,
    String? inviteCode,
  }) {
    return GymBuddyProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarId: avatarId ?? this.avatarId,
      levelTitle: levelTitle ?? this.levelTitle,
      levelNumber: levelNumber ?? this.levelNumber,
      goalPhase: goalPhase ?? this.goalPhase,
      currentWeightKg: currentWeightKg ?? this.currentWeightKg,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      goalProgressPercent: goalProgressPercent ?? this.goalProgressPercent,
      benchmarkLifts: benchmarkLifts ?? this.benchmarkLifts,
      lastWorkout: lastWorkout ?? this.lastWorkout,
      isUser: isUser ?? this.isUser,
      inviteCode: inviteCode ?? this.inviteCode,
    );
  }
}

/// A recent Personal Record (PR) post in the Gym Buddy activity stream.
class BuddyPrActivity {
  final String id;
  final String buddyId;
  final String buddyName;
  final String? buddyAvatarId;
  final String exerciseName;
  final double weightKg;
  final int reps;
  final double? improvementKg;
  final DateTime achievedAt;
  final Map<String, int> reactions; // e.g. {'🔥': 3, '💪': 5, '👏': 2}

  const BuddyPrActivity({
    required this.id,
    required this.buddyId,
    required this.buddyName,
    this.buddyAvatarId,
    required this.exerciseName,
    required this.weightKg,
    this.reps = 1,
    this.improvementKg,
    required this.achievedAt,
    this.reactions = const {'🔥': 1, '💪': 2},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buddyId': buddyId,
      'buddyName': buddyName,
      'buddyAvatarId': buddyAvatarId,
      'exerciseName': exerciseName,
      'weightKg': weightKg,
      'reps': reps,
      'improvementKg': improvementKg,
      'achievedAt': achievedAt.toIso8601String(),
      'reactions': reactions,
    };
  }

  factory BuddyPrActivity.fromMap(Map<String, dynamic> map) {
    return BuddyPrActivity(
      id: map['id'] as String,
      buddyId: map['buddyId'] as String,
      buddyName: map['buddyName'] as String,
      buddyAvatarId: map['buddyAvatarId'] as String?,
      exerciseName: map['exerciseName'] as String,
      weightKg: (map['weightKg'] as num).toDouble(),
      reps: (map['reps'] as num?)?.toInt() ?? 1,
      improvementKg: (map['improvementKg'] as num?)?.toDouble(),
      achievedAt:
          DateTime.tryParse(map['achievedAt'] as String? ?? '') ??
          DateTime.now(),
      reactions:
          (map['reactions'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ) ??
          const {'🔥': 1, '💪': 1},
    );
  }

  String toJson() => json.encode(toMap());

  factory BuddyPrActivity.fromJson(String source) =>
      BuddyPrActivity.fromMap(json.decode(source) as Map<String, dynamic>);

  BuddyPrActivity copyWith({
    String? id,
    String? buddyId,
    String? buddyName,
    String? buddyAvatarId,
    String? exerciseName,
    double? weightKg,
    int? reps,
    double? improvementKg,
    DateTime? achievedAt,
    Map<String, int>? reactions,
  }) {
    return BuddyPrActivity(
      id: id ?? this.id,
      buddyId: buddyId ?? this.buddyId,
      buddyName: buddyName ?? this.buddyName,
      buddyAvatarId: buddyAvatarId ?? this.buddyAvatarId,
      exerciseName: exerciseName ?? this.exerciseName,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      improvementKg: improvementKg ?? this.improvementKg,
      achievedAt: achievedAt ?? this.achievedAt,
      reactions: reactions ?? this.reactions,
    );
  }
}

/// An exercise tracked in the Gym Buddy lifts comparison leaderboard.
class ComparisonExercise {
  final String key;
  final String label;
  final String unit; // 'kg' or 'reps'
  final bool isCustom;
  final String? slug;

  const ComparisonExercise({
    required this.key,
    required this.label,
    this.unit = 'kg',
    this.isCustom = false,
    this.slug,
  });

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'unit': unit,
    'isCustom': isCustom,
    if (slug != null) 'slug': slug,
  };

  factory ComparisonExercise.fromMap(Map<String, dynamic> map) =>
      ComparisonExercise(
        key: map['key'] as String,
        label: map['label'] as String,
        unit: map['unit'] as String? ?? 'kg',
        isCustom: map['isCustom'] as bool? ?? false,
        slug: map['slug'] as String?,
      );

  String toJson() => json.encode(toMap());

  factory ComparisonExercise.fromJson(String source) =>
      ComparisonExercise.fromMap(json.decode(source) as Map<String, dynamic>);
}
