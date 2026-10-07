import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_back_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

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
  }) : assert(
         children != null || slivers != null,
         'Provide either children or slivers',
       );

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
  bool _isAtTop = true;

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
    final atTop = metrics.pixels <= metrics.minScrollExtent + 8;
    if (atTop != _isAtTop) {
      setState(() {
        _isAtTop = atTop;
      });
    }

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

    final slivers =
        widget.slivers ??
        [SliverList(delegate: SliverChildListDelegate(widget.children!))];

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
                    bottom:
                        bottomInset +
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
                      offset: Offset(
                        0,
                        -(_headerHeight + HxSpace.x2) * (1 - t),
                      ),
                      child: child,
                    ),
                  ),
                );
              },
              child: SizedBox(
                height: _headerHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Centered title: visible ONLY when at the top
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: _isAtTop ? 1.0 : 0.0,
                        duration: HxMotion.base,
                        curve: Curves.easeInOut,
                        child: IgnorePointer(
                          ignoring: !_isAtTop,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 56,
                              ),
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Back button on the left
                    if (widget.showBack)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: HxBackButton(),
                      ),
                    // Actions on the right
                    if (widget.actions.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final action in widget.actions) ...[
                              action,
                              const SizedBox(width: HxSpace.x2),
                            ],
                          ],
                        ),
                      ),
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
