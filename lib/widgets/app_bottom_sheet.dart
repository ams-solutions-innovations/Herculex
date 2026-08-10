import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// The app's modal sheet shell: grab handle, optional title/subtitle, rounded
/// top corners and safe-area padding.
///
/// Extracted from the `showModalBottomSheet` + `DraggableScrollableSheet` +
/// hand-rolled grab-handle boilerplate that is duplicated across the app. New
/// sheets should use this; existing ones are left alone.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.scrollable = true,
    this.initialSize = 0.6,
    this.maxSize = 0.92,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
  final EdgeInsets padding;

  /// Shows [builder]'s widget wrapped in this shell.
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
        SingleChildScrollView(
          padding: padding,
          child: child,
        ),
        shrinkWrap: true,
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: 0.3,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 16),
            if (shrinkWrap) Flexible(child: body) else Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
