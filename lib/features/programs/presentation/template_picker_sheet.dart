import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../workouts/presentation/template_builder_view.dart';
import '../../workouts/presentation/workouts_providers.dart';

/// Picks one of the user's real workout templates, grouped by folder.
///
/// This is what the old builder's "CHOOSE TEMPLATE" sheet pretended to be — it
/// listed seven hardcoded strings and never touched the templates table.
class TemplatePickerSheet extends ConsumerStatefulWidget {
  const TemplatePickerSheet({super.key});

  static Future<WorkoutTemplateData?> show(BuildContext context) {
    return AppBottomSheet.show<WorkoutTemplateData>(
      context,
      builder: (_) => const TemplatePickerSheet(),
    );
  }

  @override
  ConsumerState<TemplatePickerSheet> createState() =>
      _TemplatePickerSheetState();
}

class _TemplatePickerSheetState extends ConsumerState<TemplatePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = ref.watch(workoutFoldersProvider).value ?? const [];
    // -1 means "every template regardless of folder" in TemplatesRepository.
    final all = ref.watch(workoutTemplatesProvider(-1));

    return AppBottomSheet(
      title: 'Choose a template',
      subtitle: 'Linked live — editing it updates future sessions',
      initialSize: 0.7,
      child: all.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text(
          'Could not load templates.',
          style: TextStyle(color: AppColors.secondary),
        ),
        data: (templates) {
          if (templates.isEmpty) return _empty(theme);

          final filtered = _query.isEmpty
              ? templates
              : templates
                    .where(
                      (t) =>
                          t.name.toLowerCase().contains(_query.toLowerCase()),
                    )
                    .toList();

          final byFolder = <int?, List<WorkoutTemplateData>>{};
          for (final t in filtered) {
            (byFolder[t.folderId] ??= []).add(t);
          }

          final groups = <({String label, List<WorkoutTemplateData> items})>[
            for (final f in folders)
              if (byFolder[f.id]?.isNotEmpty ?? false)
                (label: '${f.emoji}  ${f.name}', items: byFolder[f.id]!),
            if (byFolder[null]?.isNotEmpty ?? false)
              (label: 'No folder', items: byFolder[null]!),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search templates',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                ),
              ),
              const SizedBox(height: 16),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No template matches "$_query".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.secondary),
                  ),
                ),
              for (final group in groups) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    group.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                for (final t in group.items)
                  _TemplateRow(
                    template: t,
                    onTap: () {
                      Haptics.selection();
                      Navigator.pop(context, t);
                    },
                  ),
                const SizedBox(height: 16),
              ],
              TextButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final created = await TemplateBuilderView.show(
                    context,
                    returnsSelection: true,
                  );
                  if (created != null) navigator.pop(created);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a new template'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 40,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No templates yet',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Build one now and it will be linked to this session.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final created = await TemplateBuilderView.show(
                context,
                returnsSelection: true,
              );
              if (created != null) navigator.pop(created);
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('New template'),
          ),
        ],
      ),
    );
  }
}

class _TemplateRow extends ConsumerWidget {
  const _TemplateRow({required this.template, required this.onTap});

  final WorkoutTemplateData template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count =
        ref.watch(templateExercisesProvider(template.id)).value?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.fitness_center, size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      count == 1 ? '1 exercise' : '$count exercises',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.secondary),
            ],
          ),
        ),
      ),
    );
  }
}
