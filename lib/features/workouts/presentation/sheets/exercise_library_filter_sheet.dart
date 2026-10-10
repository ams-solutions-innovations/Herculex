import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Filter values the library resolves in memory rather than through the
/// catalog facet matcher.
abstract final class ExerciseLibraryFilters {
  static const all = 'All';
  static const custom = 'Custom';
  static const coreLifts = 'Core lifts';
  static const liked = 'Liked';

  /// Filters the catalog query cannot answer on its own.
  static const inMemory = {custom, coreLifts, liked};

  static const groups = <(String, List<String>)>[
    ('Mine', [all, coreLifts, liked, custom]),
    (
      'Muscle',
      [
        'Chest',
        'Back',
        'Shoulders',
        'Biceps',
        'Triceps',
        'Legs',
        'Quads',
        'Hamstrings',
        'Glutes',
        'Calves',
        'Core',
        'Abs',
        'Forearms',
      ],
    ),
    ('Movement', ['Compound', 'Isolation', 'Push', 'Pull']),
    ('Type', ['Cardio', 'Calisthenics']),
  ];
}

/// Bottom sheet replacing the library's chip row. Pops the chosen filter
/// ([ExerciseLibraryFilters.all] to clear), or null when dismissed.
class ExerciseLibraryFilterSheet extends StatelessWidget {
  const ExerciseLibraryFilterSheet({super.key, required this.selected});

  /// Current filter; null means "All".
  final String? selected;

  static Future<String?> show(BuildContext context, {String? selected}) {
    return HxSheet.show<String>(
      context,
      builder: (_) => ExerciseLibraryFilterSheet(selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final current = selected ?? ExerciseLibraryFilters.all;

    return HxSheet(
      title: 'Filter exercises',
      initialSize: 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (heading, options) in ExerciseLibraryFilters.groups) ...[
            Text(
              heading.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: hx.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: HxSpace.x2),
            Wrap(
              spacing: HxSpace.x2,
              runSpacing: HxSpace.x2,
              children: [
                for (final option in options)
                  HxTextPill(
                    label: option,
                    selected: option == current,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
              ],
            ),
            const SizedBox(height: HxSpace.x4),
          ],
        ],
      ),
    );
  }
}
