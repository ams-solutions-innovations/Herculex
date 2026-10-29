import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_glass.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// The quick-add "+": its own tinted glass, outside the navigation pill so
/// it never reads as another destination, in the warm `quickAdd` colour that
/// is distinct from both the neutral glass and the primary selection fill.
/// Turns into an "×" (45°) while the menu is open.
///
/// Shared by [HxNavBar] (phones) and [HxNavRail] (wide windows).
class HxQuickAddButton extends StatelessWidget {
  const HxQuickAddButton({
    super.key,
    required this.open,
    required this.onTap,
    this.size = 60,
  });

  final bool open;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;

    // A screen-reader label, not a Tooltip: the tooltip popped up over the
    // content on every long press and it names nothing the "+" does not.
    return Semantics(
      button: true,
      label: open ? 'Close' : 'Quick add',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: HxGlass(
            shape: BoxShape.circle,
            padding: EdgeInsets.zero,
            fill: hx.quickAdd.withValues(alpha: open ? 0.32 : 0.22),
            borderColor: hx.quickAdd.withValues(alpha: 0.55),
            child: Center(
              child: AnimatedRotation(
                duration: HxMotion.base,
                curve: HxMotion.standard,
                turns: open ? 0.125 : 0,
                // 28 at the bottom bar's 60 px, scaled for the rail's.
                child: Icon(
                  Icons.add_rounded,
                  color: hx.quickAdd,
                  size: size * 28 / 60,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
