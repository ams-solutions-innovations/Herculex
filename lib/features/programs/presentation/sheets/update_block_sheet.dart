import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/programs/application/block_update_controller.dart';
import 'package:herculex/features/programs/domain/block_adjustment_advisor.dart';
import 'package:herculex/features/programs/domain/time_saving_policy.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';

/// Opens the "update this block" sheet for [program], prefilled from
/// [recommendation] when the app suggested the change.
Future<void> showUpdateBlockSheet(
  BuildContext context, {
  required ProgramData program,
  BlockAdjustmentRecommendation? recommendation,
}) {
  return HxSheet.show<void>(
    context,
    builder: (_) =>
        _UpdateBlockSheet(program: program, recommendation: recommendation),
  );
}

/// Change how often and how long you train; the rest of the block is rebuilt
/// around it. Opens the regenerated plan for review — nothing changes until
/// the user confirms there.
class _UpdateBlockSheet extends ConsumerStatefulWidget {
  const _UpdateBlockSheet({required this.program, this.recommendation});

  final ProgramData program;
  final BlockAdjustmentRecommendation? recommendation;

  @override
  ConsumerState<_UpdateBlockSheet> createState() => _UpdateBlockSheetState();
}

class _UpdateBlockSheetState extends ConsumerState<_UpdateBlockSheet> {
  late int _days =
      widget.recommendation?.suggestedDaysPerWeek ??
      widget.program.daysPerWeek ??
      3;
  int _minutes = 60;
  late bool _lighter = widget.recommendation?.lighter ?? false;
  bool _building = false;
  bool _timeSaving = true;
  TimeSavingTechnique _technique = TimeSavingTechnique.automatic;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final current = widget.program.daysPerWeek;
    final recommendation = widget.recommendation;

    return HxSheet(
      scrollable: true,
      title: 'Update your block',
      subtitle: 'The remaining weeks are rebuilt. Logged workouts stay.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recommendation != null) ...[
            HxCard(
              accent: hx.warning,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: hx.warning),
                  const SizedBox(width: HxSpace.x3),
                  Expanded(child: Text(recommendation.message)),
                ],
              ),
            ),
            const SizedBox(height: HxSpace.x5),
          ],
          Text('Training days per week', style: theme.textTheme.titleSmall),
          const SizedBox(height: HxSpace.x2),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: _days > BlockAdjustmentAdvisor.minDaysPerWeek
                    ? () => setState(() => _days--)
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_days',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (current != null && current != _days)
                      Text(
                        'now $current',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hx.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: _days < 6 ? () => setState(() => _days++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x5),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Time per workout',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '$_minutes min',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _minutes.toDouble(),
            min: 30,
            max: 120,
            divisions: 6,
            label: '$_minutes min',
            onChanged: (value) => setState(() => _minutes = value.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _lighter,
            onChanged: (value) => setState(() => _lighter = value),
            title: const Text('Lighter block'),
            subtitle: const Text('About 15% less volume to help you recover.'),
          ),
          if (!_lighter) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _timeSaving,
              onChanged: (value) => setState(() => _timeSaving = value),
              title: const Text('Time-saving isolation sets'),
              subtitle: const Text(
                'Use eligible exercises and keep heavy-lift warm-ups and rest.',
              ),
            ),
            if (_timeSaving)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in TimeSavingTechnique.values)
                    ChoiceChip(
                      label: Text(option.label),
                      selected: _technique == option,
                      onSelected: (_) => setState(() => _technique = option),
                    ),
                ],
              ),
          ],
          const SizedBox(height: HxSpace.x4),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _building ? null : _build,
              icon: _building
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded),
              label: Text(_building ? 'Building…' : 'Build updated plan'),
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          Text(
            'You will review the new plan before anything changes.',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
        ],
      ),
    );
  }

  Future<void> _build() async {
    setState(() => _building = true);
    final navigator = Navigator.of(context);
    final notices = AppNotice.of(context);
    try {
      final draftId = await ref
          .read(blockUpdateControllerProvider)
          .buildDraft(
            widget.program,
            BlockUpdateRequest(
              daysPerWeek: _days,
              sessionMinutes: _minutes,
              lighter: _lighter,
              allowTimeSavingSetTechniques: _timeSaving,
              timeSavingTechnique: _technique,
            ),
          );
      Haptics.success();
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ProgramReviewView(
            programId: draftId,
            replacesProgramId: widget.program.id,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _building = false);
      notices.show(
        'Could not rebuild the block: $e',
        kind: AppNoticeKind.error,
      );
    }
  }
}
