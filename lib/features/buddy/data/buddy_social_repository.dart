import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:herculex/features/buddy/domain/gym_buddy_social.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BuddySocialRepository {
  static const _kBuddiesKey = 'herculex.buddies.profiles_v2';
  static const _kPrFeedKey = 'herculex.buddies.pr_feed_v2';
  static const _kMyInviteCodeKey = 'herculex.buddies.my_code';

  final SharedPreferences _prefs;
  final _buddiesController =
      StreamController<List<GymBuddyProfile>>.broadcast();
  final _prFeedController = StreamController<List<BuddyPrActivity>>.broadcast();

  BuddySocialRepository(this._prefs) {
    _ensureInitialData();
  }

  void _ensureInitialData() {
    if (!_prefs.containsKey(_kBuddiesKey)) {
      final initialBuddies = [
        const GymBuddyProfile(
          id: 'buddy_luka',
          name: 'Luka Novak',
          avatarId: 'zeus',
          levelTitle: 'Spartan IV',
          levelNumber: 4,
          goalPhase: 'Cutting',
          currentWeightKg: 81.5,
          targetWeightKg: 78.0,
          goalProgressPercent: 0.86,
          benchmarkLifts: {
            'bench': 115.0,
            'squat': 155.0,
            'deadlift': 205.0,
            'ohp': 75.0,
            'pullup': 18.0,
          },
          lastWorkout: '2h ago',
          inviteCode: 'HERC-8921',
        ),
        const GymBuddyProfile(
          id: 'buddy_miha',
          name: 'Miha Kranjc',
          avatarId: 'ares',
          levelTitle: 'Olympian I',
          levelNumber: 6,
          goalPhase: 'Bulking',
          currentWeightKg: 88.0,
          targetWeightKg: 92.0,
          goalProgressPercent: 0.64,
          benchmarkLifts: {
            'bench': 132.5,
            'squat': 180.0,
            'deadlift': 225.0,
            'ohp': 85.0,
            'pullup': 14.0,
          },
          lastWorkout: 'Yesterday',
          inviteCode: 'HERC-4412',
        ),
        const GymBuddyProfile(
          id: 'buddy_sara',
          name: 'Sara Vidmar',
          avatarId: 'athena',
          levelTitle: 'Titan II',
          levelNumber: 5,
          goalPhase: 'Recomposition',
          currentWeightKg: 63.5,
          targetWeightKg: 62.0,
          goalProgressPercent: 0.92,
          benchmarkLifts: {
            'bench': 67.5,
            'squat': 100.0,
            'deadlift': 125.0,
            'ohp': 45.0,
            'pullup': 12.0,
          },
          lastWorkout: 'This morning',
          inviteCode: 'HERC-7309',
        ),
      ];
      final jsonList = initialBuddies.map((b) => b.toMap()).toList();
      _prefs.setString(_kBuddiesKey, json.encode(jsonList));
    }

    if (!_prefs.containsKey(_kPrFeedKey)) {
      final now = DateTime.now();
      final initialFeed = [
        BuddyPrActivity(
          id: 'pr_1',
          buddyId: 'buddy_luka',
          buddyName: 'Luka Novak',
          buddyAvatarId: 'zeus',
          exerciseName: 'Conventional Deadlift',
          weightKg: 205.0,
          reps: 1,
          improvementKg: 5.0,
          achievedAt: now.subtract(const Duration(hours: 3)),
          reactions: {'🔥': 4, '💪': 3, '👏': 2},
        ),
        BuddyPrActivity(
          id: 'pr_2',
          buddyId: 'buddy_miha',
          buddyName: 'Miha Kranjc',
          buddyAvatarId: 'ares',
          exerciseName: 'Barbell Bench Press',
          weightKg: 132.5,
          reps: 1,
          improvementKg: 2.5,
          achievedAt: now.subtract(const Duration(days: 1, hours: 2)),
          reactions: {'🔥': 6, '💪': 5},
        ),
        BuddyPrActivity(
          id: 'pr_3',
          buddyId: 'buddy_sara',
          buddyName: 'Sara Vidmar',
          buddyAvatarId: 'athena',
          exerciseName: 'Barbell Back Squat',
          weightKg: 100.0,
          reps: 2,
          improvementKg: 5.0,
          achievedAt: now.subtract(const Duration(days: 2)),
          reactions: {'💪': 4, '👏': 5},
        ),
      ];
      final jsonList = initialFeed.map((f) => f.toMap()).toList();
      _prefs.setString(_kPrFeedKey, json.encode(jsonList));
    }

    if (!_prefs.containsKey(_kMyInviteCodeKey)) {
      final randomNum = 1000 + Random().nextInt(8999);
      _prefs.setString(_kMyInviteCodeKey, 'HERC-$randomNum');
    }
  }

  String get myInviteCode => _prefs.getString(_kMyInviteCodeKey) ?? 'HERC-5582';

  List<GymBuddyProfile> getBuddies() {
    final raw = _prefs.getString(_kBuddiesKey);
    if (raw == null) return [];
    try {
      final List decoded = json.decode(raw);
      return decoded
          .map((m) => GymBuddyProfile.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Stream<List<GymBuddyProfile>> watchBuddies() {
    return Stream<List<GymBuddyProfile>>.multi((multi) {
      multi.add(getBuddies());
      final sub = _buddiesController.stream.listen(
        multi.add,
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  Future<void> saveBuddies(List<GymBuddyProfile> list) async {
    final raw = json.encode(list.map((b) => b.toMap()).toList());
    await _prefs.setString(_kBuddiesKey, raw);
    _buddiesController.add(list);
  }

  Future<void> addBuddy(GymBuddyProfile buddy) async {
    final current = getBuddies();
    final updated = [...current.where((b) => b.id != buddy.id), buddy];
    await saveBuddies(updated);
  }

  Future<void> removeBuddy(String buddyId) async {
    final current = getBuddies();
    final updated = current.where((b) => b.id != buddyId).toList();
    await saveBuddies(updated);
  }

  List<BuddyPrActivity> getPrActivities() {
    final raw = _prefs.getString(_kPrFeedKey);
    if (raw == null) return [];
    try {
      final List decoded = json.decode(raw);
      final list = decoded
          .map((m) => BuddyPrActivity.fromMap(m as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Stream<List<BuddyPrActivity>> watchPrActivities() {
    return Stream<List<BuddyPrActivity>>.multi((multi) {
      multi.add(getPrActivities());
      final sub = _prFeedController.stream.listen(
        multi.add,
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  Future<void> savePrActivities(List<BuddyPrActivity> list) async {
    final raw = json.encode(list.map((f) => f.toMap()).toList());
    await _prefs.setString(_kPrFeedKey, raw);
    _prFeedController.add(list);
  }

  Future<void> addPrActivity(BuddyPrActivity activity) async {
    final current = getPrActivities();
    final updated = [activity, ...current];
    await savePrActivities(updated);
  }

  Future<void> toggleReaction(String activityId, String emoji) async {
    final current = getPrActivities();
    final index = current.indexWhere((a) => a.id == activityId);
    if (index == -1) return;

    final item = current[index];
    final reactions = Map<String, int>.from(item.reactions);
    final count = reactions[emoji] ?? 0;
    reactions[emoji] = count + 1;

    final updatedItem = item.copyWith(reactions: reactions);
    current[index] = updatedItem;
    await savePrActivities(current);
  }

  // ── Custom Comparison Exercises ──────────────────────────────────────────

  static const _kComparisonExercisesKey =
      'herculex.buddies.comparison_exercises_v1';
  static const _kUserCustomLiftsKey = 'herculex.buddies.user_custom_lifts_v1';

  final _comparisonExercisesController =
      StreamController<List<ComparisonExercise>>.broadcast();

  static const defaultComparisonExercises = [
    ComparisonExercise(
      key: 'bench',
      label: 'Bench Press',
      unit: 'kg',
      slug: 'barbell-bench-press',
    ),
    ComparisonExercise(
      key: 'squat',
      label: 'Squat',
      unit: 'kg',
      slug: 'barbell-back-squat',
    ),
    ComparisonExercise(
      key: 'deadlift',
      label: 'Deadlift',
      unit: 'kg',
      slug: 'conventional-deadlift',
    ),
    ComparisonExercise(
      key: 'ohp',
      label: 'Overhead Press',
      unit: 'kg',
      slug: 'overhead-press',
    ),
    ComparisonExercise(
      key: 'pullup',
      label: 'Pull-ups',
      unit: 'reps',
      slug: 'pull-up',
    ),
  ];

  List<ComparisonExercise> getComparisonExercises() {
    final raw = _prefs.getString(_kComparisonExercisesKey);
    if (raw == null) return defaultComparisonExercises;
    try {
      final List decoded = json.decode(raw);
      return decoded
          .map((m) => ComparisonExercise.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return defaultComparisonExercises;
    }
  }

  Stream<List<ComparisonExercise>> watchComparisonExercises() {
    return Stream<List<ComparisonExercise>>.multi((multi) {
      multi.add(getComparisonExercises());
      final sub = _comparisonExercisesController.stream.listen(
        multi.add,
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  Map<String, double> getUserCustomLifts() {
    final raw = _prefs.getString(_kUserCustomLiftsKey);
    if (raw == null) return {};
    try {
      final Map<String, dynamic> decoded = json.decode(raw);
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> addComparisonExercise(
    ComparisonExercise exercise, {
    double? userValue,
  }) async {
    final current = getComparisonExercises();
    if (!current.any((e) => e.key == exercise.key)) {
      final updated = [...current, exercise];
      await _prefs.setString(
        _kComparisonExercisesKey,
        json.encode(updated.map((e) => e.toMap()).toList()),
      );
      _comparisonExercisesController.add(updated);
    }

    if (userValue != null) {
      final customLifts = getUserCustomLifts();
      customLifts[exercise.key] = userValue;
      await _prefs.setString(_kUserCustomLiftsKey, json.encode(customLifts));
    }

    // Also populate buddies with realistic estimates for this exercise
    final buddies = getBuddies();
    var modified = false;
    final val = userValue ?? 75.0;
    final updatedBuddies = buddies.map((b) {
      if (!b.benchmarkLifts.containsKey(exercise.key)) {
        modified = true;
        final map = Map<String, double>.from(b.benchmarkLifts);
        double buddyVal = val;
        if (b.id == 'buddy_miha') {
          buddyVal = val * 1.15;
        } else if (b.id == 'buddy_luka') {
          buddyVal = val * 1.05;
        } else if (b.id == 'buddy_sara') {
          buddyVal = val * 0.78;
        }
        map[exercise.key] = double.parse(buddyVal.toStringAsFixed(1));
        return b.copyWith(benchmarkLifts: map);
      }
      return b;
    }).toList();

    if (modified) {
      await saveBuddies(updatedBuddies);
    }
  }

  Future<void> removeComparisonExercise(String key) async {
    final current = getComparisonExercises();
    final updated = current.where((e) => e.key != key).toList();
    await _prefs.setString(
      _kComparisonExercisesKey,
      json.encode(updated.map((e) => e.toMap()).toList()),
    );
    _comparisonExercisesController.add(updated);
  }

  void dispose() {
    _buddiesController.close();
    _prFeedController.close();
    _comparisonExercisesController.close();
  }
}
