// lib/features/sleep/presentation/widgets/sleep_hero_gauge.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';
import 'package:herculex/features/sleep/domain/sleep_score_engine.dart';

/// Animated circular/arc recovery gauge displaying the composite sleep recovery score (0-100).
class SleepHeroGauge extends StatefulWidget {
  final SleepRecord? record;
  final SleepRecoveryScore? score;
  final double targetHours;

  const SleepHeroGauge({
    super.key,
    required this.record,
    required this.score,
    this.targetHours = 8.0,
  });

  @override
  State<SleepHeroGauge> createState() => _SleepHeroGaugeState();
}

class _SleepHeroGaugeState extends State<SleepHeroGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(SleepHeroGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score?.score != widget.score?.score) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _categoryColor(SleepRecoveryCategory category) {
    switch (category) {
      case SleepRecoveryCategory.optimal:
        return const Color(0xFF10B981); // Emerald
      case SleepRecoveryCategory.prime:
        return const Color(0xFF6366F1); // Indigo
      case SleepRecoveryCategory.fair:
        return const Color(0xFF06B6D4); // Cyan
      case SleepRecoveryCategory.deficit:
        return const Color(0xFFF59E0B); // Amber
      case SleepRecoveryCategory.critical:
        return const Color(0xFFEF4444); // Red
    }
  }

  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentScore = widget.score?.score ?? 0;
    final category = widget.score?.category ?? SleepRecoveryCategory.fair;
    final totalHours = widget.record?.totalHours ?? 0.0;
    final accentColor = _categoryColor(category);

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          // Header title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SLEEP RECOVERY INDEX',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  widget.score?.title.toUpperCase() ?? 'NO DATA',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Gauge Circle
          SizedBox(
            width: 200,
            height: 200,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                final animatedProgress =
                    (currentScore / 100.0) * _animation.value;
                final animatedScore = (currentScore * _animation.value).round();

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(200, 200),
                      painter: _ArcGaugePainter(
                        progress: animatedProgress,
                        trackColor: Colors.white.withValues(alpha: 0.06),
                        gradientColors: [
                          const Color(0xFF6366F1), // Indigo
                          const Color(0xFF8B5CF6), // Purple
                          accentColor,
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$animatedScore',
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'RECOVERY SCORE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.secondary,
                            letterSpacing: 1.0,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Secondary metrics row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniMetric(
                label: 'DURATION',
                value: totalHours > 0 ? _formatHours(totalHours) : '--',
                subtitle: 'Goal: ${widget.targetHours.toStringAsFixed(1)}h',
                icon: Icons.access_time_rounded,
                color: const Color(0xFF6366F1),
                theme: theme,
              ),
              Container(width: 1, height: 32, color: Colors.white10),
              _buildMiniMetric(
                label: 'EFFICIENCY',
                value: widget.record?.sleepEfficiency != null
                    ? '${(widget.record!.sleepEfficiency * 100).round()}%'
                    : '--',
                subtitle: 'Time in bed',
                icon: Icons.bolt_rounded,
                color: const Color(0xFF06B6D4),
                theme: theme,
              ),
              Container(width: 1, height: 32, color: Colors.white10),
              _buildMiniMetric(
                label: 'RESTING HR',
                value: widget.record?.restingHr != null
                    ? '${widget.record!.restingHr!.round()} bpm'
                    : '--',
                subtitle: 'Nocturnal HR',
                icon: Icons.favorite_rounded,
                color: const Color(0xFFEF4444),
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                fontSize: 10,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.tertiary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final List<Color> gradientColors;

  _ArcGaugePainter({
    required this.progress,
    required this.trackColor,
    required this.gradientColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;
    const startAngle = 0.75 * math.pi; // 135 deg
    const sweepAngle = 1.5 * math.pi; // 270 deg
    const strokeWidth = 14.0;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    if (progress <= 0.0) return;

    // Animated gradient arc
    final activeSweep = sweepAngle * progress.clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepAngle,
      colors: gradientColors,
    );

    final activePaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, activeSweep, false, activePaint);

    // Glowing tip dot
    final tipAngle = startAngle + activeSweep;
    final tipX = center.dx + radius * math.cos(tipAngle);
    final tipY = center.dy + radius * math.sin(tipAngle);

    final glowPaint = Paint()
      ..color = gradientColors.last.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawCircle(Offset(tipX, tipY), 6.0, glowPaint);

    final tipPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(tipX, tipY), 4.0, tipPaint);
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
