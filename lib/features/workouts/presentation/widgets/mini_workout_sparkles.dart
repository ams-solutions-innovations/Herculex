import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:herculex/theme/haptics.dart';
import 'package:herculex/theme/tokens/tokens.dart';

/// Interactive check button for mini workouts with a spring pop,
/// shockwave expansion, and sparkle particle burst.
class MiniWorkoutCheckButton extends StatefulWidget {
  const MiniWorkoutCheckButton({
    super.key,
    required this.isDone,
    required this.onPressed,
    this.size = 38.0,
    this.completedCount,
    this.targetCount,
  });

  final bool isDone;
  final VoidCallback onPressed;
  final double size;
  final int? completedCount;
  final int? targetCount;

  @override
  State<MiniWorkoutCheckButton> createState() => _MiniWorkoutCheckButtonState();
}

class _MiniWorkoutCheckButtonState extends State<MiniWorkoutCheckButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _shockwaveAnim;
  late final Animation<double> _shockwaveAlpha;

  final List<_Sparkle> _sparkles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.72,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.72,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
    ]).animate(_ctrl);

    _shockwaveAnim = Tween<double>(begin: 0.8, end: 2.2).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.15, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    _shockwaveAlpha = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    _ctrl.addListener(() {
      if (_sparkles.isNotEmpty) {
        final progress = _ctrl.value;
        for (final s in _sparkles) {
          s.update(progress);
        }
        setState(() {});
      }
    });

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _sparkles.clear();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _trigger() {
    Haptics.medium();
    _spawnSparkles();
    _ctrl.forward(from: 0.0);
    widget.onPressed();
  }

  void _spawnSparkles() {
    _sparkles.clear();
    const count = 16;
    final colors = [
      const Color(0xFF10B981), // Emerald
      const Color(0xFF38BDF8), // Cyan
      const Color(0xFFFBBF24), // Amber/Gold
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF34D399), // Mint
    ];

    for (int i = 0; i < count; i++) {
      final angle =
          (i / count) * 2 * math.pi + (_random.nextDouble() * 0.4 - 0.2);
      final speed = 26.0 + _random.nextDouble() * 28.0;
      final size = 3.0 + _random.nextDouble() * 3.5;
      final color = colors[_random.nextInt(colors.length)];
      final isStar = _random.nextBool();

      _sparkles.add(
        _Sparkle(
          angle: angle,
          speed: speed,
          size: size,
          color: color,
          isStar: isStar,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final primaryColor = hx.domainTraining;
    final successColor = const Color(0xFF10B981);

    return SizedBox(
      width: widget.size + 30,
      height: widget.size + 30,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Shockwave ripple
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              if (!_ctrl.isAnimating || _shockwaveAlpha.value <= 0.01) {
                return const SizedBox.shrink();
              }
              return Container(
                width: widget.size * _shockwaveAnim.value,
                height: widget.size * _shockwaveAnim.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (widget.isDone ? successColor : primaryColor)
                        .withValues(alpha: _shockwaveAlpha.value),
                    width: 2.0,
                  ),
                ),
              );
            },
          ),

          // Custom particle sparks
          if (_sparkles.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _SparklesPainter(_sparkles, _ctrl.value),
              ),
            ),

          // Main button
          ScaleTransition(
            scale: _scaleAnim,
            child: GestureDetector(
              onTap: _trigger,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isDone
                      ? successColor.withValues(alpha: 0.18)
                      : primaryColor.withValues(alpha: 0.12),
                  border: Border.all(
                    color: widget.isDone
                        ? successColor
                        : primaryColor.withValues(alpha: 0.45),
                    width: widget.isDone ? 2.2 : 1.5,
                  ),
                  boxShadow: widget.isDone
                      ? [
                          BoxShadow(
                            color: successColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.15),
                            blurRadius: 6,
                          ),
                        ],
                ),
                child: Center(
                  child: widget.isDone
                      ? Icon(
                          Icons.check_rounded,
                          size: widget.size * 0.6,
                          color: successColor,
                        )
                      : (widget.completedCount != null &&
                            widget.targetCount != null)
                      ? Text(
                          '+1',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: widget.size * 0.36,
                          ),
                        )
                      : Icon(
                          Icons.add_rounded,
                          size: widget.size * 0.58,
                          color: primaryColor,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented visual indicators (e.g. `● ● ○`) showing completed rounds vs daily goal.
class MiniWorkoutSegmentedProgress extends StatelessWidget {
  const MiniWorkoutSegmentedProgress({
    super.key,
    required this.completed,
    required this.total,
    this.dotSize = 9.0,
    this.spacing = 6.0,
  });

  final int completed;
  final int total;
  final double dotSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final primaryColor = hx.domainTraining;
    final successColor = const Color(0xFF10B981);
    final count = total.clamp(1, 12);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          _buildDot(
            isDone: i < completed,
            isCurrent: i == completed,
            primaryColor: primaryColor,
            successColor: successColor,
            outlineColor: hx.outlineVariant.withValues(alpha: 0.5),
            isAllDone: completed >= total,
          ),
        ],
      ],
    );
  }

  Widget _buildDot({
    required bool isDone,
    required bool isCurrent,
    required Color primaryColor,
    required Color successColor,
    required Color outlineColor,
    required bool isAllDone,
  }) {
    final activeColor = isAllDone ? successColor : primaryColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      width: isDone ? dotSize * 1.15 : dotSize,
      height: isDone ? dotSize * 1.15 : dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone
            ? activeColor
            : (isCurrent
                  ? activeColor.withValues(alpha: 0.22)
                  : Colors.transparent),
        border: Border.all(
          color: isDone
              ? activeColor
              : (isCurrent
                    ? activeColor.withValues(alpha: 0.75)
                    : outlineColor),
          width: isDone ? 0 : 1.4,
        ),
        boxShadow: isDone
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.45),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: isDone && dotSize >= 12
          ? const Center(child: Icon(Icons.check, size: 9, color: Colors.white))
          : null,
    );
  }
}

/// Celebratory all-completed banner with animated shimmer and glowing aura.
class MiniWorkoutAllDoneBanner extends StatefulWidget {
  const MiniWorkoutAllDoneBanner({
    super.key,
    required this.totalReps,
    required this.totalSets,
  });

  final int totalReps;
  final int totalSets;

  @override
  State<MiniWorkoutAllDoneBanner> createState() =>
      _MiniWorkoutAllDoneBannerState();
}

class _MiniWorkoutAllDoneBannerState extends State<MiniWorkoutAllDoneBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final successColor = const Color(0xFF10B981);

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, child) {
        final glow = _glowCtrl.value;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                successColor.withValues(alpha: 0.18 + glow * 0.08),
                hx.surfaceContainerLowest,
                successColor.withValues(alpha: 0.08 + glow * 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: successColor.withValues(alpha: 0.4 + glow * 0.35),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: successColor.withValues(alpha: 0.15 + glow * 0.15),
                blurRadius: 16 + glow * 8,
                spreadRadius: glow * 2,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: successColor.withValues(alpha: 0.2),
                  border: Border.all(
                    color: successColor.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFFFBBF24),
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'All Mini Workouts Done! 🎯',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: hx.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.totalSets} sets • ${widget.totalReps} total reps logged today',
                      style: TextStyle(
                        fontSize: 12,
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: successColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: successColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Text(
                  '100%',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
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

class _Sparkle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final bool isStar;

  double x = 0;
  double y = 0;
  double alpha = 1.0;
  double currentSize = 0;
  double rotation = 0;

  _Sparkle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.isStar,
  });

  void update(double progress) {
    final dist = speed * Curves.easeOutCubic.transform(progress);
    x = math.cos(angle) * dist;
    y = math.sin(angle) * dist + (progress * progress * 8.0); // slight gravity
    alpha = (1.0 - progress).clamp(0.0, 1.0);
    currentSize = size * (1.0 - (progress * 0.4));
    rotation = progress * 3.14 * 2;
  }
}

class _SparklesPainter extends CustomPainter {
  final List<_Sparkle> sparkles;
  final double progress;

  _SparklesPainter(this.sparkles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final s in sparkles) {
      if (s.alpha <= 0.01) continue;

      final paint = Paint()
        ..color = s.color.withValues(alpha: s.alpha)
        ..style = PaintingStyle.fill;

      final pos = center + Offset(s.x, s.y);

      if (s.isStar) {
        _drawStar(canvas, pos, s.currentSize * 1.5, paint, s.rotation);
      } else {
        canvas.drawCircle(pos, s.currentSize, paint);
      }
    }
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
    double rotation,
  ) {
    final path = Path();
    const points = 4;
    final innerRadius = radius * 0.42;

    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : innerRadius;
      final angle = (i * math.pi / points) + rotation;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklesPainter oldDelegate) => true;
}
