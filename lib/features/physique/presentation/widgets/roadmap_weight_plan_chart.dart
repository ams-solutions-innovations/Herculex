import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/application/physique_schedule_provider.dart';
import 'package:herculex/features/physique/domain/roadmap_schedule.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';
import 'package:intl/intl.dart' show DateFormat;

/// The whole roadmap as one weight chart: a band per phase, the planned line,
/// your weigh-ins on top, and where today falls.
class RoadmapWeightPlanChart extends ConsumerWidget {
  const RoadmapWeightPlanChart({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final schedule = ref.watch(physiqueRoadmapScheduleProvider(goalId));
    if (schedule == null ||
        schedule.isEmpty ||
        schedule.phases.every((p) => p.endKg == null)) {
      return const SizedBox.shrink();
    }
    final wf = ref.watch(weightFormatProvider);
    final logs =
        ref.watch(physiqueWeightLogsProvider).asData?.value ?? const [];
    final now = ref.watch(clockProvider).now();
    final start = schedule.startDate!;
    final actual = [
      for (final l in logs)
        if (!l.date.isBefore(start) && !l.date.isAfter(now)) l,
    ];
    final legend = TextStyle(
      color: hx.secondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: physiqueCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Expanded(child: PhysiqueEyebrow('WEIGHT PLAN')),
                Container(width: 14, height: 2, color: hx.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('Plan', style: legend),
                const SizedBox(width: 10),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: hx.primaryText,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text('You', style: legend),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 170,
            child: CustomPaint(
              painter: _PlanPainter(
                schedule: schedule,
                actual: actual,
                now: now,
                wf: wf,
                hx: hx,
                labelStyle: TextStyle(
                  color: hx.tertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: Theme.of(
                    context,
                  ).textTheme.labelSmall?.fontFamily,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({
    required this.schedule,
    required this.actual,
    required this.now,
    required this.wf,
    required this.hx,
    required this.labelStyle,
  });

  final RoadmapSchedule schedule;
  final List<WeightLog> actual;
  final DateTime now;
  final WeightFormat wf;
  final HxColors hx;
  final TextStyle labelStyle;

  TextPainter _text(String s, TextStyle style) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  void _dashed(Canvas canvas, List<Offset> pts, Paint paint) {
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final length = (b - a).distance;
      if (length == 0) continue;
      final dir = (b - a) / length;
      for (var d = 0.0; d < length; d += 9) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 5, length), paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final phases = schedule.phases;
    final start = schedule.startDate!;
    final end = schedule.endDate!;
    const left = 30.0;
    const top = 8.0;
    final plotBottom = size.height - 34;
    final stripY = plotBottom + 10;
    final span = math.max(1, end.difference(start).inDays).toDouble();
    double x(DateTime d) =>
        left +
        (size.width - left) *
            (d.difference(start).inDays / span).clamp(0.0, 1.0);

    final planPts = <(DateTime, double)>[];
    for (final p in phases) {
      if (p.startKg != null) planPts.add((p.startDate, p.startKg!));
      if (p.endKg != null) planPts.add((p.endDate, p.endKg!));
    }
    final values = [
      for (final p in planPts) p.$2,
      for (final l in actual) l.kg,
    ];
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    final pad = (hi - lo) < 1 ? 1.0 : (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    double y(double kg) =>
        top + (plotBottom - top) * (1 - (kg - lo) / (hi - lo));

    // Phase bands, alternating, and their colour strips below the plot.
    for (var i = 0; i < phases.length; i++) {
      final p = phases[i];
      final x0 = x(p.startDate), x1 = x(p.endDate);
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTRB(x0, top, x1, plotBottom),
          Paint()..color = hx.onSurface.withValues(alpha: 0.025),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, stripY, math.max(x0, x1 - 2), stripY + 6),
          const Radius.circular(3),
        ),
        Paint()..color = physiquePhaseColor(p.phase, hx),
      );
    }

    // Three gridlines with their weights.
    final grid = Paint()..color = hx.surfaceVariant;
    for (final t in const [0.15, 0.5, 0.85]) {
      final kg = hi - (hi - lo) * t;
      final gy = y(kg);
      canvas.drawLine(Offset(left, gy), Offset(size.width, gy), grid);
      final label = _text(wf.formatValue(kg, decimals: 0), labelStyle);
      label.paint(canvas, Offset(0, gy - label.height / 2));
    }

    // Planned line.
    final plan = [for (final p in planPts) Offset(x(p.$1), y(p.$2))];
    _dashed(
      canvas,
      plan,
      Paint()
        ..color = hx.onSurfaceVariant
        ..strokeWidth = 2,
    );
    if (plan.isNotEmpty) {
      canvas.drawCircle(plan.last, 5, Paint()..color = hx.primary);
    }

    // Your weigh-ins.
    final you = [for (final l in actual) Offset(x(l.date), y(l.kg))];
    if (you.length > 1) {
      final path = Path()..moveTo(you.first.dx, you.first.dy);
      for (final o in you.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = hx.primaryText
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    if (you.length < 40) {
      for (final o in you) {
        canvas.drawCircle(o, 3, Paint()..color = hx.primaryText);
      }
    }

    // Today.
    final inRange = !now.isBefore(start) && now.isBefore(end);
    final tx = x(now);
    if (inRange) {
      canvas.drawLine(
        Offset(tx, top),
        Offset(tx, plotBottom),
        Paint()
          ..color = hx.onSurface
          ..strokeWidth = 1.5,
      );
      final todayKg = actual.isNotEmpty
          ? actual.last.kg
          : schedule.weightAt(now);
      if (todayKg != null) {
        final c = Offset(tx, y(todayKg));
        canvas.drawCircle(c, 5.5, Paint()..color = hx.onSurface);
        canvas.drawCircle(
          c,
          5.5,
          Paint()
            ..color = hx.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }

    // Axis labels: start, today and end.
    final labelY = size.height - 13;
    final first = _text(DateFormat('MMM').format(start), labelStyle);
    first.paint(canvas, Offset(left, labelY));
    final last = _text(DateFormat('MMM').format(end), labelStyle);
    last.paint(canvas, Offset(size.width - last.width, labelY));
    if (inRange) {
      final today = _text(
        'Today',
        labelStyle.copyWith(color: hx.onSurface, fontWeight: FontWeight.w800),
      );
      final lx = (tx - today.width / 2).clamp(
        left + first.width + 6,
        size.width - last.width - today.width - 6,
      );
      today.paint(canvas, Offset(lx, labelY));
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) =>
      old.schedule != schedule ||
      old.actual != actual ||
      old.now != now ||
      old.hx != hx;
}
