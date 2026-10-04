import 'package:flutter/material.dart';

/// Hides [child] when [hidden] is true, sliding it out below the screen edge
/// and making it non-interactive and invisible to assistive tech while it's
/// out of the way.
///
/// Built for bottom-anchored controls (nav bars, floating action bars) that
/// must clear the on-screen keyboard or a focused input's own controls: the
/// caller derives [hidden] from whatever focus/keyboard-inset signal it
/// tracks and this widget owns only the resulting animation.
///
/// Hiding is instant (no fade-out) so the control can never be seen
/// overlapping the thing that displaced it; restoring uses a 150ms fade.
/// The slide itself always animates over 200ms with [Curves.easeOutCubic].
class KeyboardObstructionScope extends StatelessWidget {
  const KeyboardObstructionScope({
    super.key,
    required this.hidden,
    required this.hiddenOffset,
    required this.child,
  });

  /// Whether [child] should currently be hidden.
  final bool hidden;

  /// How far below its resting position [child] slides to when [hidden].
  final double hiddenOffset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: hidden ? -hiddenOffset : 0,
      // Do not leave an invisible control in the accessibility tree while
      // it's hidden.
      child: ExcludeSemantics(
        excluding: hidden,
        child: IgnorePointer(
          ignoring: hidden,
          child: AnimatedOpacity(
            // Hiding is immediate: the obstruction must never overlap a
            // visible control. Restoring still uses the standard fade.
            duration: hidden
                ? Duration.zero
                : const Duration(milliseconds: 150),
            opacity: hidden ? 0 : 1,
            child: child,
          ),
        ),
      ),
    );
  }
}
