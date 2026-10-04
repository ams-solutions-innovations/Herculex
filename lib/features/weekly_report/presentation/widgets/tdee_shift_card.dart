import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_display_providers.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_tdee_actions.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/tdee_target_proposal.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// The TDEE shift card of the weekly report (D-11).
///
/// The report view mounts it only when [section] is material. The numbers shown
/// always come from the frozen [section] (RPT-04); the only live inputs decide
/// whether an action is possible right now. The buttons write only on the
/// user's tap, through [TdeeDecisionActions]; a decided or past week is
/// read-only. There is no confirmation dialog: the tap is the confirmation and
/// the target stays editable in nutrition settings.
class TdeeShiftCard extends ConsumerStatefulWidget {
  const TdeeShiftCard({super.key, required this.record, required this.section});

  final WeeklyReportRecord record;
  final TdeeSection section;

  @override
  ConsumerState<TdeeShiftCard> createState() => _TdeeShiftCardState();
}

class _TdeeShiftCardState extends ConsumerState<TdeeShiftCard> {
  // Cleared in a finally block after every call: the card never stays dimmed.
  // On success the stored decision re-renders it read-only (the footer branches
  // on `record.tdeeDecision`), so clearing busy is harmless.
  bool _busy = false;

  static const String _title = 'Your energy estimate moved';
  static const String _followsEstimate =
      'Your target already follows your energy estimate.';
  static const String _noSuggestion =
      'No target change is suggested for this shift.';
  static const String _saveFailed = "Couldn't save your choice. Try again.";

  String? _message(TdeeActionResult result, {required String applied}) {
    switch (result) {
      case TdeeActionResult.applied:
        return applied;
      case TdeeActionResult.alreadyDecided:
        return 'You already made this choice for this week.';
      case TdeeActionResult.stale:
        return 'Your target changed since this suggestion. '
            'Review it in nutrition settings.';
      case TdeeActionResult.notActionable:
        return 'This report is read-only.';
      case TdeeActionResult.invalidInput:
        return _saveFailed;
    }
  }

  Future<void> _update(TdeeTargetProposal proposal) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    String? message;
    try {
      final result = await ref
          .read(tdeeDecisionActionsProvider)
          .update(
            week: widget.record.week,
            oldEstimateKcal: widget.section.oldKcal,
            newEstimateKcal: widget.section.newKcal,
            displayed: proposal,
          );
      message = _message(
        result,
        applied: 'Target updated to ${proposal.kcal} kcal',
      );
    } catch (_) {
      message = "Couldn't update your target. Try again.";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _keep(int currentKcal) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (currentKcal < WeeklyReportRepository.minDecisionKcal ||
        currentKcal > WeeklyReportRepository.maxDecisionKcal) {
      messenger?.showSnackBar(const SnackBar(content: Text(_saveFailed)));
      return;
    }
    setState(() => _busy = true);
    String? message;
    try {
      final result = await ref
          .read(tdeeDecisionActionsProvider)
          .keep(week: widget.record.week, currentKcal: currentKcal);
      // A kept decision re-renders the card; no snackbar on success.
      message = _message(result, applied: '');
      if (result == TdeeActionResult.applied) message = null;
    } catch (_) {
      message = _saveFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final section = widget.section;
    return HxCard(
      accent: hx.domainNutrition,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 20, color: hx.domainNutrition),
              const SizedBox(width: HxSpace.x2),
              Expanded(child: Text(_title, style: ReportText.heading(context))),
            ],
          ),
          const SizedBox(height: HxSpace.x4),
          Text(
            '${section.oldKcal} → ${section.newKcal} kcal',
            style: ReportText.heading(context).copyWith(fontSize: 28),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            '${signedNumber(section.deltaKcal.toDouble(), fractionDigits: 0)} '
            'kcal vs. your previous estimate',
            style: ReportText.label(context),
          ),
          const SizedBox(height: HxSpace.x4),
          _footer(context),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final record = widget.record;
    final section = widget.section;
    final decision = record.tdeeDecision;
    if (decision != null) {
      return _note(context, _decidedText(decision, record.tdeeDecisionKcal));
    }

    final now = ref.watch(clockProvider).now();
    final due = ref.watch(weeklyReportDueWeekProvider);
    if (!isActionableWeek(record.week, now, due)) {
      return _note(
        context,
        'Your energy estimate moved from ${section.oldKcal} to '
        '${section.newKcal} kcal.',
      );
    }

    final result = ref.watch(
      tdeeTargetProposalProvider((section.oldKcal, section.newKcal)),
    );
    final rule = ref.watch(savedTargetForTodayProvider).valueOrNull;
    return result.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => _note(context, _noSuggestion),
      data: (r) {
        final proposal = r.proposal;
        switch (r.status) {
          case TdeeProposalStatus.noSavedRule:
            return _note(context, _followsEstimate);
          case TdeeProposalStatus.noChange:
          case TdeeProposalStatus.belowMacroFloor:
            return _note(context, _noSuggestion);
          case TdeeProposalStatus.proposed:
            if (proposal == null || rule == null) {
              return _note(context, _noSuggestion);
            }
            return _actions(context, proposal, rule.kcal);
        }
      },
    );
  }

  String _decidedText(String decision, int? kcal) {
    if (decision == 'updated') {
      return kcal == null
          ? 'You updated your target'
          : 'You updated your target to $kcal kcal';
    }
    return kcal == null
        ? 'You kept your target'
        : 'You kept your target at $kcal kcal';
  }

  Widget _note(BuildContext context, String text) =>
      Text(text, style: ReportText.body(context));

  Widget _actions(
    BuildContext context,
    TdeeTargetProposal proposal,
    int currentKcal,
  ) {
    final hx = context.hx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PremiumButton has no disabled state: dim it and ignore taps.
        Semantics(
          button: true,
          enabled: !_busy,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: IgnorePointer(
              ignoring: _busy,
              child: Opacity(
                opacity: _busy ? 0.4 : 1,
                child: PremiumButton(
                  text: 'Update my target to ${proposal.kcal} kcal',
                  onTap: () => _update(proposal),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: hx.onSurfaceVariant,
            textStyle: ReportText.body(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          onPressed: _busy ? null : () => _keep(currentKcal),
          child: const Text('Keep current target'),
        ),
      ],
    );
  }
}
