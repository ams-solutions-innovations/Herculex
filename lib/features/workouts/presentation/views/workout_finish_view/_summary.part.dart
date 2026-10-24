part of '../workout_finish_view.dart';

/// The whole workout in three numbers, how much of the plan got done, and
/// any records — everything else waits under "More details".
class _FinishStats extends ConsumerWidget {
  const _FinishStats({
    required this.summary,
    required this.sessionId,
    required this.weightFormat,
  });

  final SessionSummary summary;
  final int sessionId;
  final WeightFormat weightFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final report = ref.watch(workoutReportProvider(sessionId)).value;
    final completion = report == null
        ? null
        : SessionCompletion.ratio(
            completed: report.completedSets,
            planned: report.plannedSets,
          );
    final partial = SessionCompletion.isPartial(completion);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: HxRadius.lgAll,
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _big(theme, summary.durationLabel, 'Time'),
              _big(
                theme,
                weightFormat.formatTonnage(summary.tonnageKg),
                'Volume',
              ),
              _big(theme, '${summary.totalSets}', 'Sets'),
            ],
          ),
          if (partial) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${SessionCompletion.label(completion!)} of the plan done',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${report!.completedSets}/${report.plannedSets} sets',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: hx.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: HxRadius.pillAll,
              child: LinearProgressIndicator(
                value: completion,
                minHeight: 7,
                color: partialSessionColor,
                backgroundColor: hx.outlineVariant.withValues(alpha: .25),
              ),
            ),
          ],
          if (summary.achievements.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in summary.achievements.take(3))
                  Chip(
                    avatar: Icon(
                      Icons.emoji_events_rounded,
                      size: 18,
                      color: hx.warning,
                    ),
                    label: Text('${a.title} · ${a.value}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _big(ThemeData theme, String value, String label) => Expanded(
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.secondary,
          ),
        ),
      ],
    ),
  );
}

/// Preview of the shareable card with its style picker. The card is only
/// rendered here, so the share action rasterises this sheet's boundary.
/// Pops with the chosen style so the next preview opens on it.
class _SharePreviewSheet extends StatefulWidget {
  const _SharePreviewSheet({
    required this.summary,
    required this.initial,
    required this.weightFormat,
    required this.onShare,
  });

  final SessionSummary summary;
  final ShareCardBackground initial;
  final WeightFormat weightFormat;
  final Future<void> Function(GlobalKey cardKey) onShare;

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  final _cardKey = GlobalKey();
  late ShareCardBackground _background = widget.initial;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final bg in ShareCardBackground.values)
                  ChoiceChip(
                    label: Text(bg.label),
                    selected: _background == bg,
                    onSelected: (_) {
                      Haptics.selection();
                      setState(() => _background = bg);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            RepaintBoundary(
              key: _cardKey,
              child: _ShareCard(
                summary: widget.summary,
                background: _background,
                weightFormat: widget.weightFormat,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _sharing
                    ? null
                    : () async {
                        setState(() => _sharing = true);
                        await widget.onShare(_cardKey);
                        if (!context.mounted) return;
                        Navigator.of(context).pop(_background);
                      },
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
