import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/profile/domain/greek_avatar.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_badge.dart';

/// Result returned from [GreekAvatarPickerSheet.show].
class GreekAvatarSelectionResult {
  /// The newly selected avatar ID, or `null` if the user chose to clear back
  /// to initials.
  final String? avatarId;
  const GreekAvatarSelectionResult(this.avatarId);
}

/// Interactive bottom sheet allowing the user to pick a Greek god, demigod,
/// titan, or legend portrait as their profile picture.
class GreekAvatarPickerSheet extends StatefulWidget {
  final String? initialAvatarId;
  final String? userName;

  const GreekAvatarPickerSheet({
    super.key,
    required this.initialAvatarId,
    this.userName,
  });

  static Future<GreekAvatarSelectionResult?> show(
    BuildContext context, {
    required String? currentAvatarId,
    String? userName,
  }) {
    return showModalBottomSheet<GreekAvatarSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GreekAvatarPickerSheet(
        initialAvatarId: currentAvatarId,
        userName: userName,
      ),
    );
  }

  @override
  State<GreekAvatarPickerSheet> createState() => _GreekAvatarPickerSheetState();
}

class _GreekAvatarPickerSheetState extends State<GreekAvatarPickerSheet> {
  late String? _selectedId = widget.initialAvatarId ?? 'hercules';
  GreekAvatarCategory? _filterCategory;

  List<GreekAvatar> get _filteredAvatars {
    if (_filterCategory == null) return GreekAvatars.all;
    return GreekAvatars.byCategory(_filterCategory!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedAvatar =
        GreekAvatars.findById(_selectedId) ?? GreekAvatars.all.first;
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(
          top: BorderSide(
            color: selectedAvatar.accentColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.hx.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),

            // ── Sheet header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Profile Picture',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Greek gods, titans & legends of Olympus',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.hx.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Selected Hero Showcase Card ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SelectedAvatarShowcase(avatar: selectedAvatar),
            ),
            const SizedBox(height: 16),

            // ── Category Filter Chips ───────────────────────────────────────
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _CategoryFilterChip(
                    label: 'All',
                    icon: Icons.auto_awesome_rounded,
                    selected: _filterCategory == null,
                    accentColor: selectedAvatar.accentColor,
                    onTap: () {
                      Haptics.selection();
                      setState(() => _filterCategory = null);
                    },
                  ),
                  const SizedBox(width: 8),
                  for (final cat in GreekAvatarCategory.values) ...[
                    _CategoryFilterChip(
                      label: cat.label,
                      icon: cat.icon,
                      selected: _filterCategory == cat,
                      accentColor: selectedAvatar.accentColor,
                      onTap: () {
                        Haptics.selection();
                        setState(() => _filterCategory = cat);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Avatar Grid ─────────────────────────────────────────────────
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: _filteredAvatars.length,
                itemBuilder: (context, index) {
                  final item = _filteredAvatars[index];
                  final isSelected = item.id == selectedAvatar.id;
                  return _AvatarGridTile(
                    avatar: item,
                    selected: isSelected,
                    onTap: () {
                      Haptics.selection();
                      setState(() => _selectedId = item.id);
                    },
                  );
                },
              ),
            ),

            // ── Action Bar ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: context.hx.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      Haptics.medium();
                      Navigator.of(
                        context,
                      ).pop(GreekAvatarSelectionResult(selectedAvatar.id));
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: selectedAvatar.accentColor,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(52),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.bolt_rounded, size: 20),
                    label: Text(
                      'Select ${selectedAvatar.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (widget.initialAvatarId != null) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () {
                        Haptics.selection();
                        Navigator.of(
                          context,
                        ).pop(const GreekAvatarSelectionResult(null));
                      },
                      child: Text(
                        'Remove picture (use initials)',
                        style: TextStyle(
                          color: context.hx.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedAvatarShowcase extends StatelessWidget {
  final GreekAvatar avatar;
  const _SelectedAvatarShowcase({required this.avatar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = avatar.accentColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.20),
            context.hx.surfaceContainer,
            context.hx.surfaceContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Row(
        children: [
          GreekAvatarBadge(
            avatarId: avatar.id,
            size: 84,
            showGlow: true,
            borderWidth: 2.5,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        avatar.category.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        avatar.greekName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                          color: context.hx.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  avatar.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  avatar.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  avatar.lore,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.hx.onSurfaceVariant,
                    fontSize: 11.5,
                    height: 1.3,
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

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.22)
              : context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? accentColor
                : context.hx.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? accentColor : context.hx.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : context.hx.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarGridTile extends StatelessWidget {
  final GreekAvatar avatar;
  final bool selected;
  final VoidCallback onTap;

  const _AvatarGridTile({
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = avatar.accentColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? accent
                : context.hx.outlineVariant.withValues(alpha: 0.35),
            width: selected ? 2.0 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.22),
                    blurRadius: 12,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                GreekAvatarBadge(
                  avatarId: avatar.id,
                  size: 64,
                  showGlow: selected,
                  borderWidth: selected ? 2.2 : 1.4,
                ),
                if (selected)
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Colors.black,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              avatar.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? accent : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              avatar.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color: context.hx.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
