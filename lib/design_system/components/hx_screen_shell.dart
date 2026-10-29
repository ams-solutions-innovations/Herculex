import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/components/hx_back_button.dart';
import 'package:herculex/design_system/components/hx_rail_frame.dart';
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
    this.titleIcon,
    this.children,
    this.slivers,
    this.actions = const [],
    this.pinnedBottom,
    this.showBack = true,
    this.padding = const EdgeInsets.symmetric(horizontal: HxSpace.x5),
    this.maxContentWidth = HxBreakpoints.readingMax,
  }) : assert(
         children != null || slivers != null,
         'Provide either children or slivers',
       );

  final String title;

  /// Optional icon shown before the title in the header.
  final IconData? titleIcon;

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

  /// Widest the content column grows in a wide browser window. Single-column
  /// screens keep the reading width; grids and overviews ask for more.
  final double maxContentWidth;

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
    final titleIcon = widget.titleIcon ?? _iconForTitle(widget.title);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Wide desktop browser windows: header and content keep to a readable
    // centred column instead of stretching edge to edge. The scrollable area
    // itself stays full width, so the wheel works anywhere on the page.
    final caps = PlatformCapabilities.current();
    final windowWidth = MediaQuery.sizeOf(context).width;
    // Wide web windows keep the main navigation on the left of pushed screens
    // too, so Settings or Dream Physique are not a dead end without a menu.
    final railLayout = HxRailFrame.layoutOf(context);
    final sideInset = caps.isWeb && !caps.isMobileBrowser
        ? math.max(
            0.0,
            (windowWidth - railLayout.inset - widget.maxContentWidth) / 2,
          )
        : 0.0;
    final leftInset = railLayout.inset + sideInset;
    final rightInset = sideInset;
    // Each header action occupies a 48 px button plus its 8 px gap.  The
    // title used to reserve a fixed 56 px on the right, which let it draw
    // underneath the first action whenever a screen had more than one.
    const headerActionSlotWidth = HxSpace.x10 + HxSpace.x4;
    // Keep the title centered against the standard back-button slot even on
    // screens that intentionally hide it.
    const titleLeftInset = headerActionSlotWidth;
    final titleRightInset = widget.actions.isEmpty
        ? headerActionSlotWidth
        : headerActionSlotWidth * widget.actions.length;

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
                    left: widget.padding.left + leftInset,
                    right: widget.padding.right + rightInset,
                    bottom:
                        bottomInset +
                        HxSpace.x8 +
                        // A pinned action sits on top of the scroll view.
                        // Reserve its full touch area plus breathing room so
                        // the last card can always scroll above it instead of
                        // being obscured by the CTA.
                        (widget.pinnedBottom == null ? 0 : 112),
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
            // The header keeps the standard gutter even when the body runs
            // edge to edge (padding: zero), so the back button never moves.
            left: HxSpace.x5 + leftInset,
            right: HxSpace.x5 + rightInset,
            child: AnimatedBuilder(
              animation: _header,
              builder: (context, child) {
                final t = Curves.easeOut.transform(_header.value);
                return IgnorePointer(
                  ignoring: t < 0.05,
                  child: Opacity(opacity: t, child: child),
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
                              padding: EdgeInsets.only(
                                left: titleLeftInset,
                                right: titleRightInset,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    titleIcon,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: HxSpace.x2),
                                  Flexible(
                                    child: Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                    ),
                                  ),
                                ],
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
                    // Actions on the right: visible ONLY when at the top
                    if (widget.actions.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedOpacity(
                          opacity: _isAtTop ? 1.0 : 0.0,
                          duration: HxMotion.base,
                          curve: Curves.easeInOut,
                          child: IgnorePointer(
                            ignoring: !_isAtTop,
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
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          if (widget.pinnedBottom != null)
            Positioned(
              left: widget.padding.left + leftInset,
              right: widget.padding.right + rightInset,
              bottom: bottomInset + HxSpace.x4,
              child: widget.pinnedBottom!,
            ),

          if (railLayout.shown) HxRailFrame.rail(context, railLayout),
        ],
      ),
    );
  }

  IconData _iconForTitle(String title) {
    final value = title.toLowerCase();
    if (value.contains('protein')) return Icons.fitness_center_rounded;
    if (value.contains('volume')) return Icons.bar_chart_rounded;
    if (value.contains('trend') || value.contains('insight')) {
      return Icons.show_chart_rounded;
    }
    if (value.contains('account') || value.contains('profile')) {
      return Icons.person_outline_rounded;
    }
    if (value.contains('setting') || value.contains('preference')) {
      return Icons.settings_outlined;
    }
    if (value.contains('workout') || value.contains('exercise')) {
      return Icons.fitness_center_rounded;
    }
    if (value.contains('food') || value.contains('nutrition')) {
      return Icons.restaurant_menu_rounded;
    }
    if (value.contains('calendar') || value.contains('schedule')) {
      return Icons.calendar_month_rounded;
    }
    if (value.contains('health') || value.contains('recovery')) {
      return Icons.favorite_border_rounded;
    }
    return Icons.grid_view_rounded;
  }
}
