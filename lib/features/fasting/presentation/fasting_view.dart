import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/presentation/fasting_providers.dart';
import 'package:herculex/features/fasting/presentation/widgets/active_fast_panel.dart';
import 'package:herculex/features/fasting/presentation/widgets/clock_dial_background.dart';
import 'package:herculex/features/fasting/presentation/widgets/fasting_history.dart';
import 'package:herculex/features/fasting/presentation/widgets/fasting_insights.dart';
import 'package:herculex/features/fasting/presentation/widgets/start_fast_panel.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_provider.dart';

/// Fasting's first-class page (`/fasting`), replacing the 1,100-line bottom
/// sheet it used to be. A minimalist clock dial motif sits behind the
/// header — the section's visual identity — and Start Fast is genuinely
/// pinned (via [HxScreenShell.pinnedBottom]) so starting the selected plan
/// never requires scrolling, not just "near the top" as the sheet had it.
class FastingView extends ConsumerStatefulWidget {
  const FastingView({super.key});

  @override
  ConsumerState<FastingView> createState() => _FastingViewState();
}

class _FastingViewState extends ConsumerState<FastingView> {
  FastingPlan _selectedPlan = FastingPlan.h16;
  int _customTargetHours = 15;
  DateTime? _customStartTime;

  @override
  Widget build(BuildContext context) {
    final activeAsync = ref.watch(activeFastingSessionProvider);
    final active = activeAsync.asData?.value;
    final isLoaded = activeAsync.hasValue;
    final hasSchedule = ref.watch(hasActiveFastingScheduleProvider);

    return Stack(
      children: [
        const Positioned(
          top: 30,
          left: 0,
          right: 0,
          child: ClockDialBackground(size: 320),
        ),
        HxScreenShell(
          title: 'Fasting',
          actions: [
            HxCircleButton(
              icon: Icons.alarm_rounded,
              tooltip: 'Fasting schedule',
              iconColor: hasSchedule ? context.hx.domainFasting : null,
              tintColor: hasSchedule
                  ? context.hx.domainFasting.withValues(alpha: 0.18)
                  : null,
              borderColor: hasSchedule
                  ? context.hx.domainFasting.withValues(alpha: 0.45)
                  : null,
              onTap: () => context.push(AppRoutes.fastingSchedule),
            ),
          ],
          pinnedBottom: isLoaded && active == null
              ? SizedBox(
                  width: double.infinity,
                  child: PremiumButton(
                    text: "START FAST NOW",
                    isPrimary: true,
                    icon: Icons.play_arrow_outlined,
                    onTap: _startFast,
                  ),
                )
              : null,
          children: [
            const FastingInsights(),
            const SizedBox(height: HxSpace.x6),
            activeAsync.when(
              data: (active) => active != null
                  ? ActiveFastPanel(active: active)
                  : StartFastPanel(
                      selectedPlan: _selectedPlan,
                      customTargetHours: _customTargetHours,
                      customStartTime: _customStartTime,
                      onPlanSelected: (p) => setState(() => _selectedPlan = p),
                      onCustomHoursChanged: (h) =>
                          setState(() => _customTargetHours = h),
                      onCustomStartTimeChanged: (t) =>
                          setState(() => _customStartTime = t),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
            const SizedBox(height: HxSpace.x8),
            const Divider(),
            const SizedBox(height: HxSpace.x6),
            const FastingHistory(),
          ],
        ),
      ],
    );
  }

  Future<void> _startFast() async {
    final targetSec = _selectedPlan == FastingPlan.custom
        ? _customTargetHours * 3600
        : _selectedPlan.targetSeconds;

    final repo = ref.read(fastingRepositoryProvider);
    await repo.startSession(targetSec, customStartTime: _customStartTime);

    // Quick Fast has no target, so there's nothing to schedule a goal
    // notification for.
    if (_selectedPlan == FastingPlan.quickFast) return;

    final started = _customStartTime ?? DateTime.now();
    final targetTime = started.add(Duration(seconds: targetSec));
    final planName = _selectedPlan == FastingPlan.custom
        ? '$_customTargetHours-Hour'
        : _selectedPlan.nameString;

    final notifEnabled = ref
        .read(notificationSettingsProvider)
        .fastingGoalReachedEnabled;
    await ref
        .read(fastingNotificationSchedulerProvider)
        .scheduleFastingGoal(
          targetTime,
          planName: planName,
          enabled: notifEnabled,
        );
  }
}
