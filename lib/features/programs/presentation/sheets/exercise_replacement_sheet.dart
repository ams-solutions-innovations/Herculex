import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_text_field.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/exercise_substitution.dart';

/// Opaque sheet used when replacing an exercise during plan review.
///
/// Keeping this as an [HxSheet] matters because the app theme intentionally
/// makes scaffold backgrounds transparent. A hand-rolled container using that
/// colour therefore reveals the workout below it.
class ExerciseReplacementSheet extends ConsumerStatefulWidget {
  const ExerciseReplacementSheet({
    super.key,
    required this.current,
    required this.candidates,
  });
  final ExerciseCatalogData current;
  final List<ExerciseCatalogData> candidates;

  @override
  ConsumerState<ExerciseReplacementSheet> createState() =>
      _ExerciseReplacementSheetState();
}

class _ExerciseReplacementSheetState
    extends ConsumerState<ExerciseReplacementSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  ProgramExerciseReplacementScope _scope =
      ProgramExerciseReplacementScope.thisWave;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentIds =
        ref.watch(recentExerciseIdsProvider).valueOrNull ?? const <int>{};
    final ranked = ExerciseSubstitution.getRankedSubstitutes(
      original: widget.current,
      candidates: widget.candidates,
      recentExerciseIds: recentIds,
    );
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? ranked
        : ranked
              .where(
                (match) =>
                    match.exercise.name.toLowerCase().contains(query) ||
                    match.exercise.primaryMuscle.toLowerCase().contains(
                      query,
                    ) ||
                    match.exercise.equipment.toLowerCase().contains(query),
              )
              .toList();
    return HxSheet(
      scrollable: false,
      title: 'Choose a replacement',
      subtitle: 'Biomechanically similar options for ${widget.current.name}.',
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .64,
        child: Column(
          children: [
            PremiumTextField(
              controller: _searchController,
              hintText: 'Search exercises',
              prefixIcon: Icons.search_rounded,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Apply replacement to',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ScopeChoice(
                  label: 'This wave',
                  recommended: true,
                  selected: _scope == ProgramExerciseReplacementScope.thisWave,
                  onTap: () => setState(
                    () => _scope = ProgramExerciseReplacementScope.thisWave,
                  ),
                ),
                _ScopeChoice(
                  label: 'This and future waves',
                  selected:
                      _scope ==
                      ProgramExerciseReplacementScope.thisAndFutureWaves,
                  onTap: () => setState(
                    () => _scope =
                        ProgramExerciseReplacementScope.thisAndFutureWaves,
                  ),
                ),
                _ScopeChoice(
                  label: 'Entire block',
                  selected:
                      _scope == ProgramExerciseReplacementScope.entireBlock,
                  onTap: () => setState(
                    () => _scope = ProgramExerciseReplacementScope.entireBlock,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                switch (_scope) {
                  ProgramExerciseReplacementScope.thisWave =>
                    'Recommended — changes only this continuous run of the exercise.',
                  ProgramExerciseReplacementScope.thisAndFutureWaves =>
                    'Keeps earlier waves and replaces this wave plus all later ones.',
                  ProgramExerciseReplacementScope.entireBlock =>
                    'Uses this replacement for every week in the block.',
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty
                            ? 'No compatible alternatives are available yet.'
                            : 'No matching exercises found.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final match = matches[index];
                        final exercise = match.exercise;
                        final strong = match.percentage >= 80;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          tileColor: AppColors.surfaceContainerLowest,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Text(
                            exercise.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${exercise.primaryMuscle} · ${exercise.equipment}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (strong
                                              ? AppColors.primary
                                              : AppColors.secondary)
                                          .withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${match.percentage}%',
                                  style: TextStyle(
                                    color: strong
                                        ? AppColors.primary
                                        : AppColors.secondary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          onTap: () => Navigator.pop(
                            context,
                            ExerciseReplacementSelection(
                              exercise: exercise,
                              scope: _scope,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result of the exercise chooser, including the explicit rotation scope.
class ExerciseReplacementSelection {
  const ExerciseReplacementSelection({
    required this.exercise,
    required this.scope,
  });

  final ExerciseCatalogData exercise;
  final ProgramExerciseReplacementScope scope;
}

class _ScopeChoice extends StatelessWidget {
  const _ScopeChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(recommended ? '$label · Recommended' : label),
    selected: selected,
    onSelected: (_) => onTap(),
    selectedColor: AppColors.primary.withValues(alpha: .16),
    side: BorderSide(
      color: selected
          ? AppColors.primary
          : AppColors.outlineVariant.withValues(alpha: .55),
    ),
    labelStyle: TextStyle(
      color: selected ? AppColors.primary : AppColors.secondary,
      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
    ),
  );
}
