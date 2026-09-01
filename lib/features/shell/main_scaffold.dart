import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/hx_nav_bar.dart';
import 'package:herculex/design_system/components/live_workout_banner.dart';
import 'package:herculex/features/dashboard/presentation/dashboard_providers.dart';
import 'package:herculex/features/dashboard/presentation/dashboard_view.dart';
import 'package:herculex/features/measurements/presentation/body_fat_ai_dialog.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/presentation/gemini_photo_analysis_dialog.dart';
import 'package:herculex/features/nutrition/presentation/label_capture_dialog.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_view.dart';
import 'package:herculex/features/profile/presentation/profile_view.dart';
import 'package:herculex/features/shell/quick_add_menu.dart';
import 'package:herculex/features/supplements/presentation/supplement_ai_scan_dialog.dart';
import 'package:herculex/features/supplements/presentation/supplement_edit_sheet.dart';
import 'package:herculex/features/workouts/presentation/exercise_ai_scan_dialog.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:herculex/features/workouts/presentation/workouts_view.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:herculex/services/platform/app_shortcuts_service.dart';
import 'package:image_picker/image_picker.dart';

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
    _pageController = PageController(
      initialPage: ref.read(mainTabIndexProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appShortcutsServiceProvider).initialize(context);
        _checkLostImageData();
      }
    });
  }

  Future<void> _checkLostImageData() async {
    try {
      if (!Platform.isAndroid) return;
      final response = await ImagePicker().retrieveLostData();
      if (response.isEmpty || response.file == null) return;
      final file = File(response.file!.path);
      if (!mounted) return;

      final pendingService = ref.read(pendingAiScanServiceProvider);
      final pendingContext = pendingService.getPendingContext();
      await pendingService.clearPendingContext();

      final currentTab = ref.read(mainTabIndexProvider);
      final type =
          pendingContext?.type ??
          (currentTab == 1
              ? AiScanContextType.food
              : currentTab == 2
              ? AiScanContextType.exercise
              : currentTab == 3
              ? AiScanContextType.bodyFat
              : AiScanContextType.supplement);

      if (!mounted) return;

      switch (type) {
        case AiScanContextType.supplement:
          final result = await SupplementAiScanDialog.show(
            context,
            initialImage: file,
          );
          if (result != null && mounted) {
            await SupplementEditSheet.show(
              context,
              existing: result.toSupplement(),
            );
          }
          break;

        case AiScanContextType.food:
          final mealKey = pendingContext?.mealKey ?? 'snack';
          final date = pendingContext?.dateIso != null
              ? DateTime.tryParse(pendingContext!.dateIso!) ?? DateTime.now()
              : DateTime.now();
          final dateOnly = DateTime(date.year, date.month, date.day);
          if (!mounted) return;
          await GeminiPhotoAnalysisDialog.show(
            context,
            imageFile: file,
            meal: Meal.fromName(mealKey),
            mealKey: mealKey,
            date: dateOnly,
          );
          break;

        case AiScanContextType.nutritionLabel:
          final mealKey = pendingContext?.mealKey ?? 'snack';
          final date = pendingContext?.dateIso != null
              ? DateTime.tryParse(pendingContext!.dateIso!) ?? DateTime.now()
              : DateTime.now();
          final dateOnly = DateTime(date.year, date.month, date.day);
          if (!mounted) return;
          await LabelCaptureDialog.show(
            context,
            imageFile: file,
            meal: Meal.fromName(mealKey),
            mealKey: mealKey,
            date: dateOnly,
          );
          break;

        case AiScanContextType.exercise:
          if (!mounted) return;
          await ExerciseAiScanDialog.show(
            context,
            initialImage: XFile(file.path),
          );
          break;

        case AiScanContextType.bodyFat:
          if (!mounted) return;
          await BodyFatAiDialog.show(context, initialImage: file);
          break;

        case AiScanContextType.dreamPhysique:
          ref.read(mainTabIndexProvider.notifier).state = 3;
          if (mounted) {
            context.push(AppRoutes.dreamPhysique);
          }
          break;

        case AiScanContextType.workoutPhoto:
          final sessionId = pendingContext?.extra?['sessionId'] as int?;
          if (sessionId != null) {
            await ref
                .read(workoutsRepositoryProvider)
                .updateSessionPhoto(sessionId, file.path);
            ref.invalidate(sessionSummaryProvider(sessionId));
            ref.invalidate(workoutSessionProvider(sessionId));
          }
          break;
      }
    } catch (e) {
      debugPrint('Error recovering lost image data: $e');
    }
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
    final dashboardEditMode = ref.watch(dashboardEditModeProvider);
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
            // Editing the dashboard grid needs the horizontal drags for its
            // resize handle and reorder gestures — a swipeable PageView
            // would otherwise win those gestures and change tabs instead.
            physics: dashboardEditMode
                ? const NeverScrollableScrollPhysics()
                : null,
            onPageChanged: (i) =>
                ref.read(mainTabIndexProvider.notifier).state = i,
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
                alignment: bannerAtTop
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                padding: EdgeInsets.only(
                  top: bannerAtTop
                      ? (MediaQuery.paddingOf(context).top + 8.0)
                      : 0.0,
                  bottom: bannerAtTop
                      ? 0.0
                      : (60.0 +
                            (MediaQuery.paddingOf(context).bottom > 0
                                ? MediaQuery.paddingOf(context).bottom + 8.0
                                : 16.0) +
                            8.0),
                ),
                child: LiveWorkoutBanner(
                  onResume: () =>
                      ref.read(mainTabIndexProvider.notifier).state = 2,
                ),
              ),
            ),
          if (_quickAddOpen)
            QuickAddMenu(
              key: _quickAddMenuKey,
              onClose: () => setState(() => _quickAddOpen = false),
              onActionSelected: (action) {
                setState(() => _quickAddOpen = false);
                action(context, ref);
              },
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
