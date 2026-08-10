import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_shortcuts_service.dart';
import '../../widgets/floating_nav_bar.dart';
import '../../widgets/live_workout_banner.dart';
import '../dashboard/presentation/dashboard_view.dart';
import '../nutrition/presentation/nutrition_view.dart';
import '../profile/presentation/profile_view.dart';
import '../programs/presentation/training_blocks_view.dart';
import '../workouts/presentation/workouts_providers.dart';
import '../workouts/presentation/workouts_view.dart';

/// The five-tab home shell. Bottom-nav index drives which feature view shows.
/// Profile is the right-most tab; it stays reachable from the Dashboard
/// avatar too. Insights is reachable from Profile.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

final mainTabIndexProvider = StateProvider<int>((ref) => 0);

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  static const _tabs = <Widget>[
    DashboardView(),
    NutritionView(),
    WorkoutsView(),
    TrainingBlocksView(),
    ProfileView(),
  ];

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: ref.read(mainTabIndexProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appShortcutsServiceProvider).initialize(context);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appShortcutsControllerProvider);
    final index = ref.watch(mainTabIndexProvider);
    final hasActiveSession =
        ref.watch(activeSessionProvider).asData?.value != null;
    final showBanner = hasActiveSession && index != 2;
    final bannerAtTop = ref.watch(liveWorkoutBannerAtTopProvider);

    ref.listen<int>(mainTabIndexProvider, (prev, next) {
      if (!_pageController.hasClients) return;
      final current = _pageController.page?.round() ?? 0;
      if (current == next) return;
      // Jumping more than 1 tab: use jumpToPage to avoid animating through
      // intermediate pages (which causes visible jitter as intermediate screens
      // render). The nav-bar indicator animates independently via AnimatedPositioned.
      if ((next - current).abs() > 1) {
        _pageController.jumpToPage(next);
      } else {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (i) => ref.read(mainTabIndexProvider.notifier).state = i,
            children: _tabs,
          ),
          // LiveWorkoutBanner placed independently in the Stack to allow smooth alignment animation
          if (showBanner)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                alignment: bannerAtTop ? Alignment.topCenter : Alignment.bottomCenter,
                padding: EdgeInsets.only(
                  top: bannerAtTop ? (MediaQuery.of(context).padding.top + 8.0) : 0.0,
                  bottom: bannerAtTop ? 0.0 : (MediaQuery.of(context).padding.bottom + 92.0),
                ),
                child: LiveWorkoutBanner(
                  onResume: () => ref.read(mainTabIndexProvider.notifier).state = 2,
                ),
              ),
            ),
          // FloatingNavBar positioned at the bottom of the screen
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavBar(
              currentIndex: index,
              onTap: (i) => ref.read(mainTabIndexProvider.notifier).state = i,
            ),
          ),
        ],
      ),
    );
  }
}
