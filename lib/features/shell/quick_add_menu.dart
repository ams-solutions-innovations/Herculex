import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/haptics.dart';
import '../../theme/tokens/tokens.dart';
import '../../ui/ui.dart';
import '../fasting/domain/fasting_plan.dart';
import '../fasting/presentation/end_fast_dialog.dart';
import '../fasting/presentation/fasting_providers.dart';
import '../gyms/presentation/gym_picker_sheet.dart';
import '../measurements/presentation/quick_log_weight.dart';
import '../nutrition/presentation/food_picker_sheet.dart';
import '../nutrition/presentation/quick_scan_food.dart';
import '../workouts/presentation/workouts_providers.dart';
import 'main_scaffold.dart';

/// Backdrop + staggered action list behind the nav bar's "+" button.
///
/// Actions are context-aware: fasting flips between "Start Quick Fast" and
/// "End Fast" depending on whether a session is already running.
class QuickAddMenu extends ConsumerStatefulWidget {
  const QuickAddMenu({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<QuickAddMenu> createState() => QuickAddMenuState();
}

class QuickAddMenuState extends ConsumerState<QuickAddMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: HxMotion.slower,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Plays the reverse animation before notifying the parent. Called both
  /// from the backdrop tap and from the nav bar's "X" button so the two
  /// close paths look identical.
  Future<void> close() => _close();

  Future<void> _close() async {
    await _controller.reverse();
    if (mounted) widget.onClose();
  }

  Future<void> _run(Future<void> Function() action) async {
    await _close();
    if (mounted) await action();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final activeFast = ref.watch(activeFastingSessionProvider).asData?.value;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final items = <_QuickAddItem>[
      _QuickAddItem(
        icon: Icons.restaurant_menu_rounded,
        label: 'Log food',
        accent: hx.domainNutrition,
        onTap: () => _run(() async {
          final today = DateUtils.dateOnly(DateTime.now());
          await FoodPickerSheet.show(context, date: today, mealKey: 'snack');
        }),
      ),
      _QuickAddItem(
        icon: Icons.qr_code_scanner_rounded,
        label: 'Scan barcode',
        accent: hx.domainNutrition,
        onTap: () => _run(() => scanAndLogFood(context, ref)),
      ),
      _QuickAddItem(
        icon: Icons.monitor_weight_outlined,
        label: 'Log weight',
        accent: hx.domainRecovery,
        onTap: () => _run(() => quickLogWeight(context, ref)),
      ),
      _QuickAddItem(
        icon: Icons.fitness_center_rounded,
        label: 'Quick workout',
        accent: hx.domainTraining,
        // Resolve the gym while the menu is still open — GymPickerSheet
        // awaits a stream first, and closing the menu before that gap
        // unmounts our context, so the picker silently no-ops.
        onTap: () async {
          final gym = await GymPickerSheet.resolve(context, ref);
          if (gym.cancelled) return;
          await _close();
          if (!mounted) return;
          ref.read(mainTabIndexProvider.notifier).state = 2;
          await ref
              .read(workoutsRepositoryProvider)
              .startSession(gymId: gym.gymId);
        },
      ),
      activeFast == null
          ? _QuickAddItem(
              icon: Icons.play_circle_outline_rounded,
              label: 'Start Quick Fast',
              accent: hx.domainFasting,
              // No target, so no goal notification to schedule — Quick Fast
              // just starts the clock.
              onTap: () => _run(() async {
                await ref
                    .read(fastingRepositoryProvider)
                    .startSession(FastingPlan.quickFast.targetSeconds);
              }),
            )
          : _QuickAddItem(
              icon: Icons.stop_circle_outlined,
              label: 'End Fast',
              accent: hx.domainFasting,
              onTap: () => _run(() async => confirmEndFast(context, ref)),
            ),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => GestureDetector(
              onTap: _close,
              child: Container(
                color: Colors.black
                    .withValues(alpha: 0.45 * _controller.value),
              ),
            ),
          ),
        ),
        Positioned(
          left: HxSpace.x5,
          right: HxSpace.x5,
          bottom: bottomInset + 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _Staggered(
                  controller: _controller,
                  index: i,
                  count: items.length,
                  child: items[i],
                ),
                if (i != items.length - 1) const SizedBox(height: HxSpace.x3),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Staggered extends StatelessWidget {
  const _Staggered({
    required this.controller,
    required this.index,
    required this.count,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Last item enters first (closest to the "+"), so the reveal reads as
    // radiating outward from the button it came from.
    final order = count - 1 - index;
    final start = (order * 0.08).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
          curve: HxMotion.emphasizedOvershoot),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: Transform.scale(
              scale: 0.85 + 0.15 * t,
              alignment: Alignment.centerRight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _QuickAddItem extends StatelessWidget {
  const _QuickAddItem({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HxGlass(
            borderRadius: HxRadius.pillAll,
            padding: const EdgeInsets.symmetric(
                horizontal: HxSpace.x4, vertical: HxSpace.x2 + 2),
            child: Text(label, style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: HxSpace.x3),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}
