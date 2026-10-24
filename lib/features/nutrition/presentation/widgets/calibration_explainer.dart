import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate_copy.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimator.dart';
import 'package:herculex/features/nutrition/domain/tdee_progress.dart';
import 'package:herculex/features/nutrition/presentation/sheets/tdee_estimate_sheet.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:intl/intl.dart';

final NumberFormat _ints = NumberFormat('#,##0');
final NumberFormat _signedInts = NumberFormat('+#,##0;-#,##0');
final NumberFormat _factor = NumberFormat('0.0##');

Text _sectionLabel(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.labelSmall?.copyWith(
    color: context.hx.secondary,
    letterSpacing: 1.0,
  ),
);

TextStyle? _caption(BuildContext context) => Theme.of(context)
    .textTheme
    .labelSmall
    ?.copyWith(fontWeight: FontWeight.w400, color: context.hx.onSurfaceVariant);

// ── Status ───────────────────────────────────────────────────────────────────

/// The current estimate: number, how it was reached and how far to trust it.
class CalibrationStatusCard extends StatelessWidget {
  const CalibrationStatusCard({
    super.key,
    required this.estimate,
    required this.asOf,
  });

  final TdeeEstimateResult estimate;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    final state = estimate.badgeState;
    final visuals = tdeeBadgeVisuals(hx, state);
    final days = estimate.method == TdeeMethod.observed
        ? tdeeObservedDays(estimate)
        : estimate.windowDays;

    return HxCard(
      key: const ValueKey('calibration_status'),
      accent: visuals.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(visuals.icon, size: 20, color: visuals.accent),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: Text(
                  state.label(estimate.confidence),
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          Text(
            '${_ints.format(estimate.kcal)} kcal',
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text('maintenance per day', style: _caption(context)),
          const SizedBox(height: HxSpace.x3),
          Text(
            tdeeMethodLine(estimate, asOf),
            style: text.bodyMedium?.copyWith(color: hx.onSurfaceVariant),
          ),
          if (estimate.method != TdeeMethod.coldStart) ...[
            const SizedBox(height: HxSpace.x1),
            Text(
              [
                if (days != null) 'Based on the last $days days',
                'updated ${tdeeRelativeDay(estimate.estimatedAt, asOf)}',
              ].join(' · '),
              style: _caption(context),
            ),
          ],
        ],
      ),
    );
  }
}

// ── How it is calculated ─────────────────────────────────────────────────────

/// The three ways the app can work out maintenance, with the one in use
/// marked, and the sum behind the current number.
class CalibrationMethodCard extends StatelessWidget {
  const CalibrationMethodCard({
    super.key,
    required this.estimate,
    required this.profile,
  });

  final TdeeEstimateResult estimate;
  final Profile? profile;

  static const _steps = [
    (
      TdeeMethod.coldStart,
      'Starting estimate',
      'Your base metabolism (BMR) times the activity level you chose.',
    ),
    (
      TdeeMethod.classifier,
      'Classified',
      'Daily steps and logged workouts adjust the multiplier.',
    ),
    (
      TdeeMethod.observed,
      'Measured',
      'What you ate, minus what your weight did. The most accurate.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _steps.indexWhere((s) => s.$1 == estimate.method);
    return HxCard(
      key: const ValueKey('calibration_method'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'HOW IT IS CALCULATED'),
          const SizedBox(height: HxSpace.x3),
          for (var i = 0; i < _steps.length; i++)
            _LadderStep(
              title: _steps[i].$2,
              body: _steps[i].$3,
              done: i < current,
              current: i == current,
              last: i == _steps.length - 1,
            ),
          const SizedBox(height: HxSpace.x2),
          Text(
            'The app moves up these steps by itself as you log. You never '
            'pick one.',
            style: _caption(context),
          ),
          const SizedBox(height: HxSpace.x5),
          _sectionLabel(context, 'YOUR NUMBERS'),
          const SizedBox(height: HxSpace.x3),
          ..._formula(context),
        ],
      ),
    );
  }

  List<Widget> _formula(BuildContext context) {
    final i = estimate.inputs;
    switch (estimate.method) {
      case TdeeMethod.observed:
        final mean = i['mean_intake_kcal'];
        final delta = i['weight_trend_delta_kg'];
        final span = i['span_days'];
        if (mean is! num) return _unavailable(context);
        final fromWeight = estimate.kcal - mean.round();
        final kg = delta is num
            ? '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg'
            : null;
        return [
          _SumRow('Average intake', '${_ints.format(mean.round())} kcal'),
          _SumRow(
            'Energy from weight change',
            '${_signedInts.format(fromWeight)} kcal',
          ),
          _SumRow(
            'Maintenance',
            '${_ints.format(estimate.kcal)} kcal',
            total: true,
          ),
          const SizedBox(height: HxSpace.x2),
          Text(
            [
              if (kg != null && span is num)
                'Your weight trend moved $kg over ${span.round() + 1} days.',
              'A kilo of body weight is about '
                  '${_ints.format(TdeeTuning.kcalPerKg.round())} kcal. If you '
                  'lose weight you burned more than you ate, so the gap is '
                  'added back. If you gain, it is taken off.',
            ].join(' '),
            style: _caption(context),
          ),
        ];
      case TdeeMethod.classifier:
      case TdeeMethod.coldStart:
        final p = profile;
        final bmr = p == null ? null : MacroTargets.bmr(p);
        final factorRaw = i['activity_factor'];
        final factor = factorRaw is num
            ? factorRaw.toDouble()
            : (p == null ? null : MacroTargets.multiplierFor(p.activityLevel));
        if (bmr == null || factor == null) return _unavailable(context);
        final cold = estimate.method == TdeeMethod.coldStart;
        return [
          _SumRow('Base metabolism (BMR)', '${_ints.format(bmr.round())} kcal'),
          _SumRow(
            cold
                ? '× Activity factor (${p!.activityLevel.label})'
                : '× Activity factor (steps and workouts)',
            _factor.format(factor),
          ),
          _SumRow(
            'Maintenance',
            '${_ints.format(estimate.kcal)} kcal',
            total: true,
          ),
          const SizedBox(height: HxSpace.x2),
          Text(
            cold
                ? (p?.activityLevel == ActivityLevel.autocalibrator
                      ? 'Auto-calibrator active. Log food and your weight for about two weeks and this switches to a measured number automatically.'
                      : 'Log food and your weight for about two weeks and this switches to a measured number automatically.')
                : 'Keep logging food and weight and this switches to a '
                      'measured number automatically.',
            style: _caption(context),
          ),
        ];
    }
  }

  List<Widget> _unavailable(BuildContext context) => [
    Text(
      'Add your weight, height and age in Profile to see the sum.',
      style: _caption(context),
    ),
  ];
}

class _LadderStep extends StatelessWidget {
  const _LadderStep({
    required this.title,
    required this.body,
    required this.done,
    required this.current,
    required this.last,
  });

  final String title;
  final String body;
  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    final accent = current || done ? hx.primary : hx.outline;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current ? hx.primary : Colors.transparent,
                    border: Border.all(color: accent, width: 1.5),
                  ),
                  child: done
                      ? Icon(Icons.check_rounded, size: 16, color: accent)
                      : current
                      ? Icon(Icons.circle, size: 8, color: hx.onPrimary)
                      : null,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: hx.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: HxSpace.x3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: HxSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: current ? hx.primary : null,
                          ),
                        ),
                      ),
                      if (current) ...[
                        const SizedBox(width: HxSpace.x2),
                        Text('· in use now', style: _caption(context)),
                      ],
                    ],
                  ),
                  Text(
                    body,
                    style: text.bodySmall?.copyWith(color: hx.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow(this.label, this.value, {this.total = false});

  final String label;
  final String value;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme.bodyMedium;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: text?.copyWith(
                fontWeight: total ? FontWeight.w700 : FontWeight.w400,
                color: total ? hx.onSurface : hx.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: HxSpace.x2),
          Text(
            value,
            style: text?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    if (!total) return row;
    return Container(
      margin: const EdgeInsets.only(top: HxSpace.x1),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: hx.outlineVariant)),
      ),
      child: row,
    );
  }
}

// ── What is missing ──────────────────────────────────────────────────────────

/// Checklist of what the app still needs before it can measure maintenance.
class CalibrationProgressCard extends StatelessWidget {
  const CalibrationProgressCard({super.key, required this.progress});

  final CalibrationProgress progress;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxCard(
      key: const ValueKey('calibration_progress'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'WHAT IT NEEDS TO MEASURE'),
          const SizedBox(height: HxSpace.x3),
          for (final g in progress.gates) _GateRow(gate: g),
          const SizedBox(height: HxSpace.x1),
          Text(
            progress.allMet
                ? 'You have what the shortest window needs. The next '
                      'recalibration can switch you to a measured number.'
                : 'A guide for the shortest window (14 days). A longer one '
                      'is used automatically when your logs cover it.',
            style: _caption(context)?.copyWith(
              color: progress.allMet ? hx.success : hx.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GateRow extends StatelessWidget {
  const _GateRow({required this.gate});

  final CalibrationGate gate;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: HxSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                gate.met
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 18,
                color: gate.met ? hx.success : hx.outline,
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(child: Text(gate.label, style: text)),
              Text(
                '${gate.have.clamp(0, gate.need)} / ${gate.need}',
                style: text?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          ClipRRect(
            borderRadius: HxRadius.pillAll,
            child: LinearProgressIndicator(
              value: gate.fraction,
              minHeight: 4,
              color: gate.met ? hx.success : hx.primary,
              backgroundColor: hx.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
