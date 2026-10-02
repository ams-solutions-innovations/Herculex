import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_legacy_migrator.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';

const _poses = {'front', 'side', 'back'};

/// A check-in photo picked just before Android killed the activity. Carries
/// only what the sheet needs to resume at the privacy step.
class ResumedCapture {
  const ResumedCapture({
    required this.goalId,
    required this.pose,
    required this.path,
  });

  final int goalId;
  final String pose;
  final String path;

  /// Null unless [context] is a `physiqueCheckin` context with a valid int
  /// goal id and a known pose (a forged or stale context is ignored).
  static ResumedCapture? fromPending(
    PendingAiScanContext context,
    String path,
  ) {
    if (context.type != AiScanContextType.physiqueCheckin) return null;
    final goalId = context.extra?['goalId'];
    final pose = context.extra?['pose'];
    if (goalId is! int || pose is! String || !_poses.contains(pose)) {
      return null;
    }
    return ResumedCapture(goalId: goalId, pose: pose, path: path);
  }
}

final physiqueResumedCaptureProvider = StateProvider<ResumedCapture?>(
  (ref) => null,
);

/// What the check-in analysis needs to know about the user's current phase.
class CheckInFlowContext {
  const CheckInFlowContext({
    required this.phase,
    required this.weeksInPhase,
    this.weightKg,
    this.weeklyTrendKg,
  });

  final DietPhase phase;
  final int weeksInPhase;
  final double? weightKg;
  final double? weeklyTrendKg;
}

DietPhase _phaseOf(String name) {
  for (final p in DietPhase.values) {
    if (p.name == name) return p;
  }
  return DietPhase.maintain;
}

final physiqueCheckInContextProvider = Provider.family<CheckInFlowContext, int>(
  (ref, goalId) {
    final status = ref.watch(physiquePhaseStatusProvider(goalId));
    final logs =
        ref.watch(physiqueWeightLogsProvider).asData?.value ?? const [];
    final profileKg = ref.watch(profileProvider).asData?.value?.weightKg;
    final now = ref.watch(clockProvider).now();

    var phase = DietPhase.maintain;
    var weeks = 0;
    final current = status?.current;
    if (current != null) {
      phase = _phaseOf(current.phaseType);
      weeks = status?.evaluation?.weekInPhase ?? 0;
    } else if (status?.next != null) {
      phase = _phaseOf(status!.next!.phaseType);
    }

    final trend = logs.isEmpty
        ? null
        : WeightTrendRate.perWeekKg(TrendSeries.fromLogs(logs), now);
    return CheckInFlowContext(
      phase: phase,
      weeksInPhase: weeks,
      weightKg: logs.isEmpty ? profileKg : logs.last.kg,
      weeklyTrendKg: trend,
    );
  },
);

/// Copy for the one-time legacy migration SnackBar (D-08, UI-SPEC S9).
abstract final class LegacyMigrationNotice {
  static String? messageFor(LegacyMigrationResult? result) {
    if (result == null || !result.ran) return null;
    final parts = <String>[
      if (result.photosMigrated > 0)
        'Your progress photos now live in your private Dream Physique goal.',
      if (result.photosUnrecoverable > 0)
        "${result.photosUnrecoverable} older photos couldn't be recovered.",
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }
}
