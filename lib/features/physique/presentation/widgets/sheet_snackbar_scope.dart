import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Gives a modal sheet its own [ScaffoldMessenger] so snackbars (and their
/// actions) appear above the sheet instead of behind the route barrier.
///
/// The scaffold covers the barrier, so the dimmed area above the sheet
/// forwards taps to [Navigator.maybePop] itself.
class SheetSnackBarScope extends StatelessWidget {
  const SheetSnackBarScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: context.hx.surfaceContainer.withValues(alpha: 0),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
