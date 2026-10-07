import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/components/hx_stat_tile.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_display_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:intl/intl.dart';

/// Accent colour and icon for a badge state (28-UI-SPEC "Badge state colours").
///
/// Shared by the inline badge and this sheet so the two never drift apart.
/// The accent decorates icons, borders and tints only, never body text.
({Color accent, IconData icon}) tdeeBadgeVisuals(
  HxColors hx,
  TdeeBadgeState state,
) => switch (state) {
  TdeeBadgeState.measured => (accent: hx.success, icon: Icons.insights_rounded),
  TdeeBadgeState.measuredAging => (
    accent: hx.warning,
    icon: Icons.insights_rounded,
  ),
  TdeeBadgeState.classified => (
    accent: hx.primary,
    icon: Icons.directions_run_rounded,
  ),
  TdeeBadgeState.calibrating => (
    accent: hx.onSurfaceVariant,
    icon: Icons.hourglass_top_rounded,
  ),
};

/// Opens the read-only maintenance estimate detail sheet.
Future<void> showTdeeEstimateSheet(BuildContext context) {
  return HxSheet.show<void>(context, builder: (_) => const TdeeEstimateSheet());
}

/// Below this content width the two comparison tiles stack vertically:
/// `HxStatTile` cannot fit its uppercase label beside the icon bubble in a
/// half-width slot any narrower.
const double _kStackTilesBelow = 400;

const String _kTrustFootnote =
    'This is an estimate, not a medical measurement. '
    'It never changes a target you set yourself.';

/// Read-only detail for the current maintenance estimate (D-05 to D-07):
/// method, confidence, window and the inputs it used. It has no write path;
/// accepting or dismissing an estimate belongs to a later phase.
class TdeeEstimateSheet extends ConsumerWidget {
  const TdeeEstimateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimate = ref.watch(tdeeEstimateProvider);
    final saved = ref.watch(savedTargetForTodayProvider).asData?.value;
    final asOf = ref.watch(clockProvider).now();

    return HxSheet(
      title: 'Maintenance estimate',
      scrollable: true,
      initialSize: 0.6,
      maxSize: 0.92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (estimate != null) ..._details(context, estimate, saved, asOf),
          const _Footnote(_kTrustFootnote),
        ],
      ),
    );
  }

  List<Widget> _details(
    BuildContext context,
    TdeeEstimateResult estimate,
    TargetRule? saved,
    DateTime asOf,
  ) {
    final state = estimate.badgeState;
    final visuals = tdeeBadgeVisuals(context.hx, state);
    final used = _usedRows(estimate, asOf);
    final alsoRecorded = state == TdeeBadgeState.classified
        ? _alsoRecordedRows(estimate)
        : const <_Row>[];
    final window = _windowLines(estimate, asOf);

    return [
      _StatusRow(
        icon: visuals.icon,
        accent: visuals.accent,
        label: state.label(estimate.confidence),
        methodLine: _methodLine(estimate, asOf),
      ),
      const SizedBox(height: HxSpace.x6),
      _Comparison(
        estimateKcal: estimate.kcal,
        estimateAccent: visuals.accent,
        saved: saved,
      ),
      if (window.isNotEmpty) ...[
        const SizedBox(height: HxSpace.x6),
        const _SectionHeader('WINDOW'),
        const SizedBox(height: HxSpace.x2),
        for (final line in window) line,
      ],
      if (used.isNotEmpty) ...[
        const SizedBox(height: HxSpace.x6),
        const _SectionHeader('WHAT WE USED'),
        const SizedBox(height: HxSpace.x2),
        HxCard(
          key: const ValueKey('tdee_used_card'),
          padding: const EdgeInsets.all(HxSpace.x4),
          radius: HxRadius.md,
          child: _RowList(used),
        ),
      ],
      if (alsoRecorded.isNotEmpty) ...[
        const SizedBox(height: HxSpace.x4),
        Column(
          key: const ValueKey('tdee_also_recorded'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Caption('Also recorded (not used in the estimate)'),
            const SizedBox(height: HxSpace.x2),
            _RowList(alsoRecorded),
          ],
        ),
      ],
      if (estimate.method == TdeeMethod.coldStart) ...[
        const SizedBox(height: HxSpace.x4),
        const _Caption(
          'Log food and your weight for about two weeks and this switches '
          'to a measured number automatically.',
        ),
      ],
      const SizedBox(height: HxSpace.x6),
    ];
  }

  String _methodLine(TdeeEstimateResult e, DateTime asOf) {
    switch (e.method) {
      case TdeeMethod.observed:
        if (e.isHeld) {
          final when = _relativeDay(_measuredAt(e), asOf);
          return 'Measured from your logs $when. Log again to refresh it.';
        }
        return 'Worked out from what you ate and how your weight trended.';
      case TdeeMethod.classifier:
        return 'Worked out from your daily activity and training.';
      case TdeeMethod.coldStart:
        return 'Using the activity level you chose at setup until there is '
            'enough data to measure.';
    }
  }

  DateTime _measuredAt(TdeeEstimateResult e) {
    final raw = e.inputs['measured_at'];
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    return parsed?.toLocal() ?? e.estimatedAt;
  }

  /// Days the observed data actually covers: the persisted measured span plus
  /// one (both ends inclusive). Null when the span is missing or malformed;
  /// the winning candidate window is a selection detail and is never shown.
  int? _observedDays(TdeeEstimateResult e) {
    final span = e.inputs['span_days'];
    return span is num ? span.round() + 1 : null;
  }

  List<Widget> _windowLines(TdeeEstimateResult e, DateTime asOf) {
    if (e.method == TdeeMethod.coldStart) return const [];
    final days = e.method == TdeeMethod.observed
        ? _observedDays(e)
        : e.windowDays;
    return [
      if (days != null) _BodyLine('Based on the last $days days'),
      _BodyLine('Updated ${_relativeDay(e.estimatedAt, asOf)}', muted: true),
    ];
  }

  List<_Row> _usedRows(TdeeEstimateResult e, DateTime asOf) {
    final i = e.inputs;
    final ints = NumberFormat('#,##0');
    final one = NumberFormat('0.#');
    final signed = NumberFormat('+0.0;-0.0');
    final factor = NumberFormat('0.0##');

    String? whole(String key, String Function(String) wrap) {
      final v = i[key];
      return v is num ? wrap(ints.format(v.round())) : null;
    }

    final rows = <String, String?>{};
    switch (e.method) {
      case TdeeMethod.observed:
        final days = _observedDays(e);
        final logged = i['logged_days'];
        final trend = i['weight_trend_delta_kg'];
        rows['Average intake'] = whole(
          'mean_intake_kcal',
          (s) => '$s kcal/day',
        );
        rows['Days with food logged'] = days != null && logged is num
            ? '${logged.round()} of $days'
            : null;
        rows['Weight trend'] = trend is num
            ? '${signed.format(trend)} kg'
            : null;
        rows['Weigh-ins'] = whole('weigh_ins', (s) => s);
        if (e.isHeld) {
          rows['Last measured'] = _relativeDay(_measuredAt(e), asOf);
        }
      case TdeeMethod.classifier:
        final workouts = i['workouts_per_week'];
        rows['Average steps'] = whole('avg_steps', (s) => '$s/day');
        rows['Logged workouts'] = workouts is num
            ? '${one.format(workouts)}/week'
            : null;
        rows['Activity factor'] = i['activity_factor'] is num
            ? factor.format(i['activity_factor'])
            : null;
      case TdeeMethod.coldStart:
        final level = i['onboarding_level'];
        rows['Onboarding activity level'] = level is String ? level : null;
        rows['Activity factor'] = i['activity_factor'] is num
            ? factor.format(i['activity_factor'])
            : null;
    }
    return _present(rows);
  }

  /// Recorded by the classifier's snapshot but never part of its multiplier or
  /// confidence, so they are shown apart from the inputs it used.
  List<_Row> _alsoRecordedRows(TdeeEstimateResult e) {
    final i = e.inputs;
    final ints = NumberFormat('#,##0');
    final one = NumberFormat('0.#');
    final kcal = i['active_kcal'];
    final sleep = i['sleep_hours'];
    final hr = i['resting_hr'];
    return _present({
      'Active calories': kcal is num
          ? '${ints.format(kcal.round())} kcal/day'
          : null,
      'Sleep': sleep is num ? '${one.format(sleep)} h/night' : null,
      'Resting heart rate': hr is num ? '${hr.round()} bpm' : null,
    });
  }

  List<_Row> _present(Map<String, String?> rows) => [
    for (final entry in rows.entries)
      if (entry.value != null) _Row(entry.key, entry.value!),
  ];
}

/// "today", "yesterday" or "N days ago", by calendar day against [asOf].
String _relativeDay(DateTime at, DateTime asOf) {
  final days = DateTime(
    asOf.year,
    asOf.month,
    asOf.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

class _Row {
  const _Row(this.label, this.value);
  final String label;
  final String value;
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.methodLine,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String methodLine;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hx = context.hx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: HxSpace.x2),
            Expanded(
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: hx.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x1),
        Text(
          methodLine,
          style: text.bodyMedium?.copyWith(
            fontWeight: FontWeight.w400,
            color: hx.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The live estimate beside the user's saved manual target (D-07). Never a
/// delta: the saved target is phase-adjusted and the estimate is maintenance.
class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.estimateKcal,
    required this.estimateAccent,
    required this.saved,
  });

  final int estimateKcal;
  final Color estimateAccent;
  final TargetRule? saved;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final ints = NumberFormat('#,##0');
    final estimateTile = HxStatTile(
      key: const ValueKey('tdee_estimate_tile'),
      label: 'MAINTENANCE ESTIMATE',
      value: '${ints.format(estimateKcal)} kcal',
      icon: Icons.timeline_rounded,
      accent: estimateAccent,
    );
    final rule = saved;
    if (rule == null) return estimateTile;

    final savedTile = HxStatTile(
      key: const ValueKey('tdee_saved_tile'),
      label: 'YOUR SAVED TARGET',
      value: '${ints.format(rule.kcal)} kcal',
      icon: Icons.flag_rounded,
      accent: hx.onSurfaceVariant,
    );
    const manually = _Caption('set manually');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _kStackTilesBelow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  savedTile,
                  const SizedBox(height: HxSpace.x1),
                  manually,
                  const SizedBox(height: HxSpace.x4),
                  estimateTile,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      savedTile,
                      const SizedBox(height: HxSpace.x1),
                      manually,
                    ],
                  ),
                ),
                const SizedBox(width: HxSpace.x4),
                Expanded(child: estimateTile),
              ],
            );
          },
        ),
        const SizedBox(height: HxSpace.x2),
        const _Caption(
          'Your saved target includes any cut or bulk adjustment, so it can '
          'sit above or below maintenance on purpose.',
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.hx.secondary,
        letterSpacing: 1.0,
      ),
    );
  }
}

/// Label-size secondary text (12px, regular weight).
class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w400,
        color: context.hx.onSurfaceVariant,
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => _Caption(text);
}

class _BodyLine extends StatelessWidget {
  const _BodyLine(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        color: muted ? hx.onSurfaceVariant : hx.onSurface,
      ),
    );
  }
}

class _RowList extends StatelessWidget {
  const _RowList(this.rows);
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium;
    final hx = context.hx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var n = 0; n < rows.length; n++) ...[
          if (n > 0) const SizedBox(height: HxSpace.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rows[n].label,
                  style: text?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: hx.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Flexible(
                child: Text(
                  rows[n].value,
                  textAlign: TextAlign.end,
                  style: text?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: hx.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
