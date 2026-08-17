import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../../../widgets/premium_button.dart';
import '../domain/fasting_plan.dart';
import 'fasting_providers.dart';
import 'widgets/active_fast_panel.dart';
import 'widgets/fasting_history.dart';
import 'widgets/fasting_insights.dart';
import 'widgets/start_fast_panel.dart';

/// Fasting's first-class page (`/fasting`), replacing the 1,100-line bottom
/// sheet it used to be. A large clock motif sits low-opacity behind the
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
    final hx = context.hx;
    final activeAsync = ref.watch(activeFastingSessionProvider);
    final active = activeAsync.asData?.value;
    final isLoaded = activeAsync.hasValue;

    return Stack(
      children: [
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Icon(
                Icons.watch_later_rounded,
                size: 320,
                color: hx.domainFasting.withValues(alpha: hx.isDark ? 0.05 : 0.07),
              ),
            ),
          ),
        ),
        HxScreenShell(
          title: 'Fasting',
          actions: [
            HxCircleButton(
              icon: Icons.alarm_rounded,
              tooltip: 'Fasting schedule',
              onTap: () => context.push('/fasting/schedule'),
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
            const FastingInsights(),
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

    await ref
        .read(fastingNotificationSchedulerProvider)
        .scheduleFastingGoal(targetTime, planName: planName);
  }
}
