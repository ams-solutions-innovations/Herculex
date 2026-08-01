import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import 'workouts_providers.dart';

/// Quick accessory tray (§5–§8, §26): opened from a set row's accessory icon,
/// toggles belt/sleeves/wraps/straps/fat-grips, attaches bands with an
/// assistance/resistance mode, and sets the chain contribution — all without
/// leaving the logging screen. Writes are live; the sheet just closes.
class AccessoryTraySheet extends ConsumerWidget {
  final SetEntryData set;
  const AccessoryTraySheet({super.key, required this.set});

  static Future<void> show(BuildContext context, SetEntryData set) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AccessoryTraySheet(set: set),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accessories = ref.watch(accessoriesProvider);
    final bands = ref.watch(bandsProvider);
    final attached = ref.watch(setAccessoriesProvider(set.id));
    final attachedBands = ref.watch(setBandsProvider(set.id));
    final repo = ref.watch(accessoriesRepositoryProvider);

    final attachedIds =
        attached.asData?.value.map((a) => a.accessoryId).toSet() ?? const <int>{};

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Accessories',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            accessories.maybeWhen(
              data: (list) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in list.where((a) => a.kind != 'chains'))
                    FilterChip(
                      label: Text(a.name),
                      selected: attachedIds.contains(a.id),
                      onSelected: (_) => repo.toggleSetAccessory(
                          setEntryId: set.id, accessoryId: a.id),
                      selectedColor:
                          AppColors.primaryContainer.withValues(alpha: 0.5),
                      checkmarkColor: AppColors.primary,
                    ),
                ],
              ),
              orElse: () => const SizedBox(
                  height: 40,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            const SizedBox(height: 20),
            Text('Chains',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Average added load over the lift (kg at lockout ÷ 2).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 8),
            _ChainsField(set: set),
            const SizedBox(height: 20),
            Text('Bands',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            attachedBands.maybeWhen(
              data: (rows) => Column(
                children: [
                  for (final sb in rows)
                    _AttachedBandTile(
                      setBand: sb,
                      band: bands.asData?.value
                          .where((b) => b.id == sb.bandId)
                          .firstOrNull,
                      onRemove: () => repo.detachBand(sb.id),
                    ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            bands.maybeWhen(
              data: (list) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in list)
                    ActionChip(
                      avatar: CircleAvatar(
                          backgroundColor: _bandColor(b.color), radius: 6),
                      label: Text(
                          '${b.name} (${b.tensionKg.toStringAsFixed(0)}kg)'),
                      onPressed: () => _pickBandMode(context, repo, b),
                    ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  static Color _bandColor(String color) => switch (color) {
        'red' => Colors.redAccent,
        'blue' => Colors.blueAccent,
        'green' => Colors.green,
        'black' => Colors.black87,
        'purple' => Colors.purpleAccent,
        'orange' => Colors.orangeAccent,
        _ => AppColors.outline,
      };

  void _pickBandMode(BuildContext context, dynamic repo, BandData band) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.trending_up, color: AppColors.primary),
              title: const Text('Resistance'),
              subtitle: const Text('Harder at the top — adds load'),
              onTap: () {
                repo.attachBand(
                    setEntryId: set.id, bandId: band.id, isResistance: true);
                Navigator.pop(sheetCtx);
              },
            ),
            ListTile(
              leading: Icon(Icons.trending_down, color: AppColors.outline),
              title: const Text('Assistance'),
              subtitle: const Text('Easier at the bottom — removes load'),
              onTap: () {
                repo.attachBand(
                    setEntryId: set.id, bandId: band.id, isResistance: false);
                Navigator.pop(sheetCtx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachedBandTile extends StatelessWidget {
  final SetBandData setBand;
  final BandData? band;
  final VoidCallback onRemove;

  const _AttachedBandTile({
    required this.setBand,
    required this.band,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResistance = setBand.mode == 'resistance';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          isResistance ? Icons.trending_up : Icons.trending_down,
          color: isResistance ? AppColors.primary : AppColors.outline,
          size: 20,
        ),
        title: Text(
          '${band?.name ?? 'Band'} ×${setBand.count}',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(isResistance ? 'Resistance' : 'Assistance'),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onRemove,
        ),
      ),
    );
  }
}

class _ChainsField extends ConsumerStatefulWidget {
  final SetEntryData set;
  const _ChainsField({required this.set});

  @override
  ConsumerState<_ChainsField> createState() => _ChainsFieldState();
}

class _ChainsFieldState extends ConsumerState<_ChainsField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.set.chainsKg == null
        ? ''
        : widget.set.chainsKg!.toStringAsFixed(
            widget.set.chainsKg!.truncateToDouble() == widget.set.chainsKg!
                ? 0
                : 1),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text);
    ref.read(workoutsRepositoryProvider).updateSet(
          setId: widget.set.id,
          chainsKg: v,
        );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onEditingComplete: _commit,
      onTapOutside: (_) => _commit(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: '0',
        suffixText: 'kg',
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceContainer,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}