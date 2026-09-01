import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:herculex/design_system/tokens/tokens.dart';

/// A minimalist clock dial background with radial hour and minute tick marks,
/// giving the fasting screen an authentic, sleek chronograph feel.
class ClockDialBackground extends StatelessWidget {
  const ClockDialBackground({super.key, this.size = 320});

  final double size;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final isDark = hx.isDark;
    final accentColor = hx.domainFasting;

    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _ClockDialPainter(
              accentColor: accentColor,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockDialPainter extends CustomPainter {
  const _ClockDialPainter({required this.accentColor, required this.isDark});

  final Color accentColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const margin = 10.0;
    final dialRadius = radius - margin;

    // Faint outer guide ring
    final ringPaint = Paint()
      ..color = accentColor.withValues(alpha: isDark ? 0.06 : 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, dialRadius, ringPaint);

    // Subtle inner guide ring
    final innerRingPaint = Paint()
      ..color = accentColor.withValues(alpha: isDark ? 0.03 : 0.02)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, dialRadius - 20, innerRingPaint);

    // 60 tick marks for the 60 minutes / 12 hours
    final tickPaint = Paint()..strokeCap = StrokeCap.round;

    for (int i = 0; i < 60; i++) {
      final angle = (i * 2 * math.pi / 60) - (math.pi / 2);
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final bool isCardinal = i % 15 == 0; // 12, 3, 6, 9 o'clock
      final bool isHour = i % 5 == 0; // Every 5 min / hour marker

      final double tickLength;
      final double strokeWidth;
      final double alpha;

      if (isCardinal) {
        tickLength = 16.0;
        strokeWidth = 2.5;
        alpha = isDark ? 0.28 : 0.24;
      } else if (isHour) {
        tickLength = 12.0;
        strokeWidth = 2.0;
        alpha = isDark ? 0.18 : 0.15;
      } else {
        tickLength = 6.0;
        strokeWidth = 1.0;
        alpha = isDark ? 0.08 : 0.06;
      }

      tickPaint
        ..color = accentColor.withValues(alpha: alpha)
        ..strokeWidth = strokeWidth;

      final startPoint = Offset(
        center.dx + dialRadius * cosA,
        center.dy + dialRadius * sinA,
      );
      final endPoint = Offset(
        center.dx + (dialRadius - tickLength) * cosA,
        center.dy + (dialRadius - tickLength) * sinA,
      );

      canvas.drawLine(startPoint, endPoint, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClockDialPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.isDark != isDark;
  }
}
