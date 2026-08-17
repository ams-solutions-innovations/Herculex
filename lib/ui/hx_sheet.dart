import 'package:flutter/material.dart';

import '../theme/tokens/tokens.dart';

/// The app's modal sheet shell: grab handle, optional title/subtitle, rounded
/// top corners and safe-area padding.
///
/// Successor to `widgets/app_bottom_sheet.dart`. Sheets are the app's main
/// navigation surface, so they get one shell rather than sixty hand-rolled
/// `showModalBottomSheet` bodies.
class HxSheet extends StatelessWidget {
  const HxSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.scrollable = true,
    this.initialSize = 0.6,
    this.maxSize = 0.92,
    this.minSize = 0.3,
    this.padding = const EdgeInsets.fromLTRB(
        HxSpace.x5, 0, HxSpace.x5, HxSpace.x5),
    this.pinnedBottom,
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  /// An action rendered opposite the title, e.g. a "Done" button.
  final Widget? trailing;

  /// When true the sheet grows with a drag handle and scrolls its content;
  /// when false it hugs its content (use for short menus).
  final bool scrollable;

  final double initialSize;
  final double maxSize;
  final double minSize;
  final EdgeInsets padding;

  /// Action anchored below the scrolling body, always reachable.
  final Widget? pinnedBottom;

  /// Shows [builder]'s widget as a modal sheet.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!scrollable) {
      return _shell(
        context,
        SingleChildScrollView(padding: padding, child: child),
        shrinkWrap: true,
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      expand: false,
      builder: (context, controller) => _shell(
        context,
        SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  Widget _shell(BuildContext context, Widget body, {bool shrinkWrap = false}) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Container(
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: HxRadius.sheetTop,
        border: Border(
          top: BorderSide(color: hx.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          children: [
            const SizedBox(height: HxSpace.x2 + 2),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: hx.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    HxSpace.x5, HxSpace.x4, HxSpace.x5, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title!,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: hx.secondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              const SizedBox(height: HxSpace.x4),
            ] else
              const SizedBox(height: HxSpace.x4),
            if (shrinkWrap) Flexible(child: body) else Expanded(child: body),
            if (pinnedBottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    HxSpace.x5, HxSpace.x3, HxSpace.x5, HxSpace.x2),
                child: pinnedBottom,
              ),
          ],
        ),
      ),
    );
  }
}
