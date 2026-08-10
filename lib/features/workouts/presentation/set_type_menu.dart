import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../domain/set_type.dart';

/// Result of the set-type menu: a type plus its serialized metadata.
class SetTypeSelection {
  final SetType type;
  final String? metaJson;
  final bool delete;
  final bool? isWarmup;
  const SetTypeSelection(this.type, [this.metaJson])
    : delete = false,
      isWarmup = null;
  const SetTypeSelection.delete()
    : type = SetType.standard,
      metaJson = null,
      delete = true,
      isWarmup = null;
  const SetTypeSelection.warmup(this.isWarmup)
    : type = SetType.standard,
      metaJson = null,
      delete = false;
}

/// One-tap set-type switcher (§15, §26). Tapping a set's index cell opens this
/// sheet; selection is instantaneous, with inline quick-picks for the types
/// that carry metadata (pause duration, drop percent, down-set decrement).
class SetTypeMenu extends StatelessWidget {
  final SetType current;
  final bool isWarmup;
  const SetTypeMenu({super.key, required this.current, this.isWarmup = false});

  static Future<SetTypeSelection?> show(
    BuildContext context, {
    required SetType current,
    bool isWarmup = false,
  }) {
    return showModalBottomSheet<SetTypeSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetTypeMenu(current: current, isWarmup: isWarmup),
    );
  }

  /// Short badge shown in the set-index cell (e.g. "D" for drop set).
  static String badge(SetType type) => switch (type) {
    SetType.standard => '',
    SetType.drop => 'D',
    SetType.restPause => 'RP',
    SetType.partials => 'P½',
    SetType.myoReps => 'MY',
    SetType.pyramid => 'PY',
    SetType.forced => 'F',
    SetType.negatives => 'N',
    SetType.pause => 'PA',
    SetType.mechanicalDrop => 'MD',
    SetType.giant => 'G',
    SetType.preExhaustion => 'PE',
    SetType.twentyOnes => '21',
    SetType.volume20x60 => '20x',
    SetType.downSets => 'DN',
    SetType.amrap => 'AM',
    SetType.emom => 'EM',
    SetType.forTime => 'FT',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color:
              theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set Type',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          backgroundColor: AppColors.surfaceContainerLowest,
                          title: const Text('Set Types'),
                          content: const Text(
                            'Select a type to apply it to the set — '
                            'Warmup, Drop Set, Down Sets, Rest-Pause, and more. The letter '
                            'shown afterwards is a short code for the chosen type.\n\n'
                            'Down Sets are numbered D1, D2, … and drop one rep each set at '
                            'the same weight. Long-press a Down Set\'s badge to auto-fill '
                            'the rest of the chain instead of adding sets one by one.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'CLOSE',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Icon(
                    Icons.help_outline,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a type to apply it to this set',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  SwitchListTile(
                    title: const Text(
                      'Warmup Set',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Does not count towards working volume',
                    ),
                    value: isWarmup,
                    onChanged: (val) =>
                        Navigator.of(context).pop(SetTypeSelection.warmup(val)),
                    secondary: Icon(
                      Icons.local_fire_department,
                      color: isWarmup ? Colors.orange : AppColors.secondary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.redAccent),
                    title: const Text(
                      'Delete Set',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const SetTypeSelection.delete()),
                  ),
                  const Divider(height: 24),
                  for (final type in SetType.values.where(
                    (t) => t != SetType.giant,
                  ))
                    _SetTypeTile(type: type, isSelected: type == current),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Default value + alternates for a metadata-carrying set type's quick-pick.
class _QuickPickConfig {
  final String metaKey;
  final int defaultValue;
  final String defaultLabel;
  final List<int> alternates;
  final String Function(int) alternateLabel;
  const _QuickPickConfig({
    required this.metaKey,
    required this.defaultValue,
    required this.defaultLabel,
    required this.alternates,
    required this.alternateLabel,
  });
}

class _SetTypeTile extends StatefulWidget {
  final SetType type;
  final bool isSelected;
  const _SetTypeTile({required this.type, required this.isSelected});

  @override
  State<_SetTypeTile> createState() => _SetTypeTileState();
}

class _SetTypeTileState extends State<_SetTypeTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = widget.type;
    final isSelected = widget.isSelected;

    // Metadata-carrying types get a default pill + expandable alternates
    // instead of forcing the user to pick a value up front (§15, item 5).
    final _QuickPickConfig? quickConfig = switch (type) {
      SetType.pause => const _QuickPickConfig(
        metaKey: 'pauseSeconds',
        defaultValue: 3,
        defaultLabel: '3s',
        alternates: [2, 5],
        alternateLabel: _secondsLabel,
      ),
      SetType.drop => const _QuickPickConfig(
        metaKey: 'dropPercent',
        defaultValue: 20,
        defaultLabel: '20%',
        alternates: [10, 30],
        alternateLabel: _dropPercentLabel,
      ),
      _ => null,
    };

    void confirm(int value) {
      Navigator.of(
        context,
      ).pop(SetTypeSelection(type, jsonEncode({quickConfig!.metaKey: value})));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : AppColors.outlineVariant.withValues(alpha: 0.0),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: quickConfig != null
                ? () => confirm(quickConfig.defaultValue)
                : () => Navigator.of(context).pop(SetTypeSelection(type)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              child: Row(
                children: [
                  _Badge(type: type, selected: isSelected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      type.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isSelected ? AppColors.primary : null,
                      ),
                    ),
                  ),
                  if (quickConfig != null) ...[
                    _QuickPick(
                      label: quickConfig.defaultLabel,
                      onTap: () => confirm(quickConfig.defaultValue),
                    ),
                    IconButton(
                      icon: Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: AppColors.secondary,
                      ),
                      tooltip: _expanded ? 'Fewer options' : 'More options',
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  ] else if (isSelected)
                    Icon(Icons.check_circle, color: AppColors.primary, size: 22),
                ],
              ),
            ),
          ),
          if (quickConfig != null && _expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final alt in quickConfig.alternates)
                      _QuickPick(
                        label: quickConfig.alternateLabel(alt),
                        onTap: () => confirm(alt),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _secondsLabel(int s) => '${s}s';
String _dropPercentLabel(int pct) => '-$pct%';

/// Leading badge bubble showing the set type's short code (or a dot for plain
/// standard sets).
class _Badge extends StatelessWidget {
  final SetType type;
  final bool selected;
  const _Badge({required this.type, required this.selected});

  @override
  Widget build(BuildContext context) {
    final code = SetTypeMenu.badge(type);
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.2)
            : AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: code.isEmpty
          ? Icon(
              Icons.remove,
              size: 16,
              color: selected ? AppColors.primary : AppColors.secondary,
            )
          : Text(
              code,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// Small pill-shaped quick-pick (drop %, pause seconds).
class _QuickPick extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickPick({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: AppColors.surfaceVariant,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
