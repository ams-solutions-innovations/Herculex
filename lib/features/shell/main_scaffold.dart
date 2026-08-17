import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_shortcuts_service.dart';
import '../../ui/hx_nav_bar.dart';
import '../../widgets/live_workout_banner.dart';
import '../dashboard/presentation/dashboard_view.dart';
import '../nutrition/presentation/nutrition_view.dart';
import '../profile/presentation/profile_view.dart';
import '../workouts/presentation/workouts_providers.dart';
import '../workouts/presentation/workouts_view.dart';
import 'quick_add_menu.dart';

/// The four-tab home shell. Bottom-nav index drives which feature view
/// shows; the nav bar's central "+" opens the quick-add menu instead of
/// selecting a tab. Programs lives inside the Workouts tab as a top segment
/// (see workouts_view.dart) rather than as a fifth destination — contextual
/// navigation belongs at the top of a section, not in a second bottom bar.
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
    ProfileView(),
  ];

  late final PageController _pageController;
  final _quickAddMenuKey = GlobalKey<QuickAddMenuState>();
  bool _quickAddOpen = false;

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
          if (_quickAddOpen)
            QuickAddMenu(
              key: _quickAddMenuKey,
              onClose: () => setState(() => _quickAddOpen = false),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: HxNavBar(
              currentIndex: index,
              onTap: (i) => ref.read(mainTabIndexProvider.notifier).state = i,
              quickAddOpen: _quickAddOpen,
              onQuickAddTap: () {
                if (_quickAddOpen) {
                  // Same reverse animation as tapping the backdrop.
                  _quickAddMenuKey.currentState?.close();
                } else {
                  setState(() => _quickAddOpen = true);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
