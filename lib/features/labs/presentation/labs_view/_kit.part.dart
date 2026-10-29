part of '../labs_view.dart';

// Pieces shared by the Labs tabs and the finding screen, laid out after the
// "Workout, Finish & Labs" Claude Design prototype.

/// Space Grotesk, the display face the design uses for titles and numbers.
TextStyle _labsDisplay(
  double size, {
  FontWeight weight = FontWeight.w700,
  double letterSpacing = 0,
  double? height,
  Color? color,
}) => TextStyle(
  fontFamily: AppTheme.fontDisplay,
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: height,
  color: color,
);

/// The flat card most Labs blocks sit in.
BoxDecoration _labsCard(BuildContext context, {double radius = 22}) =>
    BoxDecoration(
      color: context.hx.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: context.hx.outlineVariant),
    );

/// The lead card of a tab: a brand glow from the top-right corner.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.child, this.padding = 20, this.radius = 28});

  final Widget child;
  final double padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: hx.primary.withValues(alpha: 0.35)),
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          stops: const [0, 0.35, 0.75],
          colors: [
            hx.primary.withValues(alpha: 0.35),
            hx.primary.withValues(alpha: 0.14),
            hx.surfaceContainerLowest,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Small all-caps label, optionally led by an icon ("ON-DEVICE ANALYSIS").
class _Kicker extends StatelessWidget {
  const _Kicker({required this.text, this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.hx.secondary;
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: c,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
    if (icon == null) return label;
    return Row(
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 6),
        Flexible(child: label),
      ],
    );
  }
}

/// A section heading with an optional quiet note on the right.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing, this.size = 22});

  final String title;
  final String? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: _labsDisplay(size))),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: context.hx.secondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// A rounded pill with tinted fill ("READY", "+6%").
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color, this.background});

  final String text;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.14),
        borderRadius: HxRadius.pillAll,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// How much a finding can carry. Exploratory signals are amber so they never
/// read like the descriptive changes beside them.
class _SupportBadge extends StatelessWidget {
  const _SupportBadge({required this.support});

  final String support;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final exploratory = support == 'Exploratory association';
    final label = switch (support) {
      'Descriptive change' => 'Descriptive',
      'Exploratory association' => 'Exploratory',
      'Collecting data' => 'Collecting',
      _ => support,
    };
    return _Pill(
      label,
      color: exploratory ? hx.warning : hx.onSurfaceVariant,
      background: exploratory
          ? hx.warning.withValues(alpha: 0.14)
          : hx.secondary.withValues(alpha: 0.14),
    );
  }
}

/// A small trend line ending in a dot.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    height: 48,
    child: CustomPaint(painter: _SparkPainter(values, color)),
  );
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(min), hi = values.reduce(max);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    const pad = 4.0;
    Offset at(int i) => Offset(
      i / (values.length - 1) * size.width,
      pad + (size.height - pad * 2) * (1 - (values[i] - lo) / span),
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.color != color || !listEquals(old.values, values);
}

/// Where an experiment stands: 14 baseline days, then 14 change days.
class _ExperimentPhase {
  const _ExperimentPhase({
    required this.label,
    required this.dayText,
    required this.baseline,
    required this.change,
    required this.inChange,
  });

  factory _ExperimentPhase.of(Map<String, dynamic> e, DateTime now) {
    final start = DateTime.parse(e['at'] as String);
    final baselineEnd = DateTime.parse(e['baselineEnd'] as String);
    final end = DateTime.parse(e['end'] as String);
    final stopped = e['status'] != 'active';
    final at = stopped && e['stoppedAt'] != null
        ? DateTime.parse(e['stoppedAt'] as String)
        : now;
    final baselineDays = max(1, baselineEnd.difference(start).inDays);
    final changeDays = max(1, end.difference(baselineEnd).inDays);
    double frac(DateTime from, int days) =>
        (at.difference(from).inHours / 24 / days).clamp(0.0, 1.0);
    final baseline = frac(start, baselineDays);
    final change = frac(baselineEnd, changeDays);
    final inChange = !at.isBefore(baselineEnd);
    final done = !at.isBefore(end);
    final String label;
    final String dayText;
    if (stopped) {
      label = 'Stopped';
      dayText = 'Stopped';
    } else if (done) {
      label = 'Ready to review';
      dayText = 'Review due';
    } else if (inChange) {
      label = 'Change phase';
      dayText = 'Day ${at.difference(baselineEnd).inDays + 1} / $changeDays';
    } else {
      label = 'Baseline';
      dayText = 'Day ${at.difference(start).inDays + 1} / $baselineDays';
    }
    return _ExperimentPhase(
      label: label,
      dayText: dayText,
      baseline: baseline,
      change: change,
      inChange: inChange,
    );
  }

  final String label;
  final String dayText;

  /// How far through each half, 0..1.
  final double baseline, change;
  final bool inChange;
}

/// Baseline and change as two tracks side by side, with an optional "today"
/// marker.
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.phase, this.height = 6, this.marker = false});

  final _ExperimentPhase phase;
  final double height;
  final bool marker;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final purple = hx.domainRecovery;
    Widget track(double fill, Color color) => Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: ColoredBox(
            color: hx.surfaceVariant,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fill,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
    final bar = Row(
      children: [
        track(phase.baseline, hx.outline),
        const SizedBox(width: 4),
        track(phase.change, purple),
      ],
    );
    if (!marker) return bar;
    return LayoutBuilder(
      builder: (context, box) {
        final half = (box.maxWidth - 4) / 2;
        final x = phase.inChange
            ? half + 4 + half * phase.change
            : half * phase.baseline;
        return SizedBox(
          height: height + 8,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              bar,
              Positioned(
                left: (x - 1.5).clamp(0.0, box.maxWidth - 3),
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: hx.onSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Icon and accent per finding. Associations get their own look so they are
/// never mistaken for a plain change.
(IconData, Color) _categoryStyle(LabsFinding f, HxColors hx) {
  if (f.q != null) return (Icons.hub_rounded, hx.primaryText);
  return switch (f.category) {
    LabsCategory.strength => (Icons.fitness_center_rounded, hx.primaryText),
    LabsCategory.training => (Icons.tune_rounded, hx.domainTraining),
    LabsCategory.techniques => (Icons.layers_rounded, hx.domainTraining),
    LabsCategory.supplements => (Icons.medication_rounded, hx.domainRecovery),
    LabsCategory.nutrition => (Icons.restaurant_rounded, hx.domainNutrition),
    LabsCategory.fasting => (Icons.timer_rounded, hx.domainFasting),
    LabsCategory.sleep => (Icons.bedtime_rounded, hx.domainRecovery),
    LabsCategory.physique => (Icons.accessibility_new_rounded, hx.primaryText),
    LabsCategory.context => (Icons.self_improvement_rounded, hx.warning),
  };
}

String _categoryLabel(LabsFinding f) =>
    f.q != null ? 'ASSOCIATION' : f.category.label.toUpperCase();

/// A value with its unit, trimmed to what the unit deserves.
String _num(double? value, String unit) {
  if (value == null) return '—';
  final digits = value.abs() >= 1000 || unit == 'steps' ? 0 : 1;
  final text = value.toStringAsFixed(digits);
  return unit.isEmpty
      ? text
      : unit.startsWith('/')
      ? '$text$unit'
      : '$text $unit';
}

/// The signed change in a finding ("+4.1 kg").
String _deltaText(LabsFinding f) {
  final d = f.delta!;
  return '${d > 0
      ? '+'
      : d < 0
      ? '−'
      : '±'}${_num(d.abs(), f.unit)}';
}

/// A 38 px rounded square holding a tinted icon.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color, this.fill});

  final IconData icon;
  final Color color;
  final Color? fill;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: fill ?? color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 20, color: color),
  );
}

/// A label over a short value, on a dark inset ("OUTCOME · Bench e1RM").
class _MiniTile extends StatelessWidget {
  const _MiniTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hx.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: hx.secondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AverageStat extends StatelessWidget {
  const _AverageStat({
    required this.label,
    required this.value,
    required this.labelColor,
    this.delta,
    this.deltaColor,
  });

  final String label;
  final String value;
  final Color labelColor;
  final String? delta;
  final Color? deltaColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: labelColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      Text.rich(
        TextSpan(
          text: value,
          children: [
            if (delta != null)
              TextSpan(
                text: ' $delta',
                style: TextStyle(fontSize: 14, color: deltaColor),
              ),
          ],
        ),
        style: _labsDisplay(24, weight: FontWeight.w600),
      ),
    ],
  );
}

/// A full-width dashed outline button ("New experiment").
class _DashedButton extends StatelessWidget {
  const _DashedButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: hx.outline, radius: 18),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: hx.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: hx.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(
          metric.extractPath(d, min(d + 5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
