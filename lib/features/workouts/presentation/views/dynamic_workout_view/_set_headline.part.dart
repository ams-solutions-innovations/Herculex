part of '../dynamic_workout_view.dart';

/// `SET 2 OF 4 · TARGET @ RPE 8` — tap to rate the set's effort.
class _SetHeadline extends StatelessWidget {
  const _SetHeadline({
    required this.set,
    required this.number,
    required this.targetRpeX10,
    required this.onTap,
  });

  final SetEntryData set;
  final SetNumber number;
  final int? targetRpeX10;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final setType = SetType.fromId(set.setType);
    final which = number.isWarmup
        ? 'WARM-UP ${number.ordinal} OF ${number.ofKind}'
        : 'SET ${number.ordinal} OF ${number.ofKind}';
    final kind = set.isWarmup || setType == SetType.standard
        ? null
        : setType.label.toUpperCase();
    final rpe = set.isCompleted ? set.rpeX10 : targetRpeX10;
    final rpeText = rpe == null
        ? null
        : set.isCompleted
        ? 'RPE ${_rpeLabel(rpe)}'
        : 'TARGET @ RPE ${_rpeLabel(rpe)}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          if (kind != null)
            Text(
              kind,
              style: workoutKicker(
                context,
                color: _colorForSetType(setType, hx),
                size: 12,
              ),
            ),
          Text(
            which,
            style: workoutKicker(
              context,
              color: set.isWarmup ? hx.warning : hx.onSurface,
              size: 12,
            ),
          ),
          if (set.isCompleted)
            Icon(Icons.check_circle_rounded, size: 15, color: hx.primaryText),
          if (rpeText != null) ...[
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: hx.tertiary,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              rpeText,
              style: workoutKicker(
                context,
                color: Color.lerp(hx.domainRecovery, Colors.white, 0.25),
                size: 12,
                spacing: 0.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _rpeLabel(int x10) =>
    x10 % 10 == 0 ? '${x10 ~/ 10}' : (x10 / 10).toStringAsFixed(1);

Color _colorForSetType(SetType type, HxColors hx) => switch (type) {
  SetType.drop => const Color(0xFFE57373),
  SetType.restPause => const Color(0xFFFFB74D),
  SetType.partials => const Color(0xFFFF8A65),
  SetType.myoReps => const Color(0xFF81C784),
  SetType.forced => const Color(0xFFE53935),
  SetType.cheat => const Color(0xFFFF7043),
  SetType.negatives => const Color(0xFF9575CD),
  SetType.pause => const Color(0xFF4FC3F7),
  SetType.downSets => const Color(0xFFBA68C8),
  _ => hx.primaryText,
};

/// One chip per set; done sets carry a check. Tap to jump to that set.
class _SetChips extends StatelessWidget {
  const _SetChips({
    required this.sets,
    required this.activeSetIndex,
    required this.onSelect,
  });

  final List<SetEntryData> sets;
  final int activeSetIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final numbers = numberSets(sets);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < sets.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Builder(
              builder: (context) {
                final selected = i == activeSetIndex;
                final done = sets[i].isCompleted;
                final fg = selected
                    ? hx.onPrimary
                    : done
                    ? hx.primaryText
                    : hx.secondary;
                return GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: HxMotion.fast,
                    height: 34,
                    constraints: const BoxConstraints(minWidth: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? (done
                                ? hx.primary
                                : hx.primary.withValues(alpha: 0.18))
                          : (done
                                ? hx.primary.withValues(alpha: 0.12)
                                : hx.surfaceContainerLowest),
                      borderRadius: HxRadius.smAll,
                      border: Border.all(
                        width: 1.5,
                        color: selected
                            ? hx.primary
                            : done
                            ? hx.primary.withValues(alpha: 0.35)
                            : hx.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (done) ...[
                          Icon(Icons.check_rounded, size: 15, color: fg),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          numbers[i].short,
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
