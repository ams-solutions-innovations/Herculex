import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/application/physique_roadmap_suggestion_provider.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';
import 'package:herculex/features/physique/domain/roadmap_draft_editor.dart';
import 'package:herculex/features/physique/presentation/dialogs/discard_changes_dialog.dart';
import 'package:herculex/features/physique/presentation/dialogs/reset_roadmap_dialog.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/phase_type_pill.dart';
import 'package:herculex/features/physique/presentation/widgets/restriction_notice.dart';
import 'package:herculex/features/physique/presentation/widgets/sheet_snackbar_scope.dart';

final _moveUp = CustomSemanticsAction(label: 'Move up');
final _moveDown = CustomSemanticsAction(label: 'Move down');

/// Review, reorder, resize, add and remove the phases of a roadmap, then
/// accept or save it (D-01). Writes roadmap rows only; calorie targets are
/// never touched here (D-02).
class RoadmapEditorSheet extends ConsumerStatefulWidget {
  const RoadmapEditorSheet({super.key, required this.goalId});

  final int goalId;

  static Future<void> show(BuildContext context, {required int goalId}) {
    return HxSheet.show<void>(
      context,
      builder: (_) =>
          SheetSnackBarScope(child: RoadmapEditorSheet(goalId: goalId)),
    );
  }

  @override
  ConsumerState<RoadmapEditorSheet> createState() => _RoadmapEditorSheetState();
}

class _RoadmapEditorSheetState extends ConsumerState<RoadmapEditorSheet> {
  List<RoadmapPhaseDraft>? _drafts;
  List<RoadmapPhaseDraft> _initial = const [];
  bool _picking = false;
  bool _saving = false;

  bool get _dirty => _drafts != null && !listEquals(_drafts, _initial);

  static DietPhase _phaseOf(String name) {
    for (final p in DietPhase.values) {
      if (p.name == name) return p;
    }
    return DietPhase.maintain;
  }

  void _init(List<PhysiqueRoadmapPhaseData> rows) {
    final drafts = [
      for (final r in rows)
        if (r.status != 'done')
          RoadmapPhaseDraft(
            phase: _phaseOf(r.phaseType),
            plannedWeeks: r.plannedWeeks,
            targetWeightKg: r.targetWeightKg,
            targetBfPercent: r.targetBfPercent,
            weeklyRateKg: r.weeklyRateKg,
            tempoCapped: r.tempoCapped,
          ),
    ];
    _drafts = drafts;
    _initial = drafts;
  }

  /// Start weight for retargeting; null when neither source is usable.
  double? _startWeight(PhysiqueGoalData goal) {
    final profileKg = ref.read(profileProvider).asData?.value?.weightKg;
    final kg = (profileKg != null && profileKg > 0)
        ? profileKg
        : goal.startWeightKg;
    return (kg != null && kg > 0) ? kg : null;
  }

  void _set(List<RoadmapPhaseDraft> next) => setState(() => _drafts = next);

  void _move(int index, int delta) {
    final drafts = _drafts!;
    final target = index + delta;
    if (target < 0 || target >= drafts.length) return;
    // reorder() takes ReorderableListView indices, where moving down is +1.
    _set(
      RoadmapDraftEditor.reorder(
        drafts,
        index,
        delta > 0 ? target + 1 : target,
      ),
    );
  }

  void _resize(int index, int delta) {
    final drafts = _drafts!;
    _set(
      RoadmapDraftEditor.resize(
        drafts,
        index,
        drafts[index].plannedWeeks + delta,
      ),
    );
  }

  void _remove(int index) {
    final drafts = _drafts!;
    if (drafts.length <= 1) return;
    final removed = drafts[index];
    _set(RoadmapDraftEditor.remove(drafts, index));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Phase removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            final current = [..._drafts!];
            current.insert(index.clamp(0, current.length), removed);
            _set(current);
          },
        ),
      ),
    );
  }

  void _add(DietPhase phase, int goalId) {
    final eligibility = ref.read(physiqueRoadmapEligibilityProvider(goalId));
    setState(() {
      _drafts = RoadmapDraftEditor.add(_drafts!, phase, eligibility);
      _picking = false;
    });
  }

  Future<void> _reset() async {
    final suggestion = ref.read(
      physiqueRoadmapSuggestionProvider(widget.goalId),
    );
    if (suggestion == null) return;
    final ok = await ResetRoadmapDialog.show(context);
    if (ok == true && mounted) {
      setState(() {
        _drafts = [...suggestion.phases];
        _picking = false;
      });
    }
  }

  Future<void> _save(PhysiqueGoalData goal) async {
    final drafts = _drafts;
    if (drafts == null || drafts.isEmpty || _saving) return;
    setState(() => _saving = true);
    var out = drafts;
    final weight = _startWeight(goal);
    if (weight != null) {
      out = RoadmapDraftEditor.retarget(
        drafts,
        startWeightKg: weight,
        goalTargetBfPercent: goal.targetBfPercent,
        maintenanceKcal:
            ref.read(maintenanceKcalProvider) ??
            PhysiqueTuning.defaultMaintenanceKcal,
        eligibility: ref.read(physiqueRoadmapEligibilityProvider(goal.id)),
      );
    }
    try {
      await ref
          .read(physiqueRoadmapRepositoryProvider)
          .replaceRoadmap(goal.id, out, accept: goal.roadmapAcceptedAt == null);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We couldn't save your roadmap. Try again."),
        ),
      );
      return;
    }
    if (!mounted) return;
    Haptics.light();
    Navigator.of(context).pop();
  }

  Future<void> _onPopBlocked() async {
    final discard = await DiscardChangesDialog.show(context);
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final goalId = widget.goalId;
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    final phases = ref.watch(physiqueRoadmapPhasesProvider(goalId)).asData;
    if (_drafts == null && phases != null) _init(phases.value);
    final drafts = _drafts;
    final eligibility = ref.watch(physiqueRoadmapEligibilityProvider(goalId));
    final suggestion = ref.watch(physiqueRoadmapSuggestionProvider(goalId));
    final accepting = goal != null && goal.roadmapAcceptedAt == null;
    final hasWeight = goal != null && _startWeight(goal) != null;
    final hx = context.hx;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopBlocked();
      },
      child: HxSheet(
        title: 'Your roadmap',
        subtitle:
            'Reorder, resize or remove phases. Nothing changes your calories '
            'until you set targets.',
        initialSize: 0.85,
        pinnedBottom: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed:
                (goal == null || drafts == null || drafts.isEmpty || _saving)
                ? null
                : () => _save(goal),
            child: Text(accepting ? 'Accept roadmap' : 'Save roadmap'),
          ),
        ),
        child: drafts == null
            ? const Padding(
                padding: EdgeInsets.all(HxSpace.x8),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RestrictionNoticeList(
                    eligibility: eligibility,
                    onAddAge: () => context.push(AppRoutes.profile),
                    onLogMeasurements: () =>
                        context.push(AppRoutes.measurements),
                  ),
                  if (eligibility.reasons.isNotEmpty)
                    const SizedBox(height: HxSpace.x4),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: drafts.length,
                    // onReorderItem hands over an already adjusted index;
                    // the editor expects the raw ReorderableListView one.
                    onReorderItem: (o, n) => _set(
                      RoadmapDraftEditor.reorder(drafts, o, n > o ? n + 1 : n),
                    ),
                    itemBuilder: (context, i) => _PhaseRow(
                      key: ObjectKey(drafts[i]),
                      index: i,
                      count: drafts.length,
                      draft: drafts[i],
                      onMove: (d) => _move(i, d),
                      onResize: (d) => _resize(i, d),
                      onRemove: () => _remove(i),
                    ),
                  ),
                  const SizedBox(height: HxSpace.x4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: hasWeight
                          ? () => setState(() => _picking = !_picking)
                          : null,
                      child: const Text('Add phase'),
                    ),
                  ),
                  if (!hasWeight && goal != null) ...[
                    const SizedBox(height: HxSpace.x2),
                    Text(
                      'Add your weight in Profile to add phases.',
                      style: PhysiqueText.label(context, color: hx.secondary),
                    ),
                  ],
                  if (_picking) ...[
                    const SizedBox(height: HxSpace.x3),
                    Wrap(
                      spacing: HxSpace.x2,
                      runSpacing: HxSpace.x2,
                      children: [
                        for (final p in DietPhase.values)
                          PhaseTypePill(
                            phase: p,
                            onTap: eligibility.allows(p)
                                ? () => _add(p, goalId)
                                : null,
                          ),
                      ],
                    ),
                  ],
                  if (suggestion != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _reset,
                        child: const Text('Reset to suggestion'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

String _tempoLabel(RoadmapPhaseDraft d) {
  switch (d.phase) {
    case DietPhase.maintain:
      return 'Hold your weight steady';
    case DietPhase.recomp:
      return 'Weight stays flat while body composition shifts';
    case DietPhase.cut:
    case DietPhase.bulk:
    case DietPhase.maingain:
      final rate = d.weeklyRateKg;
      return rate == null
          ? ''
          : 'About ${rate.abs().toStringAsFixed(1)} kg per week';
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    super.key,
    required this.index,
    required this.count,
    required this.draft,
    required this.onMove,
    required this.onResize,
    required this.onRemove,
  });

  final int index;
  final int count;
  final RoadmapPhaseDraft draft;
  final ValueChanged<int> onMove;
  final ValueChanged<int> onResize;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final tempo = _tempoLabel(draft);
    final weeks = draft.plannedWeeks;
    return Semantics(
      container: true,
      customSemanticsActions: {
        if (index > 0) _moveUp: () => onMove(-1),
        if (index < count - 1) _moveDown: () => onMove(1),
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: HxSpace.x3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: hx.surfaceVariant,
            borderRadius: HxRadius.mdAll,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: HxSpace.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          color: hx.secondary,
                        ),
                      ),
                    ),
                    Icon(
                      PhaseTypeIcon.of(draft.phase),
                      size: 20,
                      color: hx.secondary,
                    ),
                    const SizedBox(width: HxSpace.x2),
                    Expanded(
                      child: Text(
                        draft.phase.label,
                        style: PhysiqueText.bodyStrong(
                          context,
                          color: hx.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove phase',
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      onPressed: count > 1 ? onRemove : null,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: count > 1 ? hx.secondary : hx.tertiary,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 48, right: HxSpace.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Fewer weeks',
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            onPressed: weeks > PhysiqueTuning.minPhaseWeeks
                                ? () => onResize(-1)
                                : null,
                            icon: const Icon(Icons.remove_rounded),
                          ),
                          Flexible(
                            child: Text(
                              '$weeks weeks',
                              textAlign: TextAlign.center,
                              style: PhysiqueText.bodyTabular(
                                context,
                                color: hx.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'More weeks',
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            onPressed: weeks < PhysiqueTuning.maxPhaseWeeks
                                ? () => onResize(1)
                                : null,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                      if (tempo.isNotEmpty)
                        Text(
                          tempo,
                          style: PhysiqueText.label(
                            context,
                            color: hx.onSurfaceVariant,
                          ),
                        ),
                      if (draft.tempoCapped)
                        Text(
                          'Paced to a safe weekly rate',
                          style: PhysiqueText.label(
                            context,
                            color: hx.secondary,
                          ),
                        ),
                      const SizedBox(height: HxSpace.x2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
