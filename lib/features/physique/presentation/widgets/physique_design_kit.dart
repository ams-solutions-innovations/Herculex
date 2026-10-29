import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';

// Shared pieces of the Dream Physique progress and roadmap screens, laid out
// after the "Dream Physique AI" Claude Design prototype.

/// Space Grotesk, the display face the design uses for titles and numbers.
TextStyle physiqueDisplay(
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
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// The flat card most blocks sit in.
BoxDecoration physiqueCard(
  BuildContext context, {
  double radius = 24,
  Color? border,
  Color? tint,
}) {
  final hx = context.hx;
  return BoxDecoration(
    color: tint == null ? hx.surfaceContainerLowest : null,
    gradient: tint == null
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.55],
            colors: [tint.withValues(alpha: 0.14), hx.surfaceContainerLowest],
          ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? hx.outlineVariant),
  );
}

/// The accent the design gives each phase type: cuts amber, building green,
/// holding grey.
Color physiquePhaseColor(DietPhase phase, HxColors hx) => switch (phase) {
  DietPhase.cut => hx.warning,
  DietPhase.bulk || DietPhase.maingain => hx.success,
  DietPhase.recomp => hx.primaryText,
  DietPhase.maintain => hx.secondary,
};

DietPhase physiquePhaseOf(String name) => DietPhase.values.firstWhere(
  (p) => p.name == name,
  orElse: () => DietPhase.maintain,
);

/// Small all-caps label above a value ("TO GOAL", "EXIT WHEN").
class PhysiqueEyebrow extends StatelessWidget {
  const PhysiqueEyebrow(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.hx.secondary;
    final label = Text(
      text,
      style: TextStyle(
        color: c,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
    if (icon == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Flexible(child: label),
      ],
    );
  }
}

/// A section heading with an optional quiet note on the right.
class PhysiqueSectionTitle extends StatelessWidget {
  const PhysiqueSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: physiqueDisplay(20))),
      if (trailing != null) ...[
        const SizedBox(width: 12),
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ],
    ],
  );
}

/// A rounded pill with a tinted fill ("On track").
class PhysiqueTintPill extends StatelessWidget {
  const PhysiqueTintPill(
    this.text, {
    super.key,
    required this.color,
    this.icon,
  });

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: HxRadius.pillAll,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A label over a short value on a dark inset ("PACE · −0.4 kg/wk").
class PhysiqueMiniTile extends StatelessWidget {
  const PhysiqueMiniTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

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
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: physiqueDisplay(
                17,
                weight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round progress ring with something in the middle.
class PhysiqueRing extends StatelessWidget {
  const PhysiqueRing({
    super.key,
    required this.value,
    required this.size,
    required this.stroke,
    required this.child,
  });

  /// 0..1, or null for an empty track.
  final double? value;
  final double size;
  final double stroke;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value ?? 0,
          stroke: stroke,
          track: hx.surfaceVariant,
          color: hx.primary,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.color,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// A thin rounded bar filled to [value].
class PhysiqueBar extends StatelessWidget {
  const PhysiqueBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 4,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: SizedBox(
      height: height,
      child: ColoredBox(
        color: context.hx.surfaceVariant,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: ColoredBox(color: color),
        ),
      ),
    ),
  );
}
