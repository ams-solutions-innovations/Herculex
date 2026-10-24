part of '../block_detail_view.dart';

/// One planned exercise: picture, name and "3 × 8–10". The programming
/// detail (role, method, why) opens on tap so the day reads at a glance.
class _ExerciseLine extends StatefulWidget {
  const _ExerciseLine({required this.item, required this.onReplace});

  final ProgramDayExerciseSummary item;
  final VoidCallback onReplace;

  @override
  State<_ExerciseLine> createState() => _ExerciseLineState();
}

class _ExerciseLineState extends State<_ExerciseLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final item = widget.item;
    final exercise = item.exercise;
    final why = item.why?.trim();

    return InkWell(
      borderRadius: HxRadius.mdAll,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                exercise == null
                    ? const ExerciseArtwork.fromSlug(slug: null, size: 44)
                    : ExerciseArtwork(exercise: exercise, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.targetLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: hx.secondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
                    size: 20,
                    color: hx.primary,
                  ),
                  onPressed: widget.onReplace,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topLeft,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(left: 56, top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              HxTextPill(label: _humanize(item.role)),
                              if (item.method != 'auto')
                                HxTextPill(label: _humanize(item.method)),
                            ],
                          ),
                          if (why != null && why.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              why,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: hx.secondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _humanize(String id) {
    final text = id.replaceAll('_', ' ');
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }
}
