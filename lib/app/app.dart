import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../features/analytics/presentation/analytics_providers.dart';
import '../features/nutrition/presentation/barcode_scanner_view.dart';
import '../features/nutrition/presentation/nutrition_providers.dart';
import '../features/shell/main_scaffold.dart';
import '../features/supplements/data/supplement_repository.dart';
import '../features/supplements/domain/supplement.dart';
import '../features/workouts/presentation/workouts_providers.dart';
import '../services/workout_notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/theme_provider.dart';
import 'router.dart';


class HerculexApp extends ConsumerStatefulWidget {
  const HerculexApp({super.key});

  @override
  ConsumerState<HerculexApp> createState() => _HerculexAppState();
}

class _HerculexAppState extends ConsumerState<HerculexApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      ref.read(authRepositoryProvider).hydrateFromNative();
    });
    WorkoutNotificationService.onNotificationTap = () {
      ref.read(mainTabIndexProvider.notifier).state = 2;
    };
    WorkoutNotificationService.instance.init();

    // Listen for the scanner deep-link from the Scanner home-screen widget.
    // When the user taps the widget, Android sends 'openScanner' via
    // the widget MethodChannel. We push the barcode scanner route.
    const widgetChannel = MethodChannel('com.ams.herculex/widget');
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openScanner' && mounted) {
        // Navigate to the nutrition tab and open the scanner.
        // BarcodeScannerView is pushed as a full-screen route from
        // nutrition_view.dart — we replicate that here from the root navigator.
        final ctx = context;
        if (ctx.mounted) {
          await Navigator.of(ctx, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const BarcodeScannerView(),
              fullscreenDialog: true,
            ),
          );
        }
      }
    });

    _lifecycleListener = AppLifecycleListener(
      onHide: _onBackground,
      onPause: _onBackground,
      onInactive: _onBackground,
      onResume: _onForeground,
      onShow: _onForeground,
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    WorkoutNotificationService.instance.cancel();
    super.dispose();
  }

  void _onBackground() {
    _syncNotification();
  }

  void _onForeground() {
    _syncNotification();
  }

  /// Reads the supplement list and fires a notification for any supplement
  /// that has [SupplementSchedule.postWorkout] set.
  void _firePostWorkoutSupplementReminder() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final repo = SupplementRepository(prefs);
      final postWorkout = repo
          .loadSupplements()
          .where((s) => s.schedule == SupplementSchedule.postWorkout)
          .map((s) => s.name)
          .toList();
      if (postWorkout.isNotEmpty) {
        WorkoutNotificationService.instance.showSupplementReminder(postWorkout);
      }
    } catch (_) {
      // Silently ignore — supplement reminder is non-critical.
    }
  }

  void _syncNotification() {
    final sessionAsync = ref.read(activeSessionProvider);
    final session = sessionAsync.asData?.value;
    if (session == null) {
      WorkoutNotificationService.instance.cancel();
      return;
    }
    final exercises =
        ref.read(sessionExercisesProvider(session.id)).asData?.value ?? [];
    String exerciseName = 'Workout in progress';
    int? currentSet;
    int? totalSets;
    double? weightKg;
    int? reps;

    if (exercises.isNotEmpty) {
      final firstWe = exercises.first;
      final catalog =
          ref.read(exerciseCatalogProvider(const ExerciseCatalogFilter())).asData?.value ?? [];
      final match = catalog
          .where((e) => e.id == firstWe.exerciseId)
          .firstOrNull;
      if (match != null) exerciseName = match.name;

      final sets = ref.read(setsForWorkoutExerciseProvider(firstWe.id)).asData?.value ?? [];
      if (sets.isNotEmpty) {
        totalSets = sets.length;
        final nextUncompleted = sets.where((s) => !s.isCompleted).firstOrNull;
        final targetSet = nextUncompleted ?? sets.last;
        currentSet = targetSet.setIndex;
        weightKg = targetSet.weightKg;
        reps = targetSet.reps;
      }
    }

    WorkoutNotificationService.instance.showOrUpdate(
      startedAt: session.startedAt,
      exerciseName: exerciseName,
      workoutName: session.name,
      currentSet: currentSet,
      totalSets: totalSets,
      weightKg: weightKg,
      reps: reps,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Initialize wear sync listening.
    ref.watch(wearSyncControllerProvider);
    ref.watch(wearWorkoutSyncControllerProvider);

    // Initialize Android home-screen widget sync.
    ref.watch(widgetMacroSyncControllerProvider);
    ref.watch(widgetCnsSyncControllerProvider);
    ref.watch(widgetRecoverySyncControllerProvider);

    final router = ref.watch(routerProvider);
    WorkoutNotificationService.onNotificationTap = () {
      router.go('/workout');
    };

    // Keep notification in sync when active session changes.
    ref.listen(activeSessionProvider, (previous, next) {
      _syncNotification();
      // Fire post-workout supplement reminder when session transitions active→null.
      final hadSession = previous?.asData?.value != null;
      final hasSession = next.asData?.value != null;
      if (hadSession && !hasSession) {
        _firePostWorkoutSupplementReminder();
      }
    });

    final themeMode = ref.watch(themeModeProvider);

    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };

    AppColors.brightness = effectiveBrightness;

    final isDark = effectiveBrightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp.router(
      key: ValueKey('${themeMode.name}_${effectiveBrightness.name}'), // Rebuild widget tree when theme changes
      title: 'Herculex',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
