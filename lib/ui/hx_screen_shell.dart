import 'package:flutter/material.dart';

import '../theme/tokens/tokens.dart';
import 'hx_back_button.dart';
import 'hx_glass.dart';

/// Page shell for pushed screens.
///
/// The header — a frosted back button, a frosted title pill and optional
/// actions — floats over the content and hides itself as you scroll down,
/// returning the moment you scroll up. That keeps the reading area clear
/// without ever stranding the user without a way back.
///
/// Replaces the hand-rolled headers each screen used to build, none of which
/// agreed on height, alignment or behavior.
class HxScreenShell extends StatefulWidget {
  const HxScreenShell({
    super.key,
    required this.title,
    this.children,
    this.slivers,
    this.actions = const [],
    this.pinnedBottom,
    this.showBack = true,
    this.padding = const EdgeInsets.symmetric(horizontal: HxSpace.x5),
  }) : assert(children != null || slivers != null,
            'Provide either children or slivers');

  final String title;

  /// Simple body: a vertical list of widgets.
  final List<Widget>? children;

  /// Advanced body, for pages that need their own slivers.
  final List<Widget>? slivers;

  /// Rendered as frosted circle buttons opposite the title.
  final List<Widget> actions;

  /// Always-visible call to action anchored above the bottom inset — used by
  /// screens whose primary action must never require scrolling.
  final Widget? pinnedBottom;

  final bool showBack;
  final EdgeInsets padding;

  @override
  State<HxScreenShell> createState() => _HxScreenShellState();
}

class _HxScreenShellState extends State<HxScreenShell>
    with SingleTickerProviderStateMixin {
  static const double _headerHeight = 56;

  /// Scrolling must travel this far in one direction before the header
  /// reacts, so ballistic jitter and rubber-banding do not flicker it.
  static const double _threshold = 12;

  late final AnimationController _header = AnimationController(
    vsync: this,
    duration: HxMotion.base,
    value: 1,
  );

  double _accumulated = 0;
  bool _visible = true;

  @override
  void dispose() {
    _header.dispose();
    super.dispose();
  }

  void _setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    visible ? _header.forward() : _header.reverse();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is! ScrollUpdateNotification) return false;

    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;

    final metrics = notification.metrics;
    // Near the top the header is always shown, so a page shorter than the
    // viewport can never hide it.
    if (metrics.pixels <= metrics.minScrollExtent + 4) {
      _accumulated = 0;
      _setVisible(true);
      return false;
    }

    if (!_accumulated.isNegative == delta.isNegative) _accumulated = 0;
    _accumulated += delta;

    if (_accumulated > _threshold) {
      _setVisible(false);
    } else if (_accumulated < -_threshold) {
      _setVisible(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final slivers = widget.slivers ??
        [
          SliverList(
            delegate: SliverChildListDelegate(widget.children!),
          ),
        ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: topInset + _headerHeight + HxSpace.x2,
                    left: widget.padding.left,
                    right: widget.padding.right,
                    bottom: bottomInset +
                        HxSpace.x8 +
                        (widget.pinnedBottom == null ? 0 : 80),
                  ),
                  sliver: slivers.length == 1
                      ? slivers.first
                      : SliverMainAxisGroup(slivers: slivers),
                ),
              ],
            ),
          ),

          // Floating header.
          Positioned(
            top: topInset,
            left: widget.padding.left,
            right: widget.padding.right,
            child: AnimatedBuilder(
              animation: _header,
              builder: (context, child) {
                final t = Curves.easeOut.transform(_header.value);
                return IgnorePointer(
                  ignoring: t < 0.05,
                  child: Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, -(_headerHeight + HxSpace.x2) * (1 - t)),
                      child: child,
                    ),
                  ),
                );
              },
              child: SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    if (widget.showBack) ...[
                      const HxBackButton(),
                      const SizedBox(width: HxSpace.x3),
                    ],
                    Flexible(
                      child: HxGlass(
                        borderRadius: HxRadius.pillAll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: HxSpace.x4, vertical: HxSpace.x2 + 2),
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (widget.actions.isNotEmpty) ...[
                      const SizedBox(width: HxSpace.x3),
                      for (final action in widget.actions) ...[
                        action,
                        const SizedBox(width: HxSpace.x2),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),

          if (widget.pinnedBottom != null)
            Positioned(
              left: widget.padding.left,
              right: widget.padding.right,
              bottom: bottomInset + HxSpace.x4,
              child: widget.pinnedBottom!,
            ),
        ],
      ),
    );
  }
}
