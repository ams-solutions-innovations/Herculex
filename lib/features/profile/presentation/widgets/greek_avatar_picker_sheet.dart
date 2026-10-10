import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/profile/domain/greek_avatar.dart';

/// Modal sheet allowing the user to select from Greek gods, demigods, titans,
/// and legends as their Herculex profile picture.
class GreekAvatarPickerSheet extends StatefulWidget {
  final String? currentAvatarId;

  const GreekAvatarPickerSheet({super.key, this.currentAvatarId});

  /// Opens the picker sheet and returns the chosen avatar ID, or empty string `""`
  /// if the user explicitly removes their avatar, or `null` if dismissed.
  static Future<String?> show(BuildContext context, {String? currentAvatarId}) {
    return HxSheet.show<String?>(
      context,
      builder: (_) => GreekAvatarPickerSheet(currentAvatarId: currentAvatarId),
    );
  }

  @override
  State<GreekAvatarPickerSheet> createState() => _GreekAvatarPickerSheetState();
}

class _GreekAvatarPickerSheetState extends State<GreekAvatarPickerSheet> {
  late String? _selectedId = widget.currentAvatarId ?? 'hercules';
  GreekAvatarCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final selectedAvatar =
        GreekAvatar.findById(_selectedId) ?? GreekAvatar.all.first;

    final filteredAvatars = _selectedCategory == null
        ? GreekAvatar.all
        : GreekAvatar.all
              .where((a) => a.category == _selectedCategory)
              .toList();

    return HxSheet(
      title: 'Izberi profilno sliko',
      subtitle: 'Grški bogovi, titani in legende Olimpa',
      initialSize: 0.88,
      maxSize: 0.94,
      minSize: 0.5,
      pinnedBottom: _buildPinnedBottom(context, selectedAvatar),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero preview card of currently selected avatar ───────────
          _buildHeroPreviewCard(context, selectedAvatar),
          const SizedBox(height: 16),

          // ── Category filter chips ───────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _buildCategoryChip(
                  label: 'Vsi (${GreekAvatar.all.length})',
                  isSelected: _selectedCategory == null,
                  onTap: () {
                    Haptics.selection();
                    setState(() => _selectedCategory = null);
                  },
                ),
                const SizedBox(width: 8),
                for (final cat in GreekAvatarCategory.values) ...[
                  _buildCategoryChip(
                    label:
                        '${cat.label} (${GreekAvatar.all.where((a) => a.category == cat).length})',
                    isSelected: _selectedCategory == cat,
                    onTap: () {
                      Haptics.selection();
                      setState(() => _selectedCategory = cat);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Avatar Grid ──────────────────────────────────────────────
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredAvatars.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              final avatar = filteredAvatars[index];
              final isSelected = avatar.id == _selectedId;

              return _buildAvatarCard(context, avatar, isSelected);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final hx = context.hx;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? hx.primary : hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? hx.primary
                : hx.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : hx.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroPreviewCard(BuildContext context, GreekAvatar avatar) {
    final hx = context.hx;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: avatar.primaryColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: avatar.primaryColor.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar circle with glow
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: avatar.primaryColor, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: avatar.primaryColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                avatar.assetPath,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.person, size: 40, color: avatar.primaryColor),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Character details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      avatar.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      avatar.greekName,
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: avatar.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  avatar.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: hx.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '“${avatar.lore}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: hx.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarCard(
    BuildContext context,
    GreekAvatar avatar,
    bool isSelected,
  ) {
    final hx = context.hx;

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        setState(() => _selectedId = avatar.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? avatar.primaryColor.withValues(alpha: 0.12)
              : hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? avatar.primaryColor
                : hx.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: avatar.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? avatar.primaryColor
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: Image.asset(avatar.assetPath, fit: BoxFit.cover),
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: avatar.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? hx.onSurface : hx.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              avatar.category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? avatar.primaryColor
                    : hx.onSurfaceVariant.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedBottom(BuildContext context, GreekAvatar selectedAvatar) {
    final hx = context.hx;
    final hasExistingAvatar =
        widget.currentAvatarId != null && widget.currentAvatarId!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: () {
            Haptics.light();
            Navigator.of(context).pop(_selectedId);
          },
          style: FilledButton.styleFrom(
            backgroundColor: selectedAvatar.primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: const StadiumBorder(),
            elevation: 2,
          ),
          child: Text(
            'Izberi ${selectedAvatar.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (hasExistingAvatar) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              Haptics.light();
              // Empty string indicates clearing the avatar back to initials
              Navigator.of(context).pop('');
            },
            style: TextButton.styleFrom(
              foregroundColor: hx.onSurfaceVariant,
              minimumSize: const Size.fromHeight(40),
            ),
            child: const Text(
              'Odstrani sliko (uporabi začetnico)',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}
