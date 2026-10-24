import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';

class RpeOption {
  final int valueX10;
  final String label;
  final String rir;
  final String description;
  final Color color;

  const RpeOption({
    required this.valueX10,
    required this.label,
    required this.rir,
    required this.description,
    required this.color,
  });
}

/// Full-screen RPE Selection view presented when a set is completed or edited.
class FullScreenRpePicker extends ConsumerWidget {
  final String exerciseName;
  final String setLabel;
  final String? performanceSubtitle;
  final int? initialRpeX10;

  const FullScreenRpePicker({
    super.key,
    required this.exerciseName,
    required this.setLabel,
    this.performanceSubtitle,
    this.initialRpeX10,
  });

  static const List<RpeOption> options = [
    RpeOption(
      valueX10: 100,
      label: '10',
      rir: '0 RIR',
      description: 'Maximum effort • Absolute limit, 0 reps in reserve',
      color: Color(0xFFEF4444),
    ),
    RpeOption(
      valueX10: 95,
      label: '9.5',
      rir: '0–1 RIR',
      description: 'Extreme effort • Maybe 1 more rep with breakdown',
      color: Color(0xFFF97316),
    ),
    RpeOption(
      valueX10: 90,
      label: '9',
      rir: '1 RIR',
      description: 'Heavy effort • Definitely 1 more clean rep',
      color: Color(0xFFFB923C),
    ),
    RpeOption(
      valueX10: 85,
      label: '8.5',
      rir: '1–2 RIR',
      description: 'Hard effort • Solid set, 1 to 2 reps left',
      color: Color(0xFFF59E0B),
    ),
    RpeOption(
      valueX10: 80,
      label: '8',
      rir: '2 RIR',
      description: 'Challenging • Good bar speed, 2 reps in reserve',
      color: Color(0xFFEAB308),
    ),
    RpeOption(
      valueX10: 75,
      label: '7.5',
      rir: '2–3 RIR',
      description: 'Moderate-heavy • Fast bar speed, 2-3 reps left',
      color: Color(0xFF84CC16),
    ),
    RpeOption(
      valueX10: 70,
      label: '7',
      rir: '3 RIR',
      description: 'Moderate effort • 3 reps in reserve',
      color: Color(0xFF22C55E),
    ),
    RpeOption(
      valueX10: 65,
      label: '6.5',
      rir: '3–4 RIR',
      description: 'Light-moderate • 3 to 4 reps in reserve',
      color: Color(0xFF14B8A6),
    ),
    RpeOption(
      valueX10: 60,
      label: '6',
      rir: '4+ RIR',
      description: 'Light effort • Warmup speed, very easy',
      color: Color(0xFF06B6D4),
    ),
    RpeOption(
      valueX10: 50,
      label: '<6',
      rir: '5+ RIR',
      description: 'Minimal effort • Light warmup / warmup sets',
      color: Color(0xFF64748B),
    ),
  ];

  /// Shows the full-screen RPE selector.
  /// Returns the chosen `rpeX10` (e.g. 85), `-1` if cleared, or `null` if dismissed/skipped.
  static Future<int?> show(
    BuildContext context, {
    required String exerciseName,
    required String setLabel,
    String? performanceSubtitle,
    int? initialRpeX10,
  }) {
    return showGeneralDialog<int?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'RPE Selection',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) => FullScreenRpePicker(
        exerciseName: exerciseName,
        setLabel: setLabel,
        performanceSubtitle: performanceSubtitle,
        initialRpeX10: initialRpeX10,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final restTimer = ref.watch(restTimerProvider);
    final now = ref.watch(clockProvider).now();
    final remainingRest = restTimer.remainingSecondsFrom(now);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar with Close, Set Info & Skip ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainer,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 22),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                  const Spacer(),
                  if (restTimer.isRunning && remainingRest > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Resting ${(remainingRest ~/ 60).toString().padLeft(2, '0')}:${(remainingRest % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Header Information ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      setLabel.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    exerciseName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (performanceSubtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      performanceSubtitle!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Rate Your Effort (RPE)',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'How many more reps could you have completed?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Full-Screen RPE Options List ──
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final opt = options[idx];
                  final isSelected = initialRpeX10 == opt.valueX10;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop(opt.valueX10);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? opt.color.withValues(alpha: 0.22)
                              : AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? opt.color
                                : AppColors.outlineVariant.withValues(
                                    alpha: 0.35,
                                  ),
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: opt.color.withValues(alpha: 0.25),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Value badge
                            Container(
                              width: 58,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: opt.color.withValues(
                                  alpha: isSelected ? 1.0 : 0.2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                opt.label,
                                style: TextStyle(
                                  color: isSelected ? Colors.black : opt.color,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: opt.color.withValues(
                                            alpha: 0.18,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          opt.rir,
                                          style: TextStyle(
                                            color: opt.color,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    opt.description,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.onSurface
                                          : AppColors.onSurfaceVariant,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check_circle_rounded,
                                color: opt.color,
                                size: 24,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Clear RPE Button (if editing existing) ──
            if (initialRpeX10 != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Clear RPE'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                  ),
                  onPressed: () {
                    Haptics.light();
                    Navigator.of(context).pop(-1);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
