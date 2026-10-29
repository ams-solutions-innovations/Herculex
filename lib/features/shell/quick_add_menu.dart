import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/fasting/application/fasting_providers.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/presentation/end_fast_dialog.dart';
import 'package:herculex/features/gyms/presentation/gym_picker_sheet.dart';
import 'package:herculex/features/measurements/presentation/quick_log_weight.dart';
import 'package:herculex/features/nutrition/presentation/sheets/food_picker_sheet.dart';
import 'package:herculex/features/nutrition/presentation/widgets/quick_scan_food.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';

/// Backdrop + staggered action list behind the nav bar's "+" button.
///
/// Actions are context-aware: fasting flips between "Start Quick Fast" and
/// "End Fast" depending on whether a session is already running.
class QuickAddMenu extends ConsumerStatefulWidget {
  const QuickAddMenu({
    super.key,
    required this.onClose,
    this.onActionSelected,
    this.leftAnchor,
  });

  final VoidCallback onClose;

  /// Set when the "+" lives on the side rail (wide windows): the actions open
  /// beside it, from this distance off the left edge, instead of rising above
  /// the bottom bar's button on the right.
  final double? leftAnchor;
  final void Function(
    Future<void> Function(BuildContext context, WidgetRef ref) action,
  )?
  onActionSelected;

  @override
  ConsumerState<QuickAddMenu> createState() => QuickAddMenuState();
}

class QuickAddMenuState extends ConsumerState<QuickAddMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: HxMotion.slower,
  )..forward();
  bool _busy = false;

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
    if (_busy) return;
    _busy = true;
    await _controller.reverse();
    if (mounted) widget.onClose();
  }

  Future<void> _run(
    Future<void> Function(BuildContext context, WidgetRef ref) action,
  ) async {
    if (_busy) return;
    _busy = true;
    await _controller.reverse();
    if (widget.onActionSelected != null) {
      widget.onActionSelected!(action);
    } else {
      if (mounted) widget.onClose();
      if (mounted) await action(context, ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final activeFast = ref.watch(activeFastingSessionProvider).asData?.value;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final leftAnchored = widget.leftAnchor != null;
    final caps = ref.read(platformCapabilitiesProvider);

    final items = <_QuickAddItem>[
      _QuickAddItem(
        icon: Icons.restaurant_menu_rounded,
        label: 'Log food',
        accent: hx.domainNutrition,
        onTap: () => _run((ctx, ref) async {
          final today = DateUtils.dateOnly(DateTime.now());
          await FoodPickerSheet.show(ctx, date: today, mealKey: 'snack');
        }),
      ),
      _QuickAddItem(
        icon: Icons.qr_code_scanner_rounded,
        label: 'Scan barcode',
        accent: hx.domainNutrition,
        onTap: () => _run((ctx, ref) => scanAndLogFood(ctx, ref)),
      ),
      _QuickAddItem(
        icon: Icons.monitor_weight_outlined,
        label: 'Log weight',
        accent: hx.domainRecovery,
        onTap: () => _run((ctx, ref) => quickLogWeight(ctx, ref)),
      ),
      if (caps.hasLiveWorkout)
        _QuickAddItem(
          icon: Icons.fitness_center_rounded,
          label: 'Quick workout',
          accent: hx.domainTraining,
          onTap: () => _run((ctx, ref) async {
            final gym = await GymPickerSheet.resolve(ctx, ref);
            if (gym.cancelled) return;
            ref.read(mainTabIndexProvider.notifier).state = 2;
            await ref
                .read(workoutsRepositoryProvider)
                .startSession(gymId: gym.gymId);
          }),
        ),
      // Joining a session scans a QR code with the phone; not on the web.
      if (caps.isNative)
        _QuickAddItem(
          icon: Icons.group_rounded,
          label: 'Gym Buddy',
          accent: hx.domainTraining,
          onTap: () => _run((ctx, ref) async {
            ctx.push(AppRoutes.gymBuddy);
          }),
        ),
      activeFast == null
          ? _QuickAddItem(
              icon: Icons.play_circle_outline_rounded,
              label: 'Start Quick Fast',
              accent: hx.domainFasting,
              onTap: () => _run((ctx, ref) async {
                await ref
                    .read(fastingRepositoryProvider)
                    .startSession(FastingPlan.quickFast.targetSeconds);
              }),
            )
          : _QuickAddItem(
              icon: Icons.stop_circle_outlined,
              label: 'End Fast',
              accent: hx.domainFasting,
              onTap: () => _run((ctx, ref) async => confirmEndFast(ctx, ref)),
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
                color: Colors.black.withValues(alpha: 0.45 * _controller.value),
              ),
            ),
          ),
        ),
        Positioned(
          left: leftAnchored ? widget.leftAnchor : HxSpace.x5,
          right: leftAnchored ? null : HxSpace.x5,
          // Beside the rail the list ends level with its "+" button.
          bottom: leftAnchored ? HxSpace.x8 : bottomInset + 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: leftAnchored
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _Staggered(
                  controller: _controller,
                  index: i,
                  count: items.length,
                  alignment: leftAnchored
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: leftAnchored ? items[i].mirrored() : items[i],
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
    this.alignment = Alignment.centerRight,
  });

  final AnimationController controller;
  final int index;
  final int count;
  final Widget child;

  /// The side the item grows from — the side its "+" is on.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    // Last item enters first (closest to the "+"), so the reveal reads as
    // radiating outward from the button it came from.
    final order = count - 1 - index;
    final start = (order * 0.08).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(
        start,
        (start + 0.4).clamp(0.0, 1.0),
        curve: HxMotion.emphasizedOvershoot,
      ),
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
              alignment: alignment,
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
    this.iconFirst = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  /// Icon on the side nearest the "+" button: right on phones, left beside
  /// the side rail.
  final bool iconFirst;

  _QuickAddItem mirrored() => _QuickAddItem(
    icon: icon,
    label: label,
    accent: accent,
    onTap: onTap,
    iconFirst: !iconFirst,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = HxGlass(
      borderRadius: HxRadius.pillAll,
      padding: const EdgeInsets.symmetric(
        horizontal: HxSpace.x4,
        vertical: HxSpace.x2 + 2,
      ),
      child: Text(label, style: theme.textTheme.labelLarge),
    );
    final bubble = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 20),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconFirst
              ? [bubble, const SizedBox(width: HxSpace.x3), pill]
              : [pill, const SizedBox(width: HxSpace.x3), bubble],
        ),
      ),
    );
  }
}
