import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/profile/domain/greek_avatar.dart';

/// Reusable circular avatar displaying the user's chosen Greek mythological
/// character or falling back to initials / icon.
class GreekAvatarBadge extends StatelessWidget {
  final String? avatarId;
  final String? fallbackName;
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final bool showEditBadge;
  final double borderWidth;

  const GreekAvatarBadge({
    super.key,
    this.avatarId,
    this.fallbackName,
    this.size = 48,
    this.onTap,
    this.showBorder = true,
    this.borderColor,
    this.showEditBadge = false,
    this.borderWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = GreekAvatar.findById(avatarId);
    final effectiveBorderColor =
        borderColor ?? avatar?.primaryColor ?? context.hx.primary;
    final name = fallbackName?.trim() ?? '';
    final initial = name.isEmpty ? 'H' : name[0].toUpperCase();

    Widget avatarContent;
    if (avatar != null) {
      avatarContent = Image.asset(
        avatar.assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _FallbackInitial(
          size: size,
          initial: initial,
          color: effectiveBorderColor,
        ),
      );
    } else if (name.isNotEmpty) {
      avatarContent = _FallbackInitial(
        size: size,
        initial: initial,
        color: effectiveBorderColor,
      );
    } else {
      avatarContent = Icon(
        Icons.person_rounded,
        size: size * 0.52,
        color: effectiveBorderColor,
      );
    }

    Widget avatarCircle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.hx.surfaceContainer,
        border: showBorder
            ? Border.all(
                color: effectiveBorderColor.withValues(
                  alpha: avatar != null ? 0.75 : 0.35,
                ),
                width: borderWidth,
              )
            : null,
        boxShadow: avatar != null && showBorder
            ? [
                BoxShadow(
                  color: effectiveBorderColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipOval(child: avatarContent),
    );

    if (showEditBadge) {
      final badgeSize = (size * 0.28).clamp(20.0, 32.0);
      avatarCircle = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomRight,
        children: [
          avatarCircle,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: effectiveBorderColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: badgeSize * 0.55,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: avatarCircle,
      );
    }

    return avatarCircle;
  }
}

class _FallbackInitial extends StatelessWidget {
  final double size;
  final String initial;
  final Color color;

  const _FallbackInitial({
    required this.size,
    required this.initial,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontSize: size * 0.44,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
