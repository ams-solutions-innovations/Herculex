import 'package:flutter/material.dart';

import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Explains why a phase is unavailable and offers the safe next step. It
/// explains; it never blames (PHYS-04, D-05, D-06).
class RestrictionNotice extends StatelessWidget {
  const RestrictionNotice({super.key, required this.reason, this.onAction});

  final PhaseRestrictionReason reason;
  final VoidCallback? onAction;

  static String copyFor(PhaseRestrictionReason reason) => switch (reason) {
    PhaseRestrictionReason.under18 =>
      'Cut and Bulk are not available under 18. Maintenance, '
          'Recomp or a small Lean bulk move you forward safely, '
          'and Maintenance is a good starting point.',
    PhaseRestrictionReason.ageMissing =>
      'Add your age to unlock all phases. Until then we offer Maintenance, '
          'Recomp and Lean bulk.',
    PhaseRestrictionReason.lowConfidence =>
      'This analysis is not reliable enough for a cut or bulk plan. '
          'Add measurements to improve it.',
  };

  static String? actionLabelFor(PhaseRestrictionReason reason) =>
      switch (reason) {
        PhaseRestrictionReason.under18 => null,
        PhaseRestrictionReason.ageMissing => 'Add age in profile',
        PhaseRestrictionReason.lowConfidence => 'Add measurements',
      };

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final actionLabel = actionLabelFor(reason);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HxSpace.x4),
      decoration: BoxDecoration(
        color: hx.warning.withValues(alpha: 0.14),
        borderRadius: HxRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: 20,
                color: hx.warning,
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Text(
                  copyFor(reason),
                  style: PhysiqueText.body(context, color: hx.onSurface),
                ),
              ),
            ],
          ),
          if (onAction != null && actionLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onAction, child: Text(actionLabel)),
            ),
        ],
      ),
    );
  }
}

/// One [RestrictionNotice] per reason, in a stable order.
class RestrictionNoticeList extends StatelessWidget {
  const RestrictionNoticeList({
    super.key,
    required this.eligibility,
    this.onAddAge,
    this.onLogMeasurements,
  });

  final PhaseEligibility eligibility;
  final VoidCallback? onAddAge;
  final VoidCallback? onLogMeasurements;

  @override
  Widget build(BuildContext context) {
    const order = [
      PhaseRestrictionReason.under18,
      PhaseRestrictionReason.ageMissing,
      PhaseRestrictionReason.lowConfidence,
    ];
    final reasons = order.where(eligibility.reasons.contains).toList();
    if (reasons.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (final r in reasons) {
      if (children.isNotEmpty) children.add(const SizedBox(height: HxSpace.x3));
      children.add(
        RestrictionNotice(
          reason: r,
          onAction: switch (r) {
            PhaseRestrictionReason.under18 => null,
            PhaseRestrictionReason.ageMissing => onAddAge,
            PhaseRestrictionReason.lowConfidence => onLogMeasurements,
          },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
