import 'package:collection/collection.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/session_segment.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/presentation/sheets/exercise_replacement_sheet.dart';
import 'package:herculex/features/programs/presentation/views/block_detail_view.dart';
import 'package:herculex/features/programs/presentation/widgets/empty_slot_notice.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';

/// A review-only screen placed between building and activating a block.
///
/// The underlying program is deliberately archived and unscheduled while this
/// screen is open. That makes its exercise choices real (rather than a mock
/// preview) without exposing an unapproved program anywhere else in the app.
class ProgramReviewView extends ConsumerStatefulWidget {
  const ProgramReviewView({super.key, required this.programId});

  final int programId;

  @override
  ConsumerState<ProgramReviewView> createState() => _ProgramReviewViewState();
}

class _ProgramReviewViewState extends ConsumerState<ProgramReviewView> {
  bool _loading = true;
  bool _confirming = false;
  bool _finished = false;
  String? _error;
  List<_ReviewDay> _days = const [];
  List<_RotationLine> _rotations = const [];
  int _totalWeeks = 0;
  List<int> _weekIndices = const [];
  int _selectedWeekIndex = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    try {
      final weeks =
          await (db.select(db.programWeeks)
                ..where((t) => t.programId.equals(widget.programId))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
              .get();
      if (weeks.isEmpty) throw StateError('The plan has no first week.');
      final selectedWeek = weeks.firstWhere(
        (week) => week.weekIndex == _selectedWeekIndex,
        orElse: () => weeks.first,
      );
      final days =
          await (db.select(db.programDays)
                ..where((t) => t.programWeekId.equals(selectedWeek.id))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.dayOfWeek),
                  (t) => OrderingTerm(expression: t.orderIndex),
                ]))
              .get();
      final rows = <_ReviewDay>[];
      for (final day in days) {
        final exercises =
            await (db.select(db.programDayExercises)
                  ..where((t) => t.programDayId.equals(day.id))
                  ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
                .get();
        final ids = exercises.map((row) => row.exerciseId).toSet();
        final catalog = ids.isEmpty
            ? const <ExerciseCatalogData>[]
            : await (db.select(
                db.exerciseCatalog,
              )..where((t) => t.id.isIn(ids))).get();
        final byId = {for (final exercise in catalog) exercise.id: exercise};
        final emptyReasons = await _emptyReasonsFor(
          db,
          day: day,
          weekIndex: selectedWeek.weekIndex,
        );
        rows.add(
          _ReviewDay(
            day: day,
            exercises: [
              for (final row in exercises)
                _ReviewExercise(row: row, exercise: byId[row.exerciseId]),
            ],
            emptyReasons: emptyReasons,
          ),
        );
      }
      final rotations = await _loadRotations(db, weeks);
      if (!mounted) return;
      setState(() {
        _days = rows;
        _rotations = rotations;
        _totalWeeks = weeks.length;
        _weekIndices = weeks.map((week) => week.weekIndex).toList();
        _selectedWeekIndex = selectedWeek.weekIndex;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not prepare the exercise review.';
      });
    }
  }

  /// Fetches the planner's own rationale text for any of [day]'s slots left
  /// empty in the given [weekIndex] (D-04: a visible, human-readable message
  /// instead of a silently missing exercise row).
  Future<List<String>> _emptyReasonsFor(
    AppDatabase db, {
    required ProgramDayData day,
    required int weekIndex,
  }) async {
    final slots =
        await (db.select(db.programExerciseSlots)..where(
              (t) =>
                  t.programId.equals(widget.programId) &
                  t.daySlotLabel.equals(day.slotLabel ?? day.name),
            ))
            .get();
    if (slots.isEmpty) return const [];
    final emptyRows =
        await (db.select(db.programSlotExplanations)..where(
              (t) =>
                  t.slotId.isIn(slots.map((slot) => slot.id)) &
                  t.weekIndex.equals(weekIndex) &
                  t.status.equals('empty'),
            ))
            .get();
    return [for (final row in emptyRows) row.rationale];
  }

  Future<List<_RotationLine>> _loadRotations(
    AppDatabase db,
    List<ProgramWeekData> weeks,
  ) async {
    final slots =
        await (db.select(db.programExerciseSlots)
              ..where((t) => t.programId.equals(widget.programId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
    if (slots.isEmpty) return const [];
    final assignments = await (db.select(
      db.rotationAssignments,
    )..where((t) => t.slotId.isIn(slots.map((slot) => slot.id)))).get();
    final exerciseIds = assignments
        .map((assignment) => assignment.exerciseId)
        .toSet();
    final catalog = exerciseIds.isEmpty
        ? const <ExerciseCatalogData>[]
        : await (db.select(
            db.exerciseCatalog,
          )..where((t) => t.id.isIn(exerciseIds))).get();
    final nameById = {
      for (final exercise in catalog) exercise.id: exercise.name,
    };
    final assignmentsBySlot = <int, Map<int, RotationAssignmentData>>{};
    for (final assignment in assignments) {
      assignmentsBySlot.putIfAbsent(
        assignment.slotId,
        () => {},
      )[assignment.weekIndex] = assignment;
    }

    return [
      for (final slot in slots)
        () {
          final byWeek = assignmentsBySlot[slot.id] ?? const {};
          final segments = <_RotationSegment>[];
          String? activeName;
          var start = 0;
          for (var week = 0; week < weeks.length; week++) {
            final name =
                nameById[byWeek[week]?.exerciseId] ?? 'Selected exercise';
            if (activeName == null) {
              activeName = name;
              start = week;
            } else if (name != activeName) {
              segments.add(
                _RotationSegment(
                  startWeek: start,
                  endWeek: week - 1,
                  exerciseName: activeName,
                ),
              );
              activeName = name;
              start = week;
            }
          }
          if (activeName != null) {
            segments.add(
              _RotationSegment(
                startWeek: start,
                endWeek: weeks.length - 1,
                exerciseName: activeName,
              ),
            );
          }
          return _RotationLine(
            label: '${slot.daySlotLabel} · ${slot.role.replaceAll('_', ' ')}',
            segments: segments,
          );
        }(),
    ].where((line) => line.segments.length > 1).toList(growable: false);
  }

  Future<void> _chooseReplacement(_ReviewExercise item) async {
    final current = item.exercise;
    if (current == null) return;
    final db = ref.read(appDatabaseProvider);
    final all = await (db.select(
      db.exerciseCatalog,
    )..where((t) => t.deletedAt.isNull())).get();
    if (!mounted) return;
    final selection = await showModalBottomSheet<ExerciseReplacementSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ExerciseReplacementSheet(current: current, candidates: all),
    );
    if (selection == null) return;
    await ref
        .read(programsRepositoryProvider)
        .replaceProgramExerciseSlot(
          programDayExerciseId: item.row.id,
          replacementExerciseId: selection.exercise.id,
          scope: selection.scope,
        );
    Haptics.selection();
    await _load();
  }

  void _selectWeek(int? weekIndex) {
    if (weekIndex == null || weekIndex == _selectedWeekIndex) return;
    setState(() {
      _selectedWeekIndex = weekIndex;
      _loading = true;
      _error = null;
    });
    _load();
  }

  Future<bool> _discard() async {
    if (_finished) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text(
          'The plan is not active yet. Discarding removes this draft and its exercise choices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true) return false;
    _finished = true;
    await ref.read(programsRepositoryProvider).deleteProgram(widget.programId);
    return true;
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    try {
      final repo = ref.read(programsRepositoryProvider);
      await repo.archiveProgram(widget.programId, archived: false);
      await repo.setActiveProgram(widget.programId);
      await repo.rematerializeProgram(widget.programId, futureOnly: false);
      if (!mounted) return;
      _finished = true;
      Haptics.success();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => BlockDetailView(programId: widget.programId),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = 'Could not confirm the plan. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _finished) return;
        if (!await _discard() || !mounted) return;
        Navigator.of(this.context).pop();
      },
      child: HxScreenShell(
        title: 'Review plan',
        pinnedBottom: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: PremiumButton(
              text: _confirming ? 'Confirming…' : 'Confirm plan',
              onTap: _confirming ? () {} : _confirm,
            ),
          ),
        ),
        children: [
          Text(
            'Your exercise plan',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Review each week before it becomes active. Tap an exercise to choose a similar option and how far that choice should reach.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _Notice(text: _error!)
          else ...[
            if (_weekIndices.length > 1) ...[
              _WeekPicker(
                weekIndices: _weekIndices,
                selectedWeekIndex: _selectedWeekIndex,
                onChanged: _selectWeek,
              ),
              const SizedBox(height: 16),
            ],
            for (final day in _days)
              _DayCard(day: day, onReplace: _chooseReplacement),
            const SizedBox(height: 8),
            const _Notice(
              text:
                  '“This wave” is recommended: it changes only the matching run of weeks. You can include future waves or the whole block when that is what you intend.',
            ),
            const SizedBox(height: 8),
            _PlannedChangesButton(
              totalWeeks: _totalWeeks,
              rotations: _rotations,
            ),
          ],
        ],
      ),
    );
  }
}

/// Keeps the week-by-week workout review front and centre. The rotation
/// schedule remains available on demand instead of interrupting the plan.
class _PlannedChangesButton extends StatelessWidget {
  const _PlannedChangesButton({
    required this.totalWeeks,
    required this.rotations,
  });

  final int totalWeeks;
  final List<_RotationLine> rotations;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: .55,
          minChildSize: .35,
          maxChildSize: .9,
          builder: (_, controller) => Material(
            color: AppColors.surfaceContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _RotationScheduleCard(
                  totalWeeks: totalWeeks,
                  rotations: rotations,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    icon: const Icon(Icons.sync_rounded),
    label: const Text('See planned exercise changes'),
  );
}

class _WeekPicker extends StatelessWidget {
  const _WeekPicker({
    required this.weekIndices,
    required this.selectedWeekIndex,
    required this.onChanged,
  });

  final List<int> weekIndices;
  final int selectedWeekIndex;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.outlineVariant.withValues(alpha: .35),
      ),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selectedWeekIndex,
        isExpanded: true,
        dropdownColor: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.onSurface,
        ),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        onChanged: onChanged,
        items: [
          for (final weekIndex in weekIndices)
            DropdownMenuItem(
              value: weekIndex,
              child: Text('Week ${weekIndex + 1}'),
            ),
        ],
      ),
    ),
  );
}

class _RotationScheduleCard extends StatelessWidget {
  const _RotationScheduleCard({
    required this.totalWeeks,
    required this.rotations,
  });

  final int totalWeeks;
  final List<_RotationLine> rotations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'What changes when',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            rotations.isEmpty
                ? 'Your selected main lifts stay in place for all $totalWeeks weeks.'
                : 'These are the exact planned exercise changes. Everything not listed stays in place.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          for (final line in rotations) ...[
            const SizedBox(height: 14),
            Text(
              line.label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            for (final segment in line.segments)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${segment.weekLabel}  ${segment.exerciseName}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RotationLine {
  const _RotationLine({required this.label, required this.segments});

  final String label;
  final List<_RotationSegment> segments;
}

class _RotationSegment {
  const _RotationSegment({
    required this.startWeek,
    required this.endWeek,
    required this.exerciseName,
  });

  final int startWeek;
  final int endWeek;
  final String exerciseName;

  String get weekLabel => startWeek == endWeek
      ? 'Week ${startWeek + 1}'
      : 'Weeks ${startWeek + 1}–${endWeek + 1}';
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.onReplace});

  final _ReviewDay day;
  final ValueChanged<_ReviewExercise> onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day.day.slotLabel ?? day.day.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (day.exercises.isEmpty && day.emptyReasons.isEmpty)
            Text(
              'No exercises have been added for this day.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            )
          else
            for (final item in day.exercises)
              _ExerciseRow(item: item, onTap: () => onReplace(item)),
          for (final reason in day.emptyReasons)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: EmptySlotNotice(reason: reason),
            ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.item, required this.onTap});
  final _ReviewExercise item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercise = item.exercise;
    final isMetcon = item.row.sessionSegment == SessionSegment.metcon.id;
    final metconSegment = isMetcon
        ? SlotPrescriptionCodec.decode(
            item.row.prescriptionCodecJson,
          )?.segments.firstOrNull
        : null;
    final reps = switch ((item.row.targetRepsMin, item.row.targetRepsMax)) {
      (final int min, final int max) when min != max => '$min–$max reps',
      (final int min, _) => '$min reps',
      (_, final int max) => '$max reps',
      _ => 'Custom reps',
    };
    final subtitle = isMetcon && metconSegment != null
        ? _metconSummary(metconSegment)
        : '${item.row.targetSets} sets · $reps${exercise?.movementPattern == null ? '' : ' · ${exercise!.movementPattern!.replaceAll('_', ' ')}'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: exercise == null ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              if (exercise != null)
                ExerciseArtwork(exercise: exercise, size: 48, radius: 12)
              else
                const Icon(Icons.fitness_center_rounded, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise?.name ?? 'Unknown exercise',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined, size: 19, color: AppColors.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

String _metconSummary(WorkSegment segment) {
  final capSeconds = (segment.meta['capSeconds'] as num?)?.toInt();
  final minutes = (segment.meta['minutes'] as num?)?.toInt();
  switch (segment.setType) {
    case SetType.amrap:
      return capSeconds != null ? 'AMRAP ${_formatCap(capSeconds)}' : 'AMRAP';
    case SetType.emom:
      return minutes != null ? 'EMOM $minutes min' : 'EMOM';
    case SetType.forTime:
      return capSeconds != null
          ? 'For Time, cap ${_formatCap(capSeconds)}'
          : 'For Time';
    default:
      return segment.setType.label;
  }
}

String _formatCap(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _ReviewDay {
  const _ReviewDay({
    required this.day,
    required this.exercises,
    this.emptyReasons = const [],
  });
  final ProgramDayData day;
  final List<_ReviewExercise> exercises;
  final List<String> emptyReasons;
}

class _ReviewExercise {
  const _ReviewExercise({required this.row, required this.exercise});
  final ProgramDayExerciseData row;
  final ExerciseCatalogData? exercise;
}
