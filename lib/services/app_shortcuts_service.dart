import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../data/local/database.dart';
import '../features/nutrition/presentation/food_picker_sheet.dart';
import '../features/shell/main_scaffold.dart';
import '../features/workouts/presentation/workouts_providers.dart';

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

  void initialize(BuildContext context) {
    if (_initialized) return;
    _initialized = true;

    _quickActions.initialize((String shortcutType) async {
      await handleShortcutAction(context, shortcutType);
    });
  }

  Future<void> updateShortcuts(List<WorkoutTemplateData> templates) async {
    final items = <ShortcutItem>[
      const ShortcutItem(
        type: 'start_empty_workout',
        localizedTitle: 'Start Empty Workout',
        icon: 'launcher_icon',
      ),
      const ShortcutItem(
        type: 'quick_scan_food',
        localizedTitle: 'Scan Food',
        icon: 'launcher_icon',
      ),
    ];

    // Up to 2 most relevant/recent templates
    for (final template in templates.take(2)) {
      items.add(
        ShortcutItem(
          type: 'template_${template.id}',
          localizedTitle: template.name,
          icon: 'launcher_icon',
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
  ) async {
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

      // 2. Open Food Picker Sheet for today's food logging
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);
      if (context.mounted) {
        await FoodPickerSheet.show(
          context,
          date: date,
          mealKey: 'lunch',
        );
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
  }
}
