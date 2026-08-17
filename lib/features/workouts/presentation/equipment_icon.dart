import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A compact, purpose-built equipment glyph.
///
/// Material's generic fitness icons make a barbell, dumbbell and machine look
/// interchangeable. These simple line glyphs keep the equipment choices
/// legible at the small sizes used by the picker and bottom sheets.
class EquipmentGlyph extends StatelessWidget {
  final String variant;
  final double size;
  final Color color;

  const EquipmentGlyph({
    super.key,
    required this.variant,
    this.size = 22,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _EquipmentGlyphPainter(variant: variant, color: color),
    );
  }
}

class _EquipmentGlyphPainter extends CustomPainter {
  final String variant;
  final Color color;

  _EquipmentGlyphPainter({required this.variant, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.7, size.width * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    void line(double x1, double y1, double x2, double y2, Paint paint) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    void rect(double x, double y, double width, double height, Paint paint) {
      canvas.drawRect(Rect.fromLTWH(x, y, width, height), paint);
    }

    void circle(double x, double y, double radius, Paint paint) {
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    switch (variant) {
      case 'barbell':
        line(3, cy, w - 3, cy, stroke);
        rect(4, cy - h * .28, w * .11, h * .56, fill);
        rect(w * .16, cy - h * .20, w * .07, h * .40, fill);
        rect(w - w * .27, cy - h * .20, w * .07, h * .40, fill);
        rect(w - w * .15, cy - h * .28, w * .11, h * .56, fill);
        break;
      case 'dumbbell':
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(-math.pi / 4);
        line(-w * .22, 0, w * .22, 0, stroke);
        rect(-w * .42, -h * .22, w * .11, h * .44, fill);
        rect(-w * .30, -h * .16, w * .08, h * .32, fill);
        rect(w * .22, -h * .16, w * .08, h * .32, fill);
        rect(w * .31, -h * .22, w * .11, h * .44, fill);
        canvas.restore();
        break;
      case 'smith':
        line(w * .2, 3, w * .2, h - 3, stroke);
        line(w * .8, 3, w * .8, h - 3, stroke);
        line(w * .13, cy, w * .87, cy, stroke);
        line(w * .08, h - 3, w * .92, h - 3, stroke);
        break;
      case 'cable':
        circle(w * .30, h * .25, w * .13, stroke);
        line(w * .30, h * .38, w * .60, h * .72, stroke);
        line(w * .60, h * .72, w * .84, h * .72, stroke);
        line(w * .72, h * .62, w * .84, h * .72, stroke);
        break;
      case 'machine_plate':
      case 'machine_selectorized':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .23, h * .13, w * .54, h * .74),
            Radius.circular(w * .08),
          ),
          stroke,
        );
        for (var i = 0; i < 3; i++) {
          final y = h * (.34 + i * .15);
          line(w * .36, y, w * .64, y, stroke);
        }
        break;
      case 'kettlebell':
        final handle = Path()
          ..moveTo(w * .31, h * .43)
          ..cubicTo(w * .27, h * .05, w * .73, h * .05, w * .69, h * .43);
        canvas.drawPath(handle, stroke);
        circle(cx, h * .60, w * .24, fill);
        break;
      case 'band':
        final band = Path()
          ..moveTo(w * .25, h * .20)
          ..cubicTo(w * .05, h * .38, w * .05, h * .62, w * .25, h * .80)
          ..cubicTo(w * .52, h * .98, w * .95, h * .77, w * .75, h * .55)
          ..cubicTo(w * .63, h * .42, w * .45, h * .42, w * .25, h * .20);
        canvas.drawPath(band, stroke);
        break;
      case 'bodyweight':
        circle(cx, h * .18, w * .11, stroke);
        line(cx, h * .30, cx, h * .62, stroke);
        line(w * .22, h * .40, w * .78, h * .40, stroke);
        line(cx, h * .62, w * .28, h * .88, stroke);
        line(cx, h * .62, w * .72, h * .88, stroke);
        break;
      case 'weighted':
        circle(cx, cy, w * .30, stroke);
        circle(cx, cy, w * .12, stroke);
        line(cx, h * .08, cx, h * .92, stroke);
        break;
      default:
        circle(w * .27, cy, w * .07, fill);
        circle(cx, cy, w * .07, fill);
        circle(w * .73, cy, w * .07, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _EquipmentGlyphPainter oldDelegate) =>
      oldDelegate.variant != variant || oldDelegate.color != color;
}
