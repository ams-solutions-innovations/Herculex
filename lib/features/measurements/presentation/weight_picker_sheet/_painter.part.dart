part of '../weight_picker_sheet.dart';

class _DigitalReadoutBadge extends StatelessWidget {
  final double currentRounded;
  final String unitSuffix;
  final double? previousDisplayWeight;
  final VoidCallback onTap;

  const _DigitalReadoutBadge({
    required this.currentRounded,
    required this.unitSuffix,
    required this.previousDisplayWeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;

    Widget? diffWidget;
    if (previousDisplayWeight != null) {
      final diff = currentRounded - previousDisplayWeight!;
      if (diff.abs() >= 0.05) {
        final isLoss = diff < 0;
        final color = isLoss ? hx.success : hx.warning;
        final icon = isLoss
            ? Icons.trending_down_rounded
            : Icons.trending_up_rounded;
        final sign = diff > 0 ? '+' : '';
        diffWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                '$sign${diff.toStringAsFixed(1)} $unitSuffix vs last',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        );
      } else {
        diffWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: hx.onSurface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Same as last log',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: hx.secondary,
            ),
          ),
        );
      }
    }

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  currentRounded.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.0,
                    color: hx.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unitSuffix,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: hx.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: hx.secondary.withValues(alpha: 0.5),
                ),
              ],
            ),
            if (diffWidget != null) ...[
              const SizedBox(height: 5),
              diffWidget,
            ] else ...[
              const SizedBox(height: 5),
              Text(
                'Drag scale to adjust',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: hx.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManualWeightInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String unitSuffix;
  final VoidCallback onSubmitted;

  const _ManualWeightInput({
    required this.controller,
    required this.focusNode,
    required this.unitSuffix,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.primary, width: 1.5),
      ),
      child: SizedBox(
        width: 160,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: hx.onSurface,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  suffixText: unitSuffix,
                  suffixStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hx.primary,
                  ),
                ),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_rounded),
              color: hx.primary,
              iconSize: 22,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onSubmitted,
            ),
          ],
        ),
      ),
    );
  }
}

class _FrostedStepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FrostedStepButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: HxGlass(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          borderRadius: BorderRadius.circular(16),
          fill: HxGlass.frostedFill(hx),
          borderColor: HxGlass.frostedBorder(hx),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: hx.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScaleSemicirclePainter extends CustomPainter {
  final double currentWeight;
  final bool isMetric;
  final Color primaryColor;
  final Color onSurface;
  final Color outline;
  final Color glassBorder;
  final bool isDragging;

  _ScaleSemicirclePainter({
    required this.currentWeight,
    required this.isMetric,
    required this.primaryColor,
    required this.onSurface,
    required this.outline,
    required this.glassBorder,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height + 25);
    final radius = size.width * 0.54;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final rimPaint = Paint()
      ..color = glassBorder.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const startAngle = -math.pi * 0.92;
    const sweepAngle = math.pi * 0.84;
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, rimPaint);

    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: isDragging ? 0.22 : 0.12)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawArc(arcRect, -math.pi / 2 - 0.35, 0.70, false, glowPaint);

    const anglePerUnit = 0.28;
    final minVal = (currentWeight - 4.5).floorToDouble();
    final maxVal = (currentWeight + 4.5).ceilToDouble();

    final minTenth = (minVal * 10).round();
    final maxTenth = (maxVal * 10).round();

    for (int t = minTenth; t <= maxTenth; t++) {
      final v = t / 10.0;
      final angle = -math.pi / 2 + (v - currentWeight) * anglePerUnit;
      final angleDistFromCenter = (angle - (-math.pi / 2)).abs();
      if (angleDistFromCenter > 1.25) continue;

      final fade = (1.0 - (angleDistFromCenter - 0.75) / 0.45).clamp(0.0, 1.0);
      if (fade <= 0.01) continue;

      final isMajor = t % 10 == 0;
      final isMedium = t % 5 == 0 && !isMajor;

      final tickLength = isMajor ? 16.0 : (isMedium ? 10.0 : 5.5);
      final tickWidth = isMajor ? 2.4 : (isMedium ? 1.6 : 1.0);

      final tickColor = isMajor
          ? onSurface.withValues(alpha: 0.85 * fade)
          : (isMedium
                ? onSurface.withValues(alpha: 0.50 * fade)
                : outline.withValues(alpha: 0.30 * fade));

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final pOuter = Offset(
        center.dx + radius * cosA,
        center.dy + radius * sinA,
      );
      final pInner = Offset(
        center.dx + (radius - tickLength) * cosA,
        center.dy + (radius - tickLength) * sinA,
      );

      final tickPaint = Paint()
        ..color = tickColor
        ..strokeWidth = tickWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(pOuter, pInner, tickPaint);

      if (isMajor && fade > 0.2) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${v.round()}',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.80 * fade),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelRadius = radius - 28.0;
        final pLabel = Offset(
          center.dx + labelRadius * cosA,
          center.dy + labelRadius * sinA,
        );

        textPainter.paint(
          canvas,
          Offset(
            pLabel.dx - textPainter.width / 2,
            pLabel.dy - textPainter.height / 2,
          ),
        );
      }
    }

    final needleTopY = center.dy - radius - 10;
    final needleBottomY = center.dy - radius + 15;

    final needleGlowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawLine(
      Offset(center.dx, needleTopY),
      Offset(center.dx, needleBottomY),
      needleGlowPaint,
    );

    final needlePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx, needleTopY),
      Offset(center.dx, needleBottomY),
      needlePaint,
    );

    final pipCenter = Offset(center.dx, needleTopY + 2);
    final pipGlowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pipCenter, 6.0, pipGlowPaint);

    final pipInnerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pipCenter, 2.8, pipInnerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScaleSemicirclePainter oldDelegate) {
    return oldDelegate.currentWeight != currentWeight ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.primaryColor != primaryColor;
  }
}
