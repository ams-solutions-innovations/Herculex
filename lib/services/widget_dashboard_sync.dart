import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/providers.dart';
import '../core/units.dart';
import '../features/analytics/presentation/analytics_providers.dart';
import '../features/dashboard/presentation/dashboard_providers.dart';
import '../features/health/domain/cycle_adjuster.dart';
import '../features/health/presentation/cycle_providers.dart';
import '../features/nutrition/domain/daily_totals.dart';
import '../features/nutrition/presentation/goals_providers.dart';
import '../features/nutrition/presentation/nutrition_providers.dart';
import '../features/nutrition/presentation/widgets/macro_chart.dart';
import '../features/recovery/domain/training_suggestion.dart';
import '../features/recovery/presentation/recovery_providers.dart';
import '../features/supplements/domain/supplement.dart';
import '../features/supplements/presentation/supplement_providers.dart';
import '../features/workouts/presentation/workouts_providers.dart';
import '../theme/colors.dart';
import 'widget_sync_service.dart';

// Feeds the training, body and habit home-screen widgets (design "2a") from
// the same providers as their dashboard cards. Each controller rebuilds when
// its sources change and pushes a display-ready payload; WidgetSyncService
// drops payloads that haven't changed.

final _widgetSyncProvider = Provider<WidgetSyncService>((ref) => WidgetSyncService());

/// Watches every 2a widget controller; watched once from the app root.
final widgetDashboardSyncControllerProvider = Provider<void>((ref) {
  ref.watch(_planSync);
  ref.watch(_weekSync);
  ref.watch(_bodyweightSync);
  ref.watch(_streakSync);
  ref.watch(_prsSync);
  ref.watch(_volumeSync);
  ref.watch(_nextFocusSync);
  ref.watch(_supplementsSync);
  ref.watch(_miniWorkoutSync);
  ref.watch(_intakeSync);
  ref.watch(_cycleSync);
});

String _categoryLabel(MuscleCategory c) => switch (c) {
  MuscleCategory.push => 'Push',
  MuscleCategory.pull => 'Pull',
  MuscleCategory.legs => 'Legs',
  MuscleCategory.core => 'Core',
};

/// The split a program day trains, guessed from its name ("Leg Day",
/// "Push A"), so its readiness can be badged. Null when the name says nothing.
MuscleCategory? _categoryForDay(String name) {
  final n = name.toLowerCase();
  if (n.contains('leg') || n.contains('lower')) return MuscleCategory.legs;
  if (n.contains('push')) return MuscleCategory.push;
  if (n.contains('pull')) return MuscleCategory.pull;
  if (n.contains('core') || n.contains('abs')) return MuscleCategory.core;
  return null;
}

final _planSync = Provider<void>((ref) {
  final async = ref.watch(todaysScheduledWorkoutProvider);
  if (!async.hasValue) return;
  final workout = async.value;
  final suggestion = ref.watch(nextWorkoutTrainingSuggestionProvider).valueOrNull;

  final Map<String, Object?> data;
  if (workout == null) {
    data = {
      'state': 'none',
      'title': 'Rest day',
      'subtitle': 'No workout scheduled',
      'badge': null,
      'button': 'Open workouts',
    };
  } else {
    final name = workout.programDay.name;
    final count = workout.exerciseCount;
    final exercises = '$count ${count == 1 ? 'exercise' : 'exercises'}';
    final category = _categoryForDay(name);
    final readiness = category == null ? null : suggestion?.allCategoryScores[category];
    data = workout.isDone
        ? {
            'state': 'done',
            'title': name,
            'subtitle': 'Completed today',
            'badge': null,
            'button': 'View workouts',
          }
        : workout.isInProgress
        ? {
            'state': 'active',
            'title': name,
            'subtitle': '$exercises · in progress',
            'badge': null,
            'button': 'Resume workout',
          }
        : {
            'state': 'ready',
            'title': name,
            'subtitle': '$exercises planned',
            'badge': readiness == null || readiness <= 0
                ? null
                : '${_categoryLabel(category!)} ${readiness.round()}% ready',
            'button': 'Start $name',
          };
  }
  ref.read(_widgetSyncProvider).syncWidgetData('plan', data);
});

final _weekSync = Provider<void>((ref) {
  final now = ref.watch(clockProvider).now();
  final today = DateTime(now.year, now.month, now.day);
  final days = ref.watch(weekCalendarSummaryProvider(today)).valueOrNull;
  if (days == null) return;
  const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  ref.read(_widgetSyncProvider).syncWidgetData('week', {
    'days': [
      for (final d in days)
        {
          'label': labels[d.date.weekday - 1],
          'day': d.date.day,
          'today': d.isToday,
          'done': d.completedSessions.any((s) => s.endedAt != null),
          'scheduled': d.hasScheduled,
        },
    ],
  });
});

final _bodyweightSync = Provider<void>((ref) {
  final history = ref.watch(bodyweightHistoryProvider).valueOrNull;
  if (history == null) return;
  final fmt = ref.watch(weightFormatProvider);
  final profile = ref.watch(profileProvider).valueOrNull;
  final targetKg = profile?.targetWeightKg ?? ref.watch(goalWeightProvider);
  if (history.isEmpty) {
    ref.read(_widgetSyncProvider).syncWidgetData('bodyweight', null);
    return;
  }
  final latest = history.last;
  final date = DateTime.tryParse(latest.dateIso);
  final recent = history.length > 8 ? history.sublist(history.length - 8) : history;
  ref.read(_widgetSyncProvider).syncWidgetData('bodyweight', {
    'value': fmt.formatValue(latest.value),
    'unit': date == null ? fmt.suffix : '${fmt.suffix} · ${DateFormat.MMMd().format(date)}',
    // Shape only: series and target stay in kg so they share one scale.
    'series': [for (final r in recent) r.value],
    'target': targetKg,
  });
});

final _streakSync = Provider<void>((ref) {
  final workouts = ref.watch(workoutStreakProvider);
  final logging = ref.watch(nutritionStreakProvider);
  final sync = ref.read(_widgetSyncProvider);
  sync.syncWidgetData('streak_workouts', {
    'current': workouts.current,
    'unit': workouts.current == 1 ? 'week' : 'weeks',
    'activeToday': workouts.activeToday,
  });
  sync.syncWidgetData('streak_logging', {
    'current': logging.current,
    'unit': logging.current == 1 ? 'day' : 'days',
    'activeToday': logging.activeToday,
  });
});

final _prsSync = Provider<void>((ref) {
  final prs = ref.watch(topOneRmsProvider).valueOrNull;
  if (prs == null) return;
  final fmt = ref.watch(weightFormatProvider);
  ref.read(_widgetSyncProvider).syncWidgetData('prs', {
    'unit': fmt.suffix,
    'items': [
      for (final pr in prs.take(3))
        {'name': pr.exerciseName, 'value': fmt.formatValue(pr.estimatedOneRmKg, decimals: 0)},
    ],
  });
});

final _volumeSync = Provider<void>((ref) {
  final volume = ref.watch(weeklyMuscleVolumeProvider).valueOrNull;
  if (volume == null) return;
  ref.read(_widgetSyncProvider).syncWidgetData('volume', {'sets': volume.totalSets});
});

final _nextFocusSync = Provider<void>((ref) {
  final s = ref.watch(nextWorkoutTrainingSuggestionProvider).valueOrNull;
  if (s == null) return;
  // No logged training yet: every category scores 0, so there's no focus.
  final hasData = s.allCategoryScores.values.any((v) => v > 0);
  ref.read(_widgetSyncProvider).syncWidgetData('next_focus', {
    'category': hasData ? _categoryLabel(s.bestCategory) : null,
    'fresh': s.readyMuscles.length,
  });
});

final _supplementsSync = Provider<void>((ref) {
  final state = ref.watch(supplementDayStateProvider).valueOrNull;
  if (state == null) return;
  String detail(Supplement s) => switch (s.schedule) {
    SupplementSchedule.time => s.timeHHMM ?? '',
    SupplementSchedule.postWorkout => 'Post-wo',
    SupplementSchedule.none => s.doseLabel ?? '',
  };
  ref.read(_widgetSyncProvider).syncWidgetData('supplements', {
    'taken': state.takenCount,
    'total': state.totalCount,
    'items': [
      for (final s in state.supplements.take(6))
        {'name': s.name, 'detail': detail(s), 'taken': state.isTaken(s.id)},
    ],
  });
});

final _miniWorkoutSync = Provider<void>((ref) {
  final today = ref.watch(microWorkoutsTodayProvider).valueOrNull;
  if (today == null) return;
  if (today.isEmpty) {
    ref.read(_widgetSyncProvider).syncWidgetData('mini', null);
    return;
  }
  // The next one still to do; once all are done, the first shows "Done".
  final next = today.where((m) => !m.doneForToday).firstOrNull ?? today.first;
  ref.read(_widgetSyncProvider).syncWidgetData('mini', {
    'id': '${next.microWorkout.id}',
    'name': next.microWorkout.name,
    'done': next.completedToday,
    'total': next.microWorkout.timesPerDay,
  });
});

final _intakeSync = Provider<void>((ref) {
  final history = ref.watch(nutritionHistoryProvider).valueOrNull;
  if (history == null) return;
  final avg = ref.watch(averageWeeklyCaloriesProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final targets =
      ref.watch(effectiveTargetsProvider(today)).valueOrNull ?? ref.watch(baselineTargetsProvider);
  ref.read(_widgetSyncProvider).syncWidgetData('intake', {
    'value': avg == null ? null : NumberFormat.decimalPattern().format(avg.round()),
    'unit': 'kcal/day',
    // Same 7 days as the dashboard's trend preview, oldest first.
    'series': [
      for (var i = 6; i >= 0; i--)
        macroValueForTotals(
          history[DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: i)))] ??
              DailyTotals.empty,
          'kcal',
        ),
    ],
    'target': targets?.kcal,
  });
});

final _cycleSync = Provider<void>((ref) {
  final settings = ref.watch(cycleSettingsStreamProvider);
  if (!settings.hasValue) return;
  if (settings.value == null) {
    ref.read(_widgetSyncProvider).syncWidgetData('cycle', null);
    return;
  }
  final a = ref.watch(cycleAdjustmentProvider).valueOrNull;
  if (a == null) return;
  // Same phase colours as CycleFocusCard.
  final Color color = switch (a.phase) {
    CyclePhase.menstrual => Colors.redAccent,
    CyclePhase.follicular => Colors.orangeAccent,
    CyclePhase.ovulatory => Colors.purpleAccent,
    CyclePhase.luteal => AppColors.primary,
  };
  final pct = ((a.volumeFactor - 1) * 100).round();
  final tip = a.trainingRecommendation;
  final firstSentence = tip.contains('. ') ? '${tip.substring(0, tip.indexOf('. '))}.' : tip;
  ref.read(_widgetSyncProvider).syncWidgetData('cycle', {
    'phase': a.phase.id,
    'title': a.phase.title.replaceAll(' Phase', ''),
    'badge': a.isManualOverride ? 'OVERRIDE' : 'DAY ${a.dayOfCycle + 1}',
    'tip': firstSentence,
    'footer': pct > 0
        ? '+$pct% volume'
        : pct < 0
        ? '−${-pct}% volume'
        : a.phase.subtitle,
    'color': color.toARGB32(),
  });
});
