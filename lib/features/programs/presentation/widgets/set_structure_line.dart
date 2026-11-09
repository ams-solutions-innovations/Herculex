import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/programs/domain/program_set_structure.dart';

/// Names a slot's set structure, so a pyramid is visible while preparing a
/// program and not only during the workout.
class SetStructureLine extends StatelessWidget {
  const SetStructureLine({
    super.key,
    required this.direction,
    required this.label,
  });

  final PyramidDirection direction;
  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = context.hx.primary;
    final icon = switch (direction) {
      PyramidDirection.ascending => Icons.trending_up_rounded,
      PyramidDirection.descending => Icons.trending_down_rounded,
      PyramidDirection.none => null,
    };
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: primary),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
