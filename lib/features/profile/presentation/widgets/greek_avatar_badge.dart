import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/profile/domain/greek_avatar.dart';

/// Reusable circular avatar widget that renders a Greek god/titan/legend
/// portrait when [avatarId] matches a known [GreekAvatar], or falls back to
/// user initials / default person icon in the Herculex design language.
class GreekAvatarBadge extends StatelessWidget {
  final String? avatarId;
  final String? name;
  final double size;
  final bool showGlow;
  final double borderWidth;

  const GreekAvatarBadge({
    super.key,
    required this.avatarId,
    this.name,
    this.size = 44,
    this.showGlow = false,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = GreekAvatars.findById(avatarId);
    final trimmedName = name?.trim() ?? '';
    final accent = avatar?.accentColor ?? context.hx.primary;

    if (avatar != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              accent,
              accent.withValues(alpha: 0.35),
              const Color(0xFFFFD54F),
              accent.withValues(alpha: 0.35),
              accent,
            ],
          ),
          boxShadow: showGlow
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.32),
                    blurRadius: size * 0.25,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        padding: EdgeInsets.all(borderWidth),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.hx.surfaceContainer,
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            avatar.assetPath,
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: (_, _, _) =>
                _FallbackInitials(name: trimmedName, size: size, color: accent),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: 0.32),
          width: borderWidth,
        ),
      ),
      alignment: Alignment.center,
      child: _FallbackInitials(name: trimmedName, size: size, color: accent),
    );
  }
}

class _FallbackInitials extends StatelessWidget {
  final String name;
  final double size;
  final Color color;

  const _FallbackInitials({
    required this.name,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) {
      return Icon(Icons.person_rounded, size: size * 0.5, color: color);
    }
    return Text(
      name[0].toUpperCase(),
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.42,
        height: 1.0,
      ),
    );
  }
}
