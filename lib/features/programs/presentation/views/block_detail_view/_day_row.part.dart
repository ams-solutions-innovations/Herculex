part of '../block_detail_view.dart';

/// One program day: its template/link trigger (D-03, unchanged), plus each
/// planned exercise's summary line and a new per-exercise "Replace this
/// exercise" trigger (D-04) that opens the same [ExerciseReplacementSheet]
/// used pre-commit and reaches future materialized sessions without
/// disturbing already-started or completed ones.
class _DayRow extends ConsumerWidget {
  const _DayRow({
    required this.program,
    required this.day,
    required this.week,
    required this.totalWeeks,
  });

  final ProgramData program;
  final ProgramDayData day;
  final ProgramWeekData week;
  final int totalWeeks;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templates = ref.watch(workoutTemplateByIdProvider(day.templateId));
    final exercises = ref.watch(programDayExerciseSummariesProvider(day.id));
    final slot = day.cycleDayIndex != null
        ? 'Day ${day.cycleDayIndex! + 1}'
        : _weekdays[(day.dayOfWeek - 1).clamp(0, 6)];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  slot,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.slotLabel?.isNotEmpty == true
                          ? day.slotLabel!
                          : day.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      templates != null
                          ? templates.name
                          : exercises.asData?.value.isNotEmpty == true
                          ? '${exercises.asData!.value.length} planned exercises · ${day.stressRole.replaceAll('_', ' ')}'
                          : 'No template — sessions will be empty',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            templates == null &&
                                exercises.asData?.value.isNotEmpty != true
                            ? AppColors.tertiary
                            : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Link a template',
                icon: Icon(
                  day.templateId == null
                      ? Icons.link_rounded
                      : Icons.swap_horiz_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                onPressed: () => _link(context, ref),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove this day',
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 20,
                  color: AppColors.secondary,
                ),
                onPressed: () => _remove(ref),
              ),
            ],
          ),
          exercises.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 44, top: 6, bottom: 4),
                    child: Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.only(
                                    top: 6,
                                    right: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        '${item.targetLabel} · ${item.role.replaceAll('_', ' ')} · ${item.method.replaceAll('_', ' ')}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: AppColors.secondary,
                                            ),
                                      ),
                                      if (item.why?.isNotEmpty == true)
                                        Text(
                                          item.why!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: AppColors.secondary,
                                                fontStyle: FontStyle.italic,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Replace this exercise',
                                  icon: Icon(
                                    Icons.swap_horiz_rounded,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  onPressed: () => _replace(context, ref, item),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final picked = await TemplatePickerSheet.show(context);
    if (picked == null) return;
    final repo = ref.read(programsRepositoryProvider);
    await repo.setProgramDayTemplate(day.id, picked.id);
    await repo.rematerializeProgram(program.id);
  }

  Future<void> _remove(WidgetRef ref) async {
    final repo = ref.read(programsRepositoryProvider);
    await repo.deleteProgramDay(day.id);
    await repo.rematerializeProgram(program.id);
  }

  /// D-04: opens the same [ExerciseReplacementSheet] used pre-commit review,
  /// applies the chosen scope, then rematerializes future sessions only.
  /// Invalidates [waveLabelProvider] afterward so a replacement that lands on
  /// the wave-strip's anchor slot never leaves a stale "Exercise wave X of Y"
  /// reading on screen.
  Future<void> _replace(
    BuildContext context,
    WidgetRef ref,
    ProgramDayExerciseSummary item,
  ) async {
    // Prefer the already-resolved cached value; fall back to awaiting the
    // underlying catalog snapshot's first emission when nothing has
    // subscribed to it yet (e.g. this is the first read this session).
    final cached = ref
        .read(exerciseCatalogProvider(const ExerciseCatalogFilter()))
        .value;
    final candidates =
        cached ??
        (await ref.read(exerciseCatalogSnapshotProvider.future)).exercises;
    final current = candidates
        .where((exercise) => exercise.id == item.exerciseId)
        .firstOrNull;
    if (current == null) return;

    final selection = await showModalBottomSheet<ExerciseReplacementSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ExerciseReplacementSheet(current: current, candidates: candidates),
    );
    if (selection == null) return;

    final repo = ref.read(programsRepositoryProvider);
    await repo.replaceProgramExerciseSlot(
      programDayExerciseId: item.id,
      replacementExerciseId: selection.exercise.id,
      scope: selection.scope,
    );
    await repo.rematerializeProgram(program.id);
    ref.invalidate(
      waveLabelProvider((
        programId: program.id,
        programWeekId: week.id,
        weekIndex: week.weekIndex,
        totalWeeks: totalWeeks,
      )),
    );
    Haptics.selection();
  }
}
