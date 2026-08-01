import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../widgets/premium_text_field.dart';
import '../domain/exercise_substitution.dart';
import 'workouts_providers.dart';

class SmartSubstitutionSheet extends ConsumerStatefulWidget {
  final WorkoutExerciseData workoutExercise;
  final ExerciseCatalogData originalExercise;

  const SmartSubstitutionSheet({
    super.key,
    required this.workoutExercise,
    required this.originalExercise,
  });

  static void show(
    BuildContext context, {
    required WorkoutExerciseData workoutExercise,
    required ExerciseCatalogData originalExercise,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SmartSubstitutionSheet(
        workoutExercise: workoutExercise,
        originalExercise: originalExercise,
      ),
    );
  }

  @override
  ConsumerState<SmartSubstitutionSheet> createState() => _SmartSubstitutionSheetState();
}

class _SmartSubstitutionSheetState extends ConsumerState<SmartSubstitutionSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedEquipment = 'All';

  final List<String> _equipmentFilters = [
    'All',
    'Barbell',
    'Dumbbell',
    'Cable',
    'Machine',
    'Bodyweight',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
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
    final catalogAsync = ref.watch(exerciseCatalogProvider(const ExerciseCatalogFilter()));
    final recentHistoryAsync = ref.watch(recentExerciseIdsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      "Smart Substitution",
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildOriginalExercise(theme),
                    const SizedBox(height: 24),
                    Text(
                      "Filter Candidates",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PremiumTextField(
                      controller: _searchController,
                      hintText: "Search candidates by name...",
                      prefixIcon: Icons.search,
                    ),
                    const SizedBox(height: 12),
                    _buildEquipmentFilterRow(),
                    const SizedBox(height: 24),
                    Text(
                      "Suggested Biomechanical Matches",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    catalogAsync.when(
                      data: (catalog) {
                        return recentHistoryAsync.when(
                          data: (recentHistory) {
                            final matches = ExerciseSubstitution.getRankedSubstitutes(
                              original: widget.originalExercise,
                              candidates: catalog,
                              recentExerciseIds: recentHistory,
                            );

                            // Apply local interactive filters
                            var filtered = matches;
                            if (_selectedEquipment != 'All') {
                              filtered = filtered.where((m) =>
                                  m.exercise.equipment.toLowerCase() ==
                                  _selectedEquipment.toLowerCase()).toList();
                            }
                            if (_searchQuery.trim().isNotEmpty) {
                              final query = _searchQuery.toLowerCase();
                              filtered = filtered.where((m) =>
                                  m.exercise.name.toLowerCase().contains(query) ||
                                  m.exercise.primaryMuscle.toLowerCase().contains(query)).toList();
                            }

                            if (filtered.isEmpty) {
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                alignment: Alignment.center,
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.fitness_center_rounded,
                                      size: 48,
                                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      "No matching candidates found",
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (ctx, index) {
                                final match = filtered[index];
                                return _buildReplacementCard(match, theme);
                              },
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Center(child: Text("Error: $err")),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(child: Text("Error: $err")),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOriginalExercise(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Original",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.originalExercise.primaryMuscle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.originalExercise.name,
            style: theme.textTheme.displayMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTag(widget.originalExercise.mechanics, theme),
              _buildTag(widget.originalExercise.force, theme, isHighlight: true),
              _buildTag(widget.originalExercise.plane, theme),
              _buildTag(widget.originalExercise.equipment, theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentFilterRow() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _equipmentFilters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, index) {
          final filter = _equipmentFilters[index];
          final isSelected = _selectedEquipment == filter;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedEquipment = filter;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReplacementCard(RankedSubstitution match, ThemeData theme) {
    final candidate = match.exercise;
    final bool isHighlyCompatible = match.percentage >= 80;

    return InkWell(
      onTap: () async {
        await ref.read(workoutsRepositoryProvider).substituteExercise(
              workoutExerciseId: widget.workoutExercise.id,
              newExerciseId: candidate.id,
            );
        // Force refresh recent history
        ref.invalidate(recentExerciseIdsProvider);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text("Substituted to ${candidate.name}"),
                ],
              ),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isHighlyCompatible
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.outlineVariant.withValues(alpha: 0.3),
            width: isHighlyCompatible ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          candidate.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (match.isHistoryMatch) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "HISTORY",
                            style: TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${candidate.primaryMuscle} • ${candidate.equipment}",
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildTag(candidate.mechanics, theme, fontSize: 10),
                      _buildTag(candidate.plane, theme, fontSize: 10),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isHighlyCompatible
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.outlineVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${match.percentage}%",
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isHighlyCompatible ? AppColors.primary : AppColors.secondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Match",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, ThemeData theme, {bool isHighlight = false, double fontSize = 11}) {
    if (text.isEmpty || text.toLowerCase() == 'none') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight ? AppColors.primary.withValues(alpha: 0.3) : AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        text[0].toUpperCase() + text.substring(1),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: fontSize,
          color: isHighlight ? AppColors.primary : AppColors.secondary,
          fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
