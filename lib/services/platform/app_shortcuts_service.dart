import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/presentation/widgets/quick_scan_food.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:quick_actions/quick_actions.dart';

final appShortcutsServiceProvider = Provider<AppShortcutsService>((ref) {
  return AppShortcutsService(ref);
});

final appShortcutsControllerProvider = Provider<void>((ref) {
  final shortcutsService = ref.watch(appShortcutsServiceProvider);

  // Watch all workout templates across all folders (-1 = all templates)
  ref.listen<AsyncValue<List<WorkoutTemplateData>>>(
    workoutTemplatesProvider(-1),
    (previous, next) {
      if (next.hasValue && next.value != null) {
        shortcutsService.updateShortcuts(next.value!);
      }
    },
    fireImmediately: true,
  );
});

class AppShortcutsService {
  final Ref ref;
  final QuickActions _quickActions = const QuickActions();
  bool _initialized = false;

  AppShortcutsService(this.ref);

  bool get _supported => ref.read(platformCapabilitiesProvider).hasAppShortcuts;

  void initialize(BuildContext context, WidgetRef widgetRef) {
    if (_initialized || !_supported) return;
    _initialized = true;

    _quickActions.initialize((String shortcutType) async {
      await handleShortcutAction(context, shortcutType, widgetRef);
    });
  }

  Future<void> updateShortcuts(List<WorkoutTemplateData> templates) async {
    if (!_supported) return;
    final items = <ShortcutItem>[
      const ShortcutItem(
        type: 'start_empty_workout',
        localizedTitle: 'Start Empty Workout',
        icon: 'ic_shortcut_start_workout',
      ),
      const ShortcutItem(
        type: 'quick_scan_food',
        localizedTitle: 'Scan Food',
        icon: 'ic_shortcut_scan_food',
      ),
    ];

    // Up to 2 most relevant/recent templates
    for (final template in templates.take(2)) {
      items.add(
        ShortcutItem(
          type: 'template_${template.id}',
          localizedTitle: template.name,
          icon: 'ic_shortcut_workout_template',
        ),
      );
    }

    try {
      await _quickActions.setShortcutItems(items);
    } catch (e) {
      debugPrint('Error setting app shortcut items: $e');
    }
  }

  Future<void> handleShortcutAction(
    BuildContext context,
    String shortcutType,
    WidgetRef widgetRef,
  ) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;

      if (shortcutType == 'start_empty_workout') {
        // 1. Switch to Workouts tab
        ref.read(mainTabIndexProvider.notifier).state = 2;

        // 2. Start empty session if no active session
        final active = ref.read(activeSessionProvider).asData?.value;
        if (active == null) {
          final repo = ref.read(workoutsRepositoryProvider);
          await repo.startSession();
        }
      } else if (shortcutType == 'quick_scan_food') {
        // 1. Switch to Nutrition tab
        ref.read(mainTabIndexProvider.notifier).state = 1;

        if (context.mounted) {
          await scanAndLogFood(context, widgetRef);
        }
      } else if (shortcutType.startsWith('template_')) {
        final templateIdStr = shortcutType.replaceFirst('template_', '');
        final templateId = int.tryParse(templateIdStr);
        if (templateId != null) {
          // 1. Switch to Workouts tab
          ref.read(mainTabIndexProvider.notifier).state = 2;

          // 2. Start session from template if no session active
          final active = ref.read(activeSessionProvider).asData?.value;
          if (active == null) {
            final templatesRepo = ref.read(templatesRepositoryProvider);
            await templatesRepo.startSessionFromTemplate(templateId);
          }
        }
      }
    });
  }
}
