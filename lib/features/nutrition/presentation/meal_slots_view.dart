import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../domain/meal_slots.dart';
import 'meal_slots_provider.dart';
import 'nutrient_settings_provider.dart';

class MealSlotsView extends ConsumerWidget {
  const MealSlotsView({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, MealSlot slot) async {
    final controller = TextEditingController(text: slot.label);
    final label = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _MealNameSheet(
        controller: controller,
        title: 'Rename meal',
        action: 'Save',
      ),
    );
    controller.dispose();
    if (label != null) {
      await ref.read(mealSlotsProvider.notifier).rename(slot.key, label);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final label = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _MealNameSheet(
        controller: controller,
        title: 'Add meal slot',
        action: 'Add',
      ),
    );
    controller.dispose();
    if (label != null) await ref.read(mealSlotsProvider.notifier).add(label);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(mealSlotsProvider);
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Meal slots'),
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add meal'),
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: slots.length,
        header: Card(
          color: AppColors.surfaceContainer,
          child: SwitchListTile(
            value: ref.watch(logTimestampEnabledProvider),
            onChanged: (v) =>
                ref.read(logTimestampEnabledProvider.notifier).set(v),
            secondary: Icon(Icons.schedule, color: AppColors.primary),
            title: const Text('Ask for time when logging'),
            subtitle: const Text(
                'Adds an optional time-of-day field to the food entry form.'),
          ),
        ),
        onReorder: (oldIndex, newIndex) =>
            ref.read(mealSlotsProvider.notifier).reorder(oldIndex, newIndex),
        itemBuilder: (context, index) {
          final slot = slots[index];
          return Card(
            key: ValueKey(slot.key),
            color: AppColors.surfaceContainer,
            child: ListTile(
              leading: Icon(slot.icon, color: AppColors.primary),
              title: Text(slot.label),
              subtitle: Text(slot.isBuiltIn ? 'Default slot' : 'Custom slot'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Rename',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, ref, slot),
                  ),
                  if (!slot.isBuiltIn)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          ref.read(mealSlotsProvider.notifier).remove(slot.key),
                    ),
                  const Icon(Icons.drag_handle),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MealNameSheet extends StatelessWidget {
  final TextEditingController controller;
  final String title;
  final String action;

  const _MealNameSheet({
    required this.controller,
    required this.title,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Meal name'),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _submit(context), child: Text(action)),
        ],
      ),
    );
  }

  void _submit(BuildContext context) {
    final value = controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }
}
