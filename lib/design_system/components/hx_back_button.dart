import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_glass.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Circular frosted-glass icon button used for back navigation and header
/// actions. Floats over scrolling content, so it needs the blur to stay
/// legible against whatever passes underneath.
class HxCircleButton extends StatelessWidget {
  const HxCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.iconSize = 20,
    this.iconColor,
    this.tintColor,
    this.borderColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Color? tintColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;

    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: HxGlass(
            shape: BoxShape.circle,
            padding: EdgeInsets.zero,
            fill: tintColor,
            borderColor: borderColor,
            child: Center(
              child: Icon(
                icon,
                size: iconSize,
                color: iconColor ?? hx.onSurface,
              ),
            ),
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Back affordance for [HxScreenShell]-based pages.
class HxBackButton extends StatelessWidget {
  const HxBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HxCircleButton(
      icon: Icons.arrow_back_ios_new_rounded,
      iconSize: 16,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
    );
  }
}
