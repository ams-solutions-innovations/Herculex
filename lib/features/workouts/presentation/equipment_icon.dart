import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Equipment categories recognized across the Herculex catalog and logging.
enum EquipmentType {
  barbell,
  dumbbell,
  kettlebell,
  swissBar,
  ezBar,
  trapBar,
  safetyBar,
  axleBar,
  camberedBar,
  smith,
  cable,
  machinePlate,
  machineSelectorized,
  bodyweight,
  weighted,
  band,
  plate,
  landmine,
  rings,
  trx,
  medicineBall,
  sandbag,
  sled,
  battleRopes,
  climbingRope,
  jumpRope,
  neckHarness,
  treadmill,
  rower,
  airBike,
  stationaryBike,
  skiErg,
  elliptical,
  stairClimber,
  other;

  /// Normalizes any raw equipment or modality string into an [EquipmentType].
  static EquipmentType resolve(String? raw) {
    if (raw == null || raw.trim().isEmpty) return EquipmentType.other;
    final s = raw
        .toLowerCase()
        .trim()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');

    if (s.contains('swiss') ||
        s.contains('football bar') ||
        s.contains('multi grip')) {
      return EquipmentType.swissBar;
    }
    if (s.contains('ez') || s.contains('curl bar')) {
      return EquipmentType.ezBar;
    }
    if (s.contains('trap') || s.contains('hex bar')) {
      return EquipmentType.trapBar;
    }
    if (s.contains('safety') || s.contains('ssb')) {
      return EquipmentType.safetyBar;
    }
    if (s.contains('axle') || s.contains('fat bar')) {
      return EquipmentType.axleBar;
    }
    if (s.contains('camber') || s.contains('duffalo')) {
      return EquipmentType.camberedBar;
    }
    if (s.contains('smith')) {
      return EquipmentType.smith;
    }
    if (s.contains('kettlebell') || s == 'kb') {
      return EquipmentType.kettlebell;
    }
    if (s.contains('dumbbell') || s == 'db') {
      return EquipmentType.dumbbell;
    }
    if (s.contains('cable') || s.contains('pulley')) {
      return EquipmentType.cable;
    }
    if (s.contains('plate loaded') ||
        s.contains('machine plate') ||
        s.contains('hammer')) {
      return EquipmentType.machinePlate;
    }
    if (s.contains('selectorized') ||
        s.contains('stack') ||
        s.contains('pin loaded')) {
      return EquipmentType.machineSelectorized;
    }
    if (s.contains('machine')) {
      return EquipmentType.machineSelectorized;
    }
    if (s.contains('landmine')) {
      return EquipmentType.landmine;
    }
    if (s.contains('ring')) {
      return EquipmentType.rings;
    }
    if (s.contains('trx') || s.contains('suspension')) {
      return EquipmentType.trx;
    }
    if (s.contains('medicine') ||
        s.contains('slam ball') ||
        s.contains('wall ball')) {
      return EquipmentType.medicineBall;
    }
    if (s.contains('sandbag')) {
      return EquipmentType.sandbag;
    }
    if (s.contains('sled') || s.contains('prowler') || s.contains('yoke')) {
      return EquipmentType.sled;
    }
    if (s.contains('battle rope')) {
      return EquipmentType.battleRopes;
    }
    if (s.contains('climb') && s.contains('rope')) {
      return EquipmentType.climbingRope;
    }
    if (s.contains('jump rope') || s.contains('speed rope')) {
      return EquipmentType.jumpRope;
    }
    if (s.contains('neck')) {
      return EquipmentType.neckHarness;
    }
    if (s.contains('treadmill')) {
      return EquipmentType.treadmill;
    }
    if (s.contains('rower') || s.contains('rowing') || s.contains('row erg')) {
      return EquipmentType.rower;
    }
    if (s.contains('air bike') ||
        s.contains('assault') ||
        s.contains('echo bike')) {
      return EquipmentType.airBike;
    }
    if (s.contains('stationary bike') ||
        s.contains('spin bike') ||
        s.contains('bike') ||
        s.contains('cycle')) {
      return EquipmentType.stationaryBike;
    }
    if (s.contains('ski erg') || s.contains('skierg') || s.contains('ski')) {
      return EquipmentType.skiErg;
    }
    if (s.contains('elliptical')) {
      return EquipmentType.elliptical;
    }
    if (s.contains('stair') || s.contains('stepmill')) {
      return EquipmentType.stairClimber;
    }
    if (s.contains('weighted')) {
      return EquipmentType.weighted;
    }
    if (s.contains('band') || s.contains('assist')) {
      return EquipmentType.band;
    }
    if (s.contains('bodyweight') || s.contains('calisthenic')) {
      return EquipmentType.bodyweight;
    }
    if (s.contains('plate') || s.contains('bumper')) {
      return EquipmentType.plate;
    }
    if (s.contains('barbell') || s == 'bb') {
      return EquipmentType.barbell;
    }
    return EquipmentType.other;
  }
}

/// A purpose-built, high-clarity equipment glyph.
///
/// Designed specifically for dark and light fitness themes with crisp vector geometry,
/// balanced stroke weights, and clear visual hierarchy for every piece of gym equipment.
class EquipmentGlyph extends StatelessWidget {
  final String variant;
  final double size;
  final Color color;

  const EquipmentGlyph({
    super.key,
    required this.variant,
    this.size = 24,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final type = EquipmentType.resolve(variant);
    return CustomPaint(
      size: Size.square(size),
      painter: _EquipmentGlyphPainter(type: type, color: color),
    );
  }
}

class _EquipmentGlyphPainter extends CustomPainter {
  final EquipmentType type;
  final Color color;

  _EquipmentGlyphPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final sw = math.max(1.6, size.width * 0.08);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final thinStroke = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, sw * 0.65)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    void line(double x1, double y1, double x2, double y2, [Paint? p]) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), p ?? stroke);
    }

    void rrect(
      double x,
      double y,
      double width,
      double height,
      double r, [
      Paint? p,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, width, height),
          Radius.circular(r),
        ),
        p ?? fill,
      );
    }

    void circle(double x, double y, double radius, [Paint? p]) {
      canvas.drawCircle(Offset(x, y), radius, p ?? stroke);
    }

    switch (type) {
      case EquipmentType.barbell:
        // Central bar
        line(w * 0.06, cy, w * 0.94, cy, stroke);
        // Knurling center marks
        line(w * 0.38, cy - h * 0.08, w * 0.38, cy + h * 0.08, thinStroke);
        line(w * 0.62, cy - h * 0.08, w * 0.62, cy + h * 0.08, thinStroke);
        // Inner collars
        rrect(w * 0.22, cy - h * 0.18, w * 0.04, h * 0.36, 1, fill);
        rrect(w * 0.74, cy - h * 0.18, w * 0.04, h * 0.36, 1, fill);
        // Plates: Large inner plate
        rrect(w * 0.15, cy - h * 0.38, w * 0.06, h * 0.76, 2, fill);
        rrect(w * 0.79, cy - h * 0.38, w * 0.06, h * 0.76, 2, fill);
        // Plates: Medium outer plate
        rrect(w * 0.08, cy - h * 0.28, w * 0.05, h * 0.56, 1.5, fill);
        rrect(w * 0.87, cy - h * 0.28, w * 0.05, h * 0.56, 1.5, fill);
        break;

      case EquipmentType.dumbbell:
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(-math.pi / 4);
        // Handle
        line(-w * 0.24, 0, w * 0.24, 0, stroke);
        // Handle grip texture marks
        line(-w * 0.08, -h * 0.06, -w * 0.08, h * 0.06, thinStroke);
        line(w * 0.08, -h * 0.06, w * 0.08, h * 0.06, thinStroke);
        // Left head (beveled plates)
        rrect(-w * 0.33, -h * 0.22, w * 0.07, h * 0.44, 2, fill);
        rrect(-w * 0.45, -h * 0.28, w * 0.09, h * 0.56, 2.5, fill);
        // Right head (beveled plates)
        rrect(w * 0.26, -h * 0.22, w * 0.07, h * 0.44, 2, fill);
        rrect(w * 0.36, -h * 0.28, w * 0.09, h * 0.56, 2.5, fill);
        canvas.restore();
        break;

      case EquipmentType.kettlebell:
        // Handle
        final handle = Path()
          ..moveTo(w * 0.30, h * 0.44)
          ..cubicTo(w * 0.25, h * 0.12, w * 0.75, h * 0.12, w * 0.70, h * 0.44);
        canvas.drawPath(handle, stroke);
        // Bell body
        final bell = Path()
          ..moveTo(w * 0.24, h * 0.46)
          ..cubicTo(w * 0.10, h * 0.60, w * 0.15, h * 0.88, w * 0.34, h * 0.88)
          ..lineTo(w * 0.66, h * 0.88)
          ..cubicTo(w * 0.85, h * 0.88, w * 0.90, h * 0.60, w * 0.76, h * 0.46)
          ..close();
        canvas.drawPath(bell, fill);
        break;

      case EquipmentType.swissBar:
        // Multi-grip / football bar: rectangular cage with 3-4 neutral grip rungs + outer sleeves
        // Sleeves extending out
        line(w * 0.05, cy, w * 0.22, cy, stroke);
        line(w * 0.78, cy, w * 0.95, cy, stroke);
        // Outer plates
        rrect(w * 0.08, cy - h * 0.34, w * 0.05, h * 0.68, 1.5, fill);
        rrect(w * 0.87, cy - h * 0.34, w * 0.05, h * 0.68, 1.5, fill);
        // Rectangular cage outline
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.22, h * 0.25, w * 0.56, h * 0.50),
            Radius.circular(w * 0.05),
          ),
          stroke,
        );
        // Internal neutral grip rungs
        line(w * 0.33, h * 0.25, w * 0.33, h * 0.75, stroke);
        line(w * 0.44, h * 0.25, w * 0.44, h * 0.75, stroke);
        line(w * 0.56, h * 0.25, w * 0.56, h * 0.75, stroke);
        line(w * 0.67, h * 0.25, w * 0.67, h * 0.75, stroke);
        break;

      case EquipmentType.ezBar:
        // W-zigzag shaped curl bar
        final ez = Path()
          ..moveTo(w * 0.05, cy)
          ..lineTo(w * 0.22, cy)
          ..lineTo(w * 0.34, cy - h * 0.18)
          ..lineTo(w * 0.50, cy + h * 0.14)
          ..lineTo(w * 0.66, cy - h * 0.18)
          ..lineTo(w * 0.78, cy)
          ..lineTo(w * 0.95, cy);
        canvas.drawPath(ez, stroke);
        // Plates
        rrect(w * 0.08, cy - h * 0.32, w * 0.05, h * 0.64, 1.5, fill);
        rrect(w * 0.87, cy - h * 0.32, w * 0.05, h * 0.64, 1.5, fill);
        // Inner collars
        rrect(w * 0.20, cy - h * 0.14, w * 0.03, h * 0.28, 1, fill);
        rrect(w * 0.77, cy - h * 0.14, w * 0.03, h * 0.28, 1, fill);
        break;

      case EquipmentType.trapBar:
        // Hexagonal frame with neutral side handles and outer load sleeves
        final hex = Path()
          ..moveTo(w * 0.24, cy)
          ..lineTo(w * 0.35, h * 0.24)
          ..lineTo(w * 0.65, h * 0.24)
          ..lineTo(w * 0.76, cy)
          ..lineTo(w * 0.65, h * 0.76)
          ..lineTo(w * 0.35, h * 0.76)
          ..close();
        canvas.drawPath(hex, stroke);
        // Outer sleeves
        line(w * 0.05, cy, w * 0.24, cy, stroke);
        line(w * 0.76, cy, w * 0.95, cy, stroke);
        // Side handles inside the hex
        line(w * 0.24, cy - h * 0.16, w * 0.24, cy + h * 0.16, stroke);
        line(w * 0.76, cy - h * 0.16, w * 0.76, cy + h * 0.16, stroke);
        // Plates
        rrect(w * 0.07, cy - h * 0.32, w * 0.05, h * 0.64, 1.5, fill);
        rrect(w * 0.88, cy - h * 0.32, w * 0.05, h * 0.64, 1.5, fill);
        break;

      case EquipmentType.safetyBar:
        // Padded neck yoke + forward handles + cambered drop sleeves
        // Padded top yoke
        rrect(w * 0.30, h * 0.22, w * 0.40, h * 0.18, 4, fill);
        // Forward handles extending downward
        line(w * 0.40, h * 0.36, w * 0.40, h * 0.80, stroke);
        line(w * 0.60, h * 0.36, w * 0.60, h * 0.80, stroke);
        // Handle grip caps
        rrect(w * 0.37, h * 0.65, w * 0.06, h * 0.16, 2, fill);
        rrect(w * 0.57, h * 0.65, w * 0.06, h * 0.16, 2, fill);
        // Cambered drop arms on sides
        final leftCamber = Path()
          ..moveTo(w * 0.30, h * 0.31)
          ..lineTo(w * 0.18, h * 0.31)
          ..lineTo(w * 0.12, h * 0.60)
          ..lineTo(w * 0.05, h * 0.60);
        canvas.drawPath(leftCamber, stroke);
        final rightCamber = Path()
          ..moveTo(w * 0.70, h * 0.31)
          ..lineTo(w * 0.82, h * 0.31)
          ..lineTo(w * 0.88, h * 0.60)
          ..lineTo(w * 0.95, h * 0.60);
        canvas.drawPath(rightCamber, stroke);
        // Plates
        rrect(w * 0.06, h * 0.42, w * 0.04, h * 0.36, 1.5, fill);
        rrect(w * 0.90, h * 0.42, w * 0.04, h * 0.36, 1.5, fill);
        break;

      case EquipmentType.axleBar:
        // Chunky, extra thick straight bar
        line(w * 0.06, cy, w * 0.94, cy, stroke..strokeWidth = sw * 2.2);
        // Heavy solid sleeves
        rrect(w * 0.08, cy - h * 0.34, w * 0.08, h * 0.68, 2, fill);
        rrect(w * 0.84, cy - h * 0.34, w * 0.08, h * 0.68, 2, fill);
        break;

      case EquipmentType.camberedBar:
        // Arched camber bar bowing downwards
        final camber = Path()
          ..moveTo(w * 0.06, h * 0.35)
          ..lineTo(w * 0.22, h * 0.35)
          ..cubicTo(w * 0.25, h * 0.75, w * 0.75, h * 0.75, w * 0.78, h * 0.35)
          ..lineTo(w * 0.94, h * 0.35);
        canvas.drawPath(camber, stroke);
        rrect(w * 0.08, h * 0.16, w * 0.05, h * 0.50, 1.5, fill);
        rrect(w * 0.87, h * 0.16, w * 0.05, h * 0.50, 1.5, fill);
        break;

      case EquipmentType.smith:
        // Vertical guide columns
        line(w * 0.22, h * 0.12, w * 0.22, h * 0.88, stroke);
        line(w * 0.78, h * 0.12, w * 0.78, h * 0.88, stroke);
        // Top and bottom frame
        line(w * 0.14, h * 0.12, w * 0.86, h * 0.12, stroke);
        line(w * 0.10, h * 0.88, w * 0.90, h * 0.88, stroke);
        // Barbell carriage across
        line(w * 0.06, cy, w * 0.94, cy, stroke);
        // Carriage slider blocks on posts
        rrect(w * 0.18, cy - h * 0.08, w * 0.08, h * 0.16, 2, fill);
        rrect(w * 0.74, cy - h * 0.08, w * 0.08, h * 0.16, 2, fill);
        // Hook notches
        for (var i = 0; i < 3; i++) {
          final y = h * (0.28 + i * 0.20);
          line(w * 0.22, y, w * 0.27, y, thinStroke);
          line(w * 0.78, y, w * 0.73, y, thinStroke);
        }
        break;

      case EquipmentType.cable:
        // Upper and lower pulleys with cable line and D-handle
        circle(w * 0.28, h * 0.24, w * 0.11, stroke);
        circle(w * 0.28, h * 0.24, w * 0.04, fill);
        circle(w * 0.28, h * 0.76, w * 0.11, stroke);
        circle(w * 0.28, h * 0.76, w * 0.04, fill);
        // Column spine
        line(w * 0.28, h * 0.10, w * 0.28, h * 0.90, stroke);
        // Cable line stretching out to D-handle
        final cableLine = Path()
          ..moveTo(w * 0.28, h * 0.35)
          ..lineTo(w * 0.62, cy);
        canvas.drawPath(cableLine, thinStroke);
        // Stirrup D-handle
        final dHandle = Path()
          ..moveTo(w * 0.62, cy - h * 0.18)
          ..lineTo(w * 0.78, cy - h * 0.18)
          ..cubicTo(
            w * 0.88,
            cy - h * 0.18,
            w * 0.88,
            cy + h * 0.18,
            w * 0.78,
            cy + h * 0.18,
          )
          ..lineTo(w * 0.62, cy + h * 0.18)
          ..close();
        canvas.drawPath(dHandle, stroke);
        line(
          w * 0.62,
          cy - h * 0.18,
          w * 0.62,
          cy + h * 0.18,
          stroke..strokeWidth = sw * 1.3,
        );
        break;

      case EquipmentType.machinePlate:
        // Lever arm pivot with weight horn holding an Olympic plate + seat frame
        // Base and seat
        line(w * 0.15, h * 0.85, w * 0.85, h * 0.85, stroke);
        line(w * 0.30, h * 0.85, w * 0.30, h * 0.45, stroke);
        rrect(w * 0.22, h * 0.42, w * 0.22, h * 0.08, 2, fill); // Seat pad
        // Pivot tower and lever arm
        line(w * 0.70, h * 0.85, w * 0.70, h * 0.25, stroke);
        circle(w * 0.70, h * 0.25, w * 0.06, fill); // Pivot bearing
        // Lever arm swinging down to handle
        line(w * 0.70, h * 0.25, w * 0.45, h * 0.35, stroke);
        // Plate mounted on horn
        rrect(w * 0.60, h * 0.14, w * 0.08, h * 0.34, 2, fill);
        break;

      case EquipmentType.machineSelectorized:
        // Weight stack tower with selector pin + seat and arm
        // Stack enclosure
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.12, w * 0.38, h * 0.76),
            Radius.circular(w * 0.06),
          ),
          stroke,
        );
        // Weight plates inside stack
        for (var i = 0; i < 4; i++) {
          final y = h * (0.28 + i * 0.12);
          line(w * 0.24, y, w * 0.50, y, thinStroke);
        }
        // Top pulley and cable
        circle(w * 0.37, h * 0.18, w * 0.05, fill);
        line(w * 0.37, h * 0.18, w * 0.75, h * 0.35, thinStroke);
        // Seat & user frame
        line(w * 0.65, h * 0.88, w * 0.88, h * 0.88, stroke);
        line(w * 0.75, h * 0.88, w * 0.75, h * 0.58, stroke);
        rrect(w * 0.68, h * 0.56, w * 0.20, h * 0.07, 2, fill);
        break;

      case EquipmentType.bodyweight:
        // Dynamic athletic silhouette (pullup/calisthenics bar + athlete)
        // Bar
        line(w * 0.12, h * 0.14, w * 0.88, h * 0.14, stroke);
        // Athlete: Head
        circle(cx, h * 0.32, w * 0.10, fill);
        // Arms gripping bar
        line(w * 0.32, h * 0.14, cx - w * 0.08, h * 0.38, stroke);
        line(w * 0.68, h * 0.14, cx + w * 0.08, h * 0.38, stroke);
        // Torso V-shape
        final torso = Path()
          ..moveTo(cx - w * 0.12, h * 0.44)
          ..lineTo(cx + w * 0.12, h * 0.44)
          ..lineTo(cx + w * 0.06, h * 0.70)
          ..lineTo(cx - w * 0.06, h * 0.70)
          ..close();
        canvas.drawPath(torso, fill);
        // Legs
        line(cx - w * 0.05, h * 0.70, cx - w * 0.08, h * 0.90, stroke);
        line(cx + w * 0.05, h * 0.70, cx + w * 0.08, h * 0.90, stroke);
        break;

      case EquipmentType.weighted:
        // Dip belt / chain with heavy Olympic plate attached
        // Belt contour at top
        final belt = Path()
          ..moveTo(w * 0.20, h * 0.22)
          ..cubicTo(w * 0.35, h * 0.32, w * 0.65, h * 0.32, w * 0.80, h * 0.22);
        canvas.drawPath(belt, stroke..strokeWidth = sw * 1.5);
        // Hanging chain links
        line(w * 0.38, h * 0.28, cx, h * 0.46, thinStroke);
        line(w * 0.62, h * 0.28, cx, h * 0.46, thinStroke);
        // Large Olympic bumper plate
        circle(cx, h * 0.66, w * 0.26, stroke);
        circle(cx, h * 0.66, w * 0.08, fill);
        // Plate bevel ring
        circle(cx, h * 0.66, w * 0.18, thinStroke);
        break;

      case EquipmentType.band:
        // Isometric loop resistance band
        final bandOuter = Path()
          ..moveTo(w * 0.22, h * 0.30)
          ..cubicTo(w * 0.06, h * 0.50, w * 0.12, h * 0.80, w * 0.42, h * 0.84)
          ..cubicTo(w * 0.78, h * 0.88, w * 0.94, h * 0.62, w * 0.78, h * 0.34)
          ..cubicTo(w * 0.66, h * 0.12, w * 0.38, h * 0.10, w * 0.22, h * 0.30);
        canvas.drawPath(bandOuter, stroke);
        final bandInner = Path()
          ..moveTo(w * 0.30, h * 0.36)
          ..cubicTo(w * 0.20, h * 0.50, w * 0.24, h * 0.70, w * 0.44, h * 0.74)
          ..cubicTo(w * 0.68, h * 0.76, w * 0.80, h * 0.58, w * 0.70, h * 0.40)
          ..cubicTo(w * 0.60, h * 0.22, w * 0.42, h * 0.22, w * 0.30, h * 0.36);
        canvas.drawPath(bandInner, thinStroke);
        break;

      case EquipmentType.plate:
        // Bumper plate with 3 ergonomic grip handles + center hole
        circle(cx, cy, w * 0.40, stroke);
        circle(cx, cy, w * 0.10, fill);
        circle(cx, cy, w * 0.28, thinStroke);
        // 3 grip handles spaced at 120 deg
        for (var i = 0; i < 3; i++) {
          final angle = i * 2 * math.pi / 3 - math.pi / 2;
          final gx = cx + math.cos(angle) * (w * 0.22);
          final gy = cy + math.sin(angle) * (h * 0.22);
          circle(gx, gy, w * 0.05, fill);
        }
        break;

      case EquipmentType.landmine:
        // Ground swivel base + angled barbell sleeve with plate
        // Base plate
        line(w * 0.12, h * 0.85, w * 0.45, h * 0.85, stroke);
        circle(w * 0.24, h * 0.78, w * 0.07, fill); // Swivel joint
        // Barbell rising at angle
        line(w * 0.24, h * 0.78, w * 0.88, h * 0.18, stroke);
        // Plate mounted near top
        canvas.save();
        canvas.translate(w * 0.72, h * 0.33);
        canvas.rotate(math.pi / 4);
        rrect(-w * 0.04, -h * 0.24, w * 0.08, h * 0.48, 2, fill);
        canvas.restore();
        break;

      case EquipmentType.rings:
        // Gymnastic rings: 2 hanging straps + 2 circular rings
        line(w * 0.32, h * 0.08, w * 0.32, h * 0.50, stroke);
        line(w * 0.68, h * 0.08, w * 0.68, h * 0.50, stroke);
        circle(w * 0.32, h * 0.68, w * 0.18, stroke);
        circle(w * 0.68, h * 0.68, w * 0.18, stroke);
        break;

      case EquipmentType.trx:
        // Suspension trainer: anchor carabiner + V-straps + handles with foot loops
        circle(cx, h * 0.12, w * 0.06, fill);
        line(cx, h * 0.16, w * 0.28, h * 0.65, stroke);
        line(cx, h * 0.16, w * 0.72, h * 0.65, stroke);
        // Handles
        line(
          w * 0.20,
          h * 0.65,
          w * 0.36,
          h * 0.65,
          stroke..strokeWidth = sw * 1.5,
        );
        line(
          w * 0.64,
          h * 0.65,
          w * 0.80,
          h * 0.65,
          stroke..strokeWidth = sw * 1.5,
        );
        // Foot cradles
        final leftCradle = Path()
          ..moveTo(w * 0.20, h * 0.65)
          ..cubicTo(w * 0.20, h * 0.85, w * 0.36, h * 0.85, w * 0.36, h * 0.65);
        canvas.drawPath(leftCradle, thinStroke);
        final rightCradle = Path()
          ..moveTo(w * 0.64, h * 0.65)
          ..cubicTo(w * 0.64, h * 0.85, w * 0.80, h * 0.85, w * 0.80, h * 0.65);
        canvas.drawPath(rightCradle, thinStroke);
        break;

      case EquipmentType.medicineBall:
        // Slam / medicine ball with stitched panels
        circle(cx, cy, w * 0.38, stroke);
        // Curved side seams
        final leftSeam = Path()
          ..moveTo(cx - w * 0.18, h * 0.18)
          ..cubicTo(
            cx - w * 0.32,
            cy,
            cx - w * 0.32,
            cy,
            cx - w * 0.18,
            h * 0.82,
          );
        canvas.drawPath(leftSeam, thinStroke);
        final rightSeam = Path()
          ..moveTo(cx + w * 0.18, h * 0.18)
          ..cubicTo(
            cx + w * 0.32,
            cy,
            cx + w * 0.32,
            cy,
            cx + w * 0.18,
            h * 0.82,
          );
        canvas.drawPath(rightSeam, thinStroke);
        // Center cross-lacing
        line(
          cx - w * 0.08,
          cy - h * 0.08,
          cx + w * 0.08,
          cy - h * 0.08,
          stroke,
        );
        line(cx - w * 0.08, cy, cx + w * 0.08, cy, stroke);
        line(
          cx - w * 0.08,
          cy + h * 0.08,
          cx + w * 0.08,
          cy + h * 0.08,
          stroke,
        );
        break;

      case EquipmentType.sandbag:
        // Heavy canvas sandbag with handles
        rrect(w * 0.16, h * 0.34, w * 0.68, h * 0.38, w * 0.08, stroke);
        // Top handle
        final topHandle = Path()
          ..moveTo(w * 0.36, h * 0.34)
          ..cubicTo(w * 0.36, h * 0.18, w * 0.64, h * 0.18, w * 0.64, h * 0.34);
        canvas.drawPath(topHandle, stroke);
        // End handles
        line(
          w * 0.16,
          h * 0.42,
          w * 0.16,
          h * 0.64,
          stroke..strokeWidth = sw * 1.5,
        );
        line(
          w * 0.84,
          h * 0.42,
          w * 0.84,
          h * 0.64,
          stroke..strokeWidth = sw * 1.5,
        );
        // Transverse strap lines
        line(w * 0.38, h * 0.34, w * 0.38, h * 0.72, thinStroke);
        line(w * 0.62, h * 0.34, w * 0.62, h * 0.72, thinStroke);
        break;

      case EquipmentType.sled:
        // Prowler sled with upright push poles, weight horn, and skid runners
        // Ground ski runners
        final runner = Path()
          ..moveTo(w * 0.10, h * 0.84)
          ..lineTo(w * 0.82, h * 0.84)
          ..lineTo(w * 0.92, h * 0.74);
        canvas.drawPath(runner, stroke);
        // Dual vertical push uprights
        line(w * 0.26, h * 0.20, w * 0.26, h * 0.84, stroke);
        line(w * 0.74, h * 0.20, w * 0.74, h * 0.84, stroke);
        // Center weight horn
        line(cx, h * 0.48, cx, h * 0.84, stroke);
        rrect(cx - w * 0.14, h * 0.72, w * 0.28, h * 0.08, 2, fill);
        break;

      case EquipmentType.battleRopes:
        // Dual undulating harmonic wave paths
        final wave1 = Path()
          ..moveTo(w * 0.08, cy - h * 0.10)
          ..cubicTo(
            w * 0.28,
            cy - h * 0.40,
            w * 0.45,
            cy + h * 0.20,
            w * 0.65,
            cy - h * 0.10,
          )
          ..cubicTo(
            w * 0.75,
            cy - h * 0.25,
            w * 0.85,
            cy + h * 0.05,
            w * 0.92,
            cy,
          );
        canvas.drawPath(wave1, stroke..strokeWidth = sw * 1.4);
        final wave2 = Path()
          ..moveTo(w * 0.08, cy + h * 0.10)
          ..cubicTo(
            w * 0.28,
            cy + h * 0.40,
            w * 0.45,
            cy - h * 0.20,
            w * 0.65,
            cy + h * 0.10,
          )
          ..cubicTo(
            w * 0.75,
            cy + h * 0.25,
            w * 0.85,
            cy - h * 0.05,
            w * 0.92,
            cy + h * 0.18,
          );
        canvas.drawPath(wave2, stroke..strokeWidth = sw * 1.4);
        break;

      case EquipmentType.climbingRope:
        // Vertical braided rope with bottom knot
        line(cx, h * 0.08, cx, h * 0.74, stroke..strokeWidth = sw * 1.8);
        for (var i = 0; i < 5; i++) {
          final y = h * (0.16 + i * 0.12);
          line(
            cx - w * 0.06,
            y - h * 0.03,
            cx + w * 0.06,
            y + h * 0.03,
            thinStroke,
          );
        }
        // Stopper knot at bottom
        circle(cx, h * 0.82, w * 0.10, fill);
        break;

      case EquipmentType.jumpRope:
        // Dual handles + sweeping smooth parabolic arc
        rrect(w * 0.18, h * 0.26, w * 0.06, h * 0.24, 2, fill);
        rrect(w * 0.76, h * 0.26, w * 0.06, h * 0.24, 2, fill);
        final rope = Path()
          ..moveTo(w * 0.21, h * 0.50)
          ..cubicTo(w * 0.22, h * 0.92, w * 0.78, h * 0.92, w * 0.79, h * 0.50);
        canvas.drawPath(rope, stroke);
        break;

      case EquipmentType.neckHarness:
        // Head harness with chain
        final crown = Path()
          ..moveTo(w * 0.22, h * 0.35)
          ..cubicTo(w * 0.22, h * 0.15, w * 0.78, h * 0.15, w * 0.78, h * 0.35);
        canvas.drawPath(crown, stroke);
        line(w * 0.22, h * 0.35, w * 0.78, h * 0.35, stroke);
        // Hanging chain links
        line(w * 0.32, h * 0.35, cx, h * 0.75, thinStroke);
        line(w * 0.68, h * 0.35, cx, h * 0.75, thinStroke);
        circle(cx, h * 0.82, w * 0.08, fill);
        break;

      case EquipmentType.treadmill:
        // Treadmill deck + console tower + handrails
        final deck = Path()
          ..moveTo(w * 0.12, h * 0.76)
          ..lineTo(w * 0.88, h * 0.68)
          ..lineTo(w * 0.88, h * 0.78)
          ..lineTo(w * 0.12, h * 0.84)
          ..close();
        canvas.drawPath(deck, fill);
        // Upright post
        line(w * 0.28, h * 0.76, w * 0.28, h * 0.24, stroke);
        // Handrail & console
        line(w * 0.28, h * 0.38, w * 0.58, h * 0.38, stroke);
        rrect(w * 0.22, h * 0.16, w * 0.14, h * 0.10, 2, fill);
        break;

      case EquipmentType.rower:
        // Flywheel fan cage + monorail track + seat
        circle(w * 0.26, h * 0.52, w * 0.18, stroke);
        circle(w * 0.26, h * 0.52, w * 0.06, fill);
        // Rail track
        line(w * 0.26, h * 0.65, w * 0.90, h * 0.75, stroke);
        // Sliding seat
        rrect(w * 0.55, h * 0.60, w * 0.14, h * 0.08, 2, fill);
        // Handle & pull cord
        line(w * 0.26, h * 0.44, w * 0.46, h * 0.48, thinStroke);
        line(w * 0.46, h * 0.42, w * 0.46, h * 0.54, stroke);
        break;

      case EquipmentType.airBike:
        // Large fan wheel with radiating blades + push-pull arms + seat
        circle(w * 0.32, h * 0.60, w * 0.20, stroke);
        circle(w * 0.32, h * 0.60, w * 0.06, fill);
        for (var i = 0; i < 4; i++) {
          final angle = i * math.pi / 4;
          line(
            w * 0.32 + math.cos(angle) * w * 0.08,
            h * 0.60 + math.sin(angle) * h * 0.08,
            w * 0.32 + math.cos(angle) * w * 0.18,
            h * 0.60 + math.sin(angle) * h * 0.18,
            thinStroke,
          );
        }
        // Frame to seat
        line(w * 0.32, h * 0.60, w * 0.68, h * 0.45, stroke);
        rrect(w * 0.62, h * 0.38, w * 0.14, h * 0.07, 2, fill);
        // Dual tall push-pull arms
        line(w * 0.32, h * 0.60, w * 0.40, h * 0.18, stroke);
        break;

      case EquipmentType.stationaryBike:
        // Spin bike flywheel + frame + saddle + drop handlebars
        circle(w * 0.30, h * 0.64, w * 0.16, stroke);
        circle(w * 0.72, h * 0.64, w * 0.16, stroke);
        // Triangle frame
        final frame = Path()
          ..moveTo(w * 0.30, h * 0.64)
          ..lineTo(w * 0.52, h * 0.64)
          ..lineTo(w * 0.42, h * 0.35)
          ..close();
        canvas.drawPath(frame, stroke);
        // Seat post & saddle
        line(w * 0.52, h * 0.64, w * 0.65, h * 0.38, stroke);
        rrect(w * 0.58, h * 0.34, w * 0.14, h * 0.06, 2, fill);
        // Handlebars
        line(w * 0.42, h * 0.35, w * 0.36, h * 0.22, stroke);
        line(w * 0.36, h * 0.22, w * 0.44, h * 0.22, stroke);
        break;

      case EquipmentType.skiErg:
        // Twin upright towers + top dual drive pulleys + pull cords with handles
        line(w * 0.36, h * 0.14, w * 0.36, h * 0.88, stroke);
        line(w * 0.64, h * 0.14, w * 0.64, h * 0.88, stroke);
        line(w * 0.24, h * 0.88, w * 0.76, h * 0.88, stroke);
        // Top pulley housing
        rrect(w * 0.28, h * 0.12, w * 0.44, h * 0.12, 3, fill);
        // Cords down to handles
        line(w * 0.40, h * 0.24, w * 0.40, h * 0.56, thinStroke);
        line(w * 0.60, h * 0.24, w * 0.60, h * 0.56, thinStroke);
        rrect(w * 0.36, h * 0.56, w * 0.08, h * 0.08, 1, fill);
        rrect(w * 0.56, h * 0.56, w * 0.08, h * 0.08, 1, fill);
        break;

      case EquipmentType.elliptical:
        // Dual foot linkages + tall synchronized moving arms
        circle(w * 0.75, h * 0.62, w * 0.15, stroke);
        // Foot linkage beams
        line(w * 0.20, h * 0.72, w * 0.75, h * 0.62, stroke);
        rrect(w * 0.32, h * 0.68, w * 0.16, h * 0.06, 2, fill);
        // Dual tall arm poles
        line(w * 0.45, h * 0.72, w * 0.36, h * 0.18, stroke);
        break;

      case EquipmentType.stairClimber:
        // Revolving step stairs + handrails + console
        final steps = Path()
          ..moveTo(w * 0.18, h * 0.84)
          ..lineTo(w * 0.34, h * 0.84)
          ..lineTo(w * 0.34, h * 0.66)
          ..lineTo(w * 0.50, h * 0.66)
          ..lineTo(w * 0.50, h * 0.48)
          ..lineTo(w * 0.66, h * 0.48)
          ..lineTo(w * 0.66, h * 0.32)
          ..lineTo(w * 0.80, h * 0.32);
        canvas.drawPath(steps, stroke);
        // Handrail
        final rail = Path()
          ..moveTo(w * 0.22, h * 0.62)
          ..lineTo(w * 0.68, h * 0.20)
          ..lineTo(w * 0.82, h * 0.20);
        canvas.drawPath(rail, stroke);
        line(w * 0.22, h * 0.84, w * 0.22, h * 0.62, stroke);
        line(w * 0.68, h * 0.48, w * 0.68, h * 0.20, stroke);
        break;

      case EquipmentType.other:
        // Minimalist dumbbell badge fallback
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(-math.pi / 4);
        line(-w * 0.22, 0, w * 0.22, 0, stroke);
        rrect(-w * 0.38, -h * 0.22, w * 0.10, h * 0.44, 2, fill);
        rrect(w * 0.28, -h * 0.22, w * 0.10, h * 0.44, 2, fill);
        canvas.restore();
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _EquipmentGlyphPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color;
}
