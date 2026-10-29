part of '../dynamic_workout_view.dart';

/// Extra reps for Myo / Forced / Cheat sets, logged as chips under the
/// numbers. Other set types render nothing.
class _ExtraRepsSection extends ConsumerWidget {
  const _ExtraRepsSection({required this.set});

  final SetEntryData set;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setType = SetType.fromId(set.setType);
    if (setType != SetType.myoReps &&
        setType != SetType.forced &&
        setType != SetType.cheat) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final hx = context.hx;
    final meta = decodeSetTypeMeta(set.setTypeMetaJson);

    final List<int> extraItems;
    final String metaKey;
    final String buttonLabel;
    final String chipSuffix;
    final String title;
    final String dialogTitle;
    final Color accentColor;

    if (setType == SetType.myoReps) {
      metaKey = 'miniSets';
      buttonLabel = 'Mini-Set';
      chipSuffix = 'reps';
      title = 'MYO MINI-SETS';
      dialogTitle = 'Add Mini-Set';
      accentColor = hx.primary;
      extraItems = setTypeMetaInts(meta['miniSets']);
    } else if (setType == SetType.forced) {
      metaKey = 'extraReps';
      buttonLabel = 'Forced';
      chipSuffix = 'forced';
      title = 'FORCED REPS';
      dialogTitle = 'Add forced reps';
      accentColor = const Color(0xFFE53935);
      extraItems = setTypeMetaInts(meta['extraReps'] ?? meta['forcedReps']);
    } else {
      metaKey = 'extraReps';
      buttonLabel = 'Cheat';
      chipSuffix = 'cheat';
      title = 'CHEAT REPS';
      dialogTitle = 'Add cheat reps';
      accentColor = const Color(0xFFFF7043);
      extraItems = setTypeMetaInts(meta['extraReps'] ?? meta['cheatReps']);
    }

    Future<void> save(List<int> items) async {
      meta[metaKey] = items;
      await ref
          .read(workoutsRepositoryProvider)
          .updateSet(setId: set.id, setTypeMetaJson: jsonEncode(meta));
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: HxRadius.mdAll,
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: workoutKicker(
              context,
              color: accentColor,
              size: 11,
              spacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < extraItems.length; i++)
                InkWell(
                  onTap: () => save(List<int>.from(extraItems)..removeAt(i)),
                  borderRadius: HxRadius.smAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: HxRadius.smAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${extraItems[i]} $chipSuffix',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              InkWell(
                onTap: () async {
                  final reps = await _askForExtraReps(
                    context,
                    title: dialogTitle,
                    hint: 'Number of extra reps (e.g. 2)',
                  );
                  if (reps == null || reps <= 0) return;
                  await save(List<int>.from(extraItems)..add(reps));
                  if (setType == SetType.myoReps) {
                    ref
                        .read(restTimerProvider.notifier)
                        .start(seconds: 15, exerciseName: 'Myo-rep Rest');
                  }
                },
                borderRadius: HxRadius.smAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: HxRadius.smAll,
                    border: Border.all(color: accentColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: accentColor),
                      const SizedBox(width: 2),
                      Text(
                        buttonLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<int?> _askForExtraReps(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final ctrl = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: [1, 2, 3, 4, 5].map((count) {
              return ActionChip(
                label: Text('+$count'),
                onPressed: () => Navigator.of(ctx).pop(count),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctrl.text)),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

/// Accessory & Band badges attached to a specific set
class _DynamicSetAccessoryPills extends ConsumerWidget {
  final int setId;
  const _DynamicSetAccessoryPills({required this.setId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final attachedAccs =
        ref.watch(setAccessoriesProvider(setId)).asData?.value ?? const [];
    final attachedBands =
        ref.watch(setBandsProvider(setId)).asData?.value ?? const [];
    final catalogAccs =
        ref.watch(accessoriesProvider).asData?.value ?? const [];
    final catalogBands = ref.watch(bandsProvider).asData?.value ?? const [];

    final activeTags = <String>[];
    for (final sa in attachedAccs) {
      final acc = catalogAccs.firstWhereOrNull((a) => a.id == sa.accessoryId);
      if (acc != null) activeTags.add(acc.name);
    }
    for (final sb in attachedBands) {
      final band = catalogBands.firstWhereOrNull((b) => b.id == sb.bandId);
      final modeStr = sb.mode == 'assistance' ? 'Ast.' : 'Res.';
      if (band != null) {
        activeTags.add('${band.name} ($modeStr)');
      } else {
        activeTags.add('Band ($modeStr)');
      }
    }

    if (activeTags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final tag in activeTags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hx.primaryContainer.withValues(alpha: 0.4),
                borderRadius: HxRadius.pillAll,
                border: Border.all(color: hx.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 14, color: hx.primaryText),
                  const SizedBox(width: 4),
                  Text(
                    tag,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: hx.primaryText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
