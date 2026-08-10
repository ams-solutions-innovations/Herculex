import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/workouts/presentation/workouts_providers.dart';
import '../theme/colors.dart';
import '../theme/haptics.dart';

final liveWorkoutBannerAtTopProvider = StateProvider<bool>((ref) => false);

class LiveWorkoutBanner extends ConsumerStatefulWidget {
  final VoidCallback onResume;

  const LiveWorkoutBanner({super.key, required this.onResume});

  @override
  ConsumerState<LiveWorkoutBanner> createState() => _LiveWorkoutBannerState();
}

class _LiveWorkoutBannerState extends ConsumerState<LiveWorkoutBanner> {
  late Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _formatElapsed(DateTime startedAt) {
    final d = DateTime.now().difference(startedAt);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bannerAtTop = ref.watch(liveWorkoutBannerAtTopProvider);
    final sessionAsync = ref.watch(activeSessionProvider);
    final session = sessionAsync.asData?.value;
    if (session == null) return const SizedBox.shrink();

    final exercisesAsync = ref.watch(sessionExercisesProvider(session.id));
    final catalog = ref.watch(exerciseCatalogProvider(const ExerciseCatalogFilter()));

    final exercises = exercisesAsync.asData?.value ?? [];
    String exerciseName = 'Workout in progress';
    if (exercises.isNotEmpty) {
      final firstId = exercises.first.exerciseId;
      final match = catalog.asData?.value
          .where((e) => e.id == firstId)
          .firstOrNull;
      if (match != null) exerciseName = match.name;
    }

    final elapsedStr = _formatElapsed(session.startedAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: GestureDetector(
            onTap: () {
              Haptics.selection();
              widget.onResume();
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -300) {
                ref.read(liveWorkoutBannerAtTopProvider.notifier).state = true;
                Haptics.medium();
              } else if (velocity > 300) {
                ref.read(liveWorkoutBannerAtTopProvider.notifier).state = false;
                Haptics.medium();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.25),
                    AppColors.primary.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  // Pulsing green dot
                  _PulsingDot(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              (session.name != null && session.name!.isNotEmpty)
                                  ? session.name!
                                  : 'Workout in Progress',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          exerciseName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Middle pill info left of the circle button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      elapsedStr,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Toggle arrow button
                  GestureDetector(
                    onTap: () {
                      Haptics.selection();
                      ref.read(liveWorkoutBannerAtTopProvider.notifier).update((state) => !state);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        bannerAtTop
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween(begin: 0.4, end: 1.0).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF30D158), // iOS green
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}