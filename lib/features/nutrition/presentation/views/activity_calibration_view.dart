import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/error/error_log.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/components/hx_screen_shell.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_calibration_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/data/tdee_inputs_repository.dart';
import 'package:herculex/features/nutrition/domain/activity_reset_policy.dart';
import 'package:herculex/features/nutrition/domain/tdee_calibration_series.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate_copy.dart';
import 'package:herculex/features/nutrition/domain/tdee_progress.dart';
import 'package:herculex/features/nutrition/presentation/widgets/calibration_charts.dart';
import 'package:herculex/features/nutrition/presentation/widgets/calibration_explainer.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/profile/presentation/widgets/activity_level_section.dart';

/// Shortest and longest span the charts show, in days.
const int _kMinChartDays = 14;
const int _kMaxChartDays = 35;
const int _kDefaultChartDays = 28;

const String _kTrustFootnote =
    'This is an estimate, not a medical measurement. '
    'It never changes a target you set yourself.';

/// Opened from the Profile activity-level badge: how the maintenance estimate
/// is worked out, what it is using right now, and how it has moved.
///
/// Read-only apart from the level picker, which goes through the same reset
/// flow as Profile. Nothing here writes estimates or targets.
class ActivityCalibrationView extends ConsumerWidget {
  const ActivityCalibrationView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimate = ref.watch(tdeeEstimateProvider);
    final profile = ref.watch(profileProvider).asData?.value;
    final asOf = ref.watch(clockProvider).now();

    return HxScreenShell(
      title: 'Calibration',
      titleIcon: Icons.insights_rounded,
      children: [
        const SizedBox(height: HxSpace.x4),
        if (estimate == null)
          const _NeedsProfileCard()
        else ...[
          CalibrationStatusCard(estimate: estimate, asOf: asOf),
          const SizedBox(height: HxSpace.x4),
          CalibrationMethodCard(estimate: estimate, profile: profile),
          const SizedBox(height: HxSpace.x4),
          _History(ref: ref),
          const SizedBox(height: HxSpace.x4),
          ..._logCharts(ref, estimate, asOf),
          const SizedBox(height: HxSpace.x4),
          if (profile != null) _ChangeLevelButton(profile: profile),
        ],
        const SizedBox(height: HxSpace.x4),
        Text(
          _kTrustFootnote,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: context.hx.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HxSpace.x8),
      ],
    );
  }

  /// Weight trend, daily intake and the "what is missing" checklist, which all
  /// read the same 60 days of logs.
  List<Widget> _logCharts(
    WidgetRef ref,
    TdeeEstimateResult estimate,
    DateTime asOf,
  ) {
    final inputs = ref.watch(tdeeCalibrationInputsProvider);
    return inputs.when(
      loading: () => const [_InlineMessage.loading()],
      error: (e, st) {
        ErrorLog.instance.record(
          e,
          source: 'tdee',
          stack: st,
          details: 'calibration inputs read failed',
        );
        return const [_InlineMessage('Could not load your logs.')];
      },
      data: (data) {
        final series = _series(data, estimate, asOf);
        return [
          WeightTrendChart(series: series),
          const SizedBox(height: HxSpace.x4),
          IntakeChart(series: series),
          if (estimate.method != TdeeMethod.observed || estimate.isHeld) ...[
            const SizedBox(height: HxSpace.x4),
            CalibrationProgressCard(
              progress: CalibrationProgress.evaluate(
                asOf: asOf,
                foodLoggedDays: data.foodLoggedDays,
                weightLogs: data.weightLogs,
              ),
            ),
          ],
        ];
      },
    );
  }

  CalibrationSeries _series(
    TdeeInputs data,
    TdeeEstimateResult estimate,
    DateTime asOf,
  ) {
    final observed = estimate.method == TdeeMethod.observed
        ? tdeeObservedDays(estimate)
        : null;
    final days = (observed ?? _kDefaultChartDays).clamp(
      _kMinChartDays,
      _kMaxChartDays,
    );
    return CalibrationSeries.build(
      asOf: asOf,
      days: days,
      weightLogs: data.weightLogs,
      dailyKcalByDate: data.dailyKcalByDate,
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(tdeeEstimateHistoryProvider);
    return history.when(
      loading: () => const _InlineMessage.loading(),
      error: (e, st) {
        ErrorLog.instance.record(
          e,
          source: 'tdee',
          stack: st,
          details: 'estimate history read failed',
        );
        return const _InlineMessage('Could not load your estimate history.');
      },
      data: (rows) => EstimateHistoryChart(history: rows),
    );
  }
}

class _ChangeLevelButton extends ConsumerWidget {
  const _ChangeLevelButton({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestTdeeEstimateProvider).asData?.value;
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('calibration_change_level'),
        icon: Icon(activityLevelIcons[profile.activityLevel], size: 18),
        label: Text('Activity level: ${profile.activityLevel.label}'),
        onPressed: () => pickAndApplyActivityLevel(
          context,
          selected: profile.activityLevel,
          calibrated: ActivityResetPolicy.isCalibrated(latest),
          measured: ActivityResetPolicy.isMeasured(latest),
          onChanged: (level) => ref
              .read(localProfileRepositoryProvider)
              .save(profile.copyWith(activityLevel: level)),
        ),
      ),
    );
  }
}

class _NeedsProfileCard extends StatelessWidget {
  const _NeedsProfileCard();

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxCard(
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, color: hx.onSurfaceVariant),
          const SizedBox(width: HxSpace.x3),
          Expanded(
            child: Text(
              'Add your weight, height and age in Profile and the app starts '
              'estimating your maintenance calories.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage(this.message) : _loading = false;
  const _InlineMessage.loading() : message = '', _loading = true;

  final String message;
  final bool _loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: _loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.hx.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
