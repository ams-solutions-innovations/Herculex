import 'dart:convert';

/// User preferences for all notification categories in Herculex.
class NotificationSettings {
  // ── Meal reminders ─────────────────────────────────────────────────────────
  final bool mealRemindersEnabled;
  final Map<String, String> mealTimes; // slotKey -> 'HH:MM'
  final Map<String, bool> mealEnabled; // slotKey -> isEnabled

  // ── Fasting reminders ──────────────────────────────────────────────────────
  final bool fastingGoalReachedEnabled;
  final bool fastingScheduleRemindersEnabled;

  // ── Supplement reminders ───────────────────────────────────────────────────
  final bool supplementRemindersEnabled;
  final bool postWorkoutSupplementEnabled;

  // ── Workout reminders ──────────────────────────────────────────────────────
  final bool activeWorkoutBannerEnabled;
  final bool restTimerAlertsEnabled;

  // ── Daily habit / log reminders ────────────────────────────────────────────
  final bool dailyLogReminderEnabled;
  final String dailyLogTimeHHMM;

  const NotificationSettings({
    this.mealRemindersEnabled = true,
    this.mealTimes = defaultMealTimes,
    this.mealEnabled = defaultMealEnabled,
    this.fastingGoalReachedEnabled = true,
    this.fastingScheduleRemindersEnabled = true,
    this.supplementRemindersEnabled = true,
    this.postWorkoutSupplementEnabled = true,
    this.activeWorkoutBannerEnabled = true,
    this.restTimerAlertsEnabled = true,
    this.dailyLogReminderEnabled = false,
    this.dailyLogTimeHHMM = '21:00',
  });

  static const Map<String, String> defaultMealTimes = {
    'breakfast': '08:00',
    'lunch': '13:00',
    'dinner': '19:00',
    'snack': '16:00',
  };

  static const Map<String, bool> defaultMealEnabled = {
    'breakfast': true,
    'lunch': true,
    'dinner': true,
    'snack': true,
  };

  String mealTimeFor(String slotKey, {String fallback = '12:00'}) {
    return mealTimes[slotKey] ?? defaultMealTimes[slotKey] ?? fallback;
  }

  bool isMealEnabled(String slotKey) {
    if (!mealRemindersEnabled) return false;
    return mealEnabled[slotKey] ?? true;
  }

  NotificationSettings copyWith({
    bool? mealRemindersEnabled,
    Map<String, String>? mealTimes,
    Map<String, bool>? mealEnabled,
    bool? fastingGoalReachedEnabled,
    bool? fastingScheduleRemindersEnabled,
    bool? supplementRemindersEnabled,
    bool? postWorkoutSupplementEnabled,
    bool? activeWorkoutBannerEnabled,
    bool? restTimerAlertsEnabled,
    bool? dailyLogReminderEnabled,
    String? dailyLogTimeHHMM,
  }) {
    return NotificationSettings(
      mealRemindersEnabled:
          mealRemindersEnabled ?? this.mealRemindersEnabled,
      mealTimes: mealTimes ?? this.mealTimes,
      mealEnabled: mealEnabled ?? this.mealEnabled,
      fastingGoalReachedEnabled:
          fastingGoalReachedEnabled ?? this.fastingGoalReachedEnabled,
      fastingScheduleRemindersEnabled:
          fastingScheduleRemindersEnabled ??
          this.fastingScheduleRemindersEnabled,
      supplementRemindersEnabled:
          supplementRemindersEnabled ?? this.supplementRemindersEnabled,
      postWorkoutSupplementEnabled:
          postWorkoutSupplementEnabled ?? this.postWorkoutSupplementEnabled,
      activeWorkoutBannerEnabled:
          activeWorkoutBannerEnabled ?? this.activeWorkoutBannerEnabled,
      restTimerAlertsEnabled:
          restTimerAlertsEnabled ?? this.restTimerAlertsEnabled,
      dailyLogReminderEnabled:
          dailyLogReminderEnabled ?? this.dailyLogReminderEnabled,
      dailyLogTimeHHMM: dailyLogTimeHHMM ?? this.dailyLogTimeHHMM,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mealRemindersEnabled': mealRemindersEnabled,
      'mealTimes': mealTimes,
      'mealEnabled': mealEnabled,
      'fastingGoalReachedEnabled': fastingGoalReachedEnabled,
      'fastingScheduleRemindersEnabled': fastingScheduleRemindersEnabled,
      'supplementRemindersEnabled': supplementRemindersEnabled,
      'postWorkoutSupplementEnabled': postWorkoutSupplementEnabled,
      'activeWorkoutBannerEnabled': activeWorkoutBannerEnabled,
      'restTimerAlertsEnabled': restTimerAlertsEnabled,
      'dailyLogReminderEnabled': dailyLogReminderEnabled,
      'dailyLogTimeHHMM': dailyLogTimeHHMM,
    };
  }

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      mealRemindersEnabled: json['mealRemindersEnabled'] as bool? ?? true,
      mealTimes: json['mealTimes'] is Map
          ? (json['mealTimes'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )
          : defaultMealTimes,
      mealEnabled: json['mealEnabled'] is Map
          ? (json['mealEnabled'] as Map).map(
              (k, v) => MapEntry(k.toString(), v as bool? ?? true),
            )
          : defaultMealEnabled,
      fastingGoalReachedEnabled:
          json['fastingGoalReachedEnabled'] as bool? ?? true,
      fastingScheduleRemindersEnabled:
          json['fastingScheduleRemindersEnabled'] as bool? ?? true,
      supplementRemindersEnabled:
          json['supplementRemindersEnabled'] as bool? ?? true,
      postWorkoutSupplementEnabled:
          json['postWorkoutSupplementEnabled'] as bool? ?? true,
      activeWorkoutBannerEnabled:
          json['activeWorkoutBannerEnabled'] as bool? ?? true,
      restTimerAlertsEnabled:
          json['restTimerAlertsEnabled'] as bool? ?? true,
      dailyLogReminderEnabled:
          json['dailyLogReminderEnabled'] as bool? ?? false,
      dailyLogTimeHHMM:
          json['dailyLogTimeHHMM'] as String? ?? '21:00',
    );
  }

  static NotificationSettings fromRawJson(String? raw) {
    if (raw == null || raw.isEmpty) return const NotificationSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return NotificationSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return NotificationSettings.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return const NotificationSettings();
  }

  String toRawJson() => jsonEncode(toJson());
}
