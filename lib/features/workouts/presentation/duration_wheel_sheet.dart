import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../domain/set_metric_format.dart';

/// Modal bottom sheet with a circular scroll wheel / dial for logging duration
/// on HIIT, cardio, and time-based exercises (e.g. Assault Bike, Rowing, Planks).
///
/// 1 full circle (360°) = 60 seconds. Rotating clockwise past 60s increments
/// minutes; rotating counterclockwise decrements minutes.
class DurationWheelSheet extends StatefulWidget {
  final int initialSeconds;
  final String? exerciseName;

  const DurationWheelSheet({
    super.key,
    required this.initialSeconds,
    this.exerciseName,
  });

  static Future<int?> show(
    BuildContext context, {
    int initialSeconds = 30,
    String? exerciseName,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DurationWheelSheet(
        initialSeconds: initialSeconds,
        exerciseName: exerciseName,
      ),
    );
  }

  @override
  State<DurationWheelSheet> createState() => _DurationWheelSheetState();
}

class _DurationWheelSheetState extends State<DurationWheelSheet> {
  late int _totalSeconds;
  double _lastAngle = 0.0;
  bool _isDragging = false;

  static const _quickPresets = [15, 30, 45, 60, 90, 120, 180, 300];

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.initialSeconds > 0 ? widget.initialSeconds : 30;
    _lastAngle = _angleForSeconds(_totalSeconds % 60);
  }

  double _angleForSeconds(int seconds) {
    // 0s is top (-pi/2), 15s is right (0), 30s is bottom (pi/2), 45s is left (pi)
    final fraction = (seconds % 60) / 60.0;
    return fraction * 2 * math.pi - (math.pi / 2);
  }

  void _onPanStart(Offset localPosition, Size size) {
    _isDragging = true;
    _updateAngleFromPosition(localPosition, size, isInitial: true);
  }

  void _onPanUpdate(Offset localPosition, Size size) {
    _updateAngleFromPosition(localPosition, size, isInitial: false);
  }

  void _onPanEnd() {
    _isDragging = false;
  }

  void _updateAngleFromPosition(
    Offset localPosition,
    Size size, {
    required bool isInitial,
  }) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Ignore taps too close to the dead center to prevent jitter
    if (dist < 20) return;

    var angle = math.atan2(dy, dx); // [-pi, pi]

    if (isInitial) {
      _lastAngle = angle;
      return;
    }

    // Compute angular delta
    var delta = angle - _lastAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;

    // Convert angular delta to seconds delta (2pi rad = 60 sec => 1 sec = 2pi / 60 rad)
    final secondsDelta = (delta / (2 * math.pi)) * 60;

    if (secondsDelta.abs() >= 0.5) {
      final intSecDelta = secondsDelta.round();
      final newSec = (_totalSeconds + intSecDelta).clamp(1, 3600);
      if (newSec != _totalSeconds) {
        Haptics.light();
        setState(() {
          _totalSeconds = newSec;
        });
      }
      _lastAngle = angle;
    }
  }

  void _adjustSeconds(int delta) {
    Haptics.medium();
    setState(() {
      _totalSeconds = (_totalSeconds + delta).clamp(1, 3600);
      _lastAngle = _angleForSeconds(_totalSeconds % 60);
    });
  }

  void _setExactSeconds(int sec) {
    Haptics.selection();
    setState(() {
      _totalSeconds = sec.clamp(1, 3600);
      _lastAngle = _angleForSeconds(_totalSeconds % 60);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _totalSeconds ~/ 60;
    final seconds = _totalSeconds % 60;
    final bottomPad = MediaQuery.of(context).padding.bottom + 12;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.timer_outlined,
                    color: Colors.teal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set Duration',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.exerciseName != null)
                        Text(
                          widget.exerciseName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ── Circular Wheel Dial (1 circle = 60s) ──
          LayoutBuilder(
            builder: (context, constraints) {
              final dialSize = math.min(constraints.maxWidth * 0.72, 240.0);
              return GestureDetector(
                onPanStart: (details) => _onPanStart(
                  details.localPosition,
                  Size(dialSize, dialSize),
                ),
                onPanUpdate: (details) => _onPanUpdate(
                  details.localPosition,
                  Size(dialSize, dialSize),
                ),
                onPanEnd: (_) => _onPanEnd(),
                child: SizedBox(
                  width: dialSize,
                  height: dialSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(dialSize, dialSize),
                        painter: _DurationDialPainter(
                          seconds: seconds,
                          minutes: minutes,
                          isDragging: _isDragging,
                        ),
                      ),
                      // Digital center readout
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            SetMetricFormat.formatDuration(_totalSeconds),
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.tealAccent.shade400,
                              letterSpacing: 1.0,
                            ),
                          ),
                          if (minutes > 0)
                            Text(
                              '$minutes min $seconds sec',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            Text(
                              '$seconds seconds',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '1 circle = 60s',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.teal.shade200,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Quick Increment / Decrement Buttons ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(label: '-1m', onTap: () => _adjustSeconds(-60)),
                const SizedBox(width: 8),
                _StepButton(label: '-15s', onTap: () => _adjustSeconds(-15)),
                const SizedBox(width: 8),
                _StepButton(label: '-5s', onTap: () => _adjustSeconds(-5)),
                const SizedBox(width: 8),
                _StepButton(label: '+5s', onTap: () => _adjustSeconds(5)),
                const SizedBox(width: 8),
                _StepButton(label: '+15s', onTap: () => _adjustSeconds(15)),
                const SizedBox(width: 8),
                _StepButton(label: '+1m', onTap: () => _adjustSeconds(60)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick Preset Chips ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: _quickPresets.map((sec) {
                final isSelected = _totalSeconds == sec;
                final label = SetMetricFormat.formatDuration(sec);
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  selectedColor: Colors.teal.withValues(alpha: 0.25),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.teal
                        : AppColors.outlineVariant.withValues(alpha: 0.5),
                  ),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.tealAccent.shade400
                        : AppColors.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (_) => _setExactSeconds(sec),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ── Action Buttons ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {
                      Haptics.medium();
                      Navigator.pop(context, _totalSeconds);
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      'Save ${SetMetricFormat.formatDuration(_totalSeconds)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StepButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the circular 60s time dial
class _DurationDialPainter extends CustomPainter {
  final int seconds;
  final int minutes;
  final bool isDragging;

  _DurationDialPainter({
    required this.seconds,
    required this.minutes,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    // Outer background track
    final trackPaint = Paint()
      ..color = AppColors.surfaceVariant.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, trackPaint);

    // Active progress arc (seconds 0..60)
    final sweepAngle = (seconds / 60.0) * 2 * math.pi;
    final progressPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [Color(0xFF00B4D8), Color(0xFF26A69A), Color(0xFF00E676)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle > 0 ? sweepAngle : 0.01,
      false,
      progressPaint,
    );

    // Second tick marks around the ring (every 5 seconds prominent, every 1s subtle)
    final tickPaint = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;

    final majorTickPaint = Paint()
      ..color = Colors.teal.shade300
      ..strokeWidth = 2.5;

    for (var s = 0; s < 60; s++) {
      final isMajor = s % 5 == 0;
      final angle = (s / 60.0) * 2 * math.pi - (math.pi / 2);
      final outerR = radius + 6;
      final innerR = isMajor ? radius - 10 : radius - 5;

      final p1 = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );
      canvas.drawLine(p1, p2, isMajor ? majorTickPaint : tickPaint);
    }

    // Drag knob / pointer at current second position
    final currentAngle = (seconds / 60.0) * 2 * math.pi - (math.pi / 2);
    final knobCenter = Offset(
      center.dx + radius * math.cos(currentAngle),
      center.dy + radius * math.sin(currentAngle),
    );

    // Outer glow on knob
    final knobGlowPaint = Paint()
      ..color = Colors.tealAccent.withValues(alpha: isDragging ? 0.6 : 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, isDragging ? 16 : 12, knobGlowPaint);

    // Inner solid knob
    final knobPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, isDragging ? 9 : 7, knobPaint);

    final knobBorderPaint = Paint()
      ..color = const Color(0xFF00796B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(knobCenter, isDragging ? 9 : 7, knobBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _DurationDialPainter oldDelegate) {
    return oldDelegate.seconds != seconds ||
        oldDelegate.minutes != minutes ||
        oldDelegate.isDragging != isDragging;
  }
}
