import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/steps/domain/step_record.dart';
import 'package:herculex/features/steps/domain/step_score_engine.dart';

/// Animated circular gradient progress ring displaying daily step progress and key telemetry.
class StepHeroProgressRing extends StatefulWidget {
  final StepRecord? record;
  final StepMovementScore? score;

  const StepHeroProgressRing({
    super.key,
    required this.record,
    required this.score,
  });

  @override
  State<StepHeroProgressRing> createState() => _StepHeroProgressRingState();
}

class _StepHeroProgressRingState extends State<StepHeroProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(StepHeroProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record?.stepCount != widget.record?.stepCount) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _zoneColor(StepActivityZone zone) => switch (zone) {
    StepActivityZone.sedentary => const Color(0xFF64748B),
    StepActivityZone.lightlyActive => const Color(0xFF38BDF8),
    StepActivityZone.optimal => const Color(0xFF10B981),
    StepActivityZone.highNeat => const Color(0xFFF59E0B),
    StepActivityZone.exhaustive => const Color(0xFFF97316),
    StepActivityZone.extreme => const Color(0xFFEF4444),
  };

  String _formatNumber(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.record;
    final score = widget.score;
    final steps = record?.stepCount ?? 0;
    final goal = record?.goal ?? 10000;
    final progress = record != null ? record.progressRatio : 0.0;
    final zone = score?.zone ?? StepActivityZone.lightlyActive;
    final accentColor = _zoneColor(zone);

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DAILY STEP TARGET',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  score?.statusLabel ?? 'ACTIVE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              final animatedProgress = (progress * _animation.value).clamp(
                0.0,
                1.5,
              );
              return CustomPaint(
                size: const Size(220, 220),
                painter: _StepRingPainter(
                  progress: animatedProgress,
                  accentColor: accentColor,
                  trackColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.08,
                  ),
                ),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.directions_walk_rounded,
                          size: 26,
                          color: accentColor,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatNumber(steps),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            fontSize: 34,
                          ),
                        ),
                        Text(
                          'of ${_formatNumber(goal)} steps',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(record?.progressPercentage ?? 0.0).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatCard(
                theme: theme,
                label: 'DISTANCE',
                value: '${(record?.distanceKm ?? 0.0).toStringAsFixed(1)} km',
                icon: Icons.place_outlined,
                color: Colors.blueAccent,
              ),
              const SizedBox(width: 8),
              _buildStatCard(
                theme: theme,
                label: 'ACTIVE KCAL',
                value: '${(record?.activeKcal ?? 0.0).toStringAsFixed(0)} kcal',
                icon: Icons.local_fire_department_outlined,
                color: Colors.orangeAccent,
              ),
              const SizedBox(width: 8),
              _buildStatCard(
                theme: theme,
                label: 'WALK TIME',
                value: '${record?.activeMinutes ?? 0} min',
                icon: Icons.timer_outlined,
                color: Colors.tealAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                fontSize: 9,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRingPainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final Color trackColor;

  _StepRingPainter({
    required this.progress,
    required this.accentColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;
    const strokeWidth = 14.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      final rect = Rect.fromCircle(center: center, radius: radius);

      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: (3 * math.pi) / 2,
          colors: [accentColor.withValues(alpha: 0.6), accentColor],
        ).createShader(rect);

      canvas.drawArc(rect, -math.pi / 2, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StepRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.trackColor != trackColor;
}
