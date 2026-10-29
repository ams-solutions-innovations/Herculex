import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_glass.dart';
import 'package:herculex/design_system/components/hx_nav_bar.dart';
import 'package:herculex/design_system/components/hx_quick_add_button.dart';
import 'package:herculex/design_system/components/hx_rail_tool.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// [HxNavBar] turned on its side for wide windows: the same four home
/// destinations in one frosted pill, the same flat primary selection bubble
/// sliding between them, and the same quick-add button — down the left edge
/// instead of across the bottom, which a desktop screen has room for and a
/// bottom bar would waste.
///
/// A desktop also has room for more than a phone's four tabs, so [tools] adds
/// the rest of the app below a divider. The rail stays icon-only and narrow;
/// labels are tooltips. When the window is too short for every icon the
/// destinations scroll and quick-add stays put.
class HxNavRail extends StatelessWidget {
  const HxNavRail({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.tools = const [],
    this.currentTool,
    this.onToolTap,
    this.quickAddOpen = false,
    this.onQuickAddTap,
    this.leading,
    this.trailing,
  });

  /// The selected home tab; null while a tool is selected.
  final int? currentIndex;
  final ValueChanged<int> onTap;

  final List<HxRailTool> tools;

  /// Index into [tools] of the selected tool; null while a home tab is.
  final int? currentTool;
  final ValueChanged<HxRailTool>? onToolTap;
  final bool quickAddOpen;

  /// Null hides the quick-add button: pushed screens share the rail but
  /// quick-add opens an overlay owned by the main shell.
  final VoidCallback? onQuickAddTap;

  /// Above the destinations — the logo.
  final Widget? leading;

  /// Below the quick-add button — the account avatar.
  final Widget? trailing;

  static const double width = 76;

  /// Space between the rail and the window edge.
  static const double margin = HxSpace.x4;

  /// How far content must stay from the left edge to clear the rail.
  static const double clearance = width + margin * 2;

  static const double _slotHeight = 52;
  static const double _bubbleSize = 44;
  static const double _dividerHeight = 17;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final tabs = HxNavBar.destinations;
    final hasTools = tools.isNotEmpty;

    // Where the selection bubble sits, from the top of the destinations.
    final selectedOffset = currentIndex != null
        ? _slotHeight * currentIndex!
        : _slotHeight * (tabs.length + (currentTool ?? 0)) + _dividerHeight;
    final destinationsHeight =
        _slotHeight * (tabs.length + tools.length) +
        (hasTools ? _dividerHeight : 0);

    return SizedBox(
      width: width,
      child: HxGlass(
        borderRadius: BorderRadius.circular(width / 2),
        fill: HxGlass.frostedFill(hx),
        borderColor: HxGlass.frostedBorder(hx),
        padding: const EdgeInsets.symmetric(
          horizontal: HxSpace.x2,
          vertical: HxSpace.x5,
        ),
        child: Column(
          children: [
            if (leading != null) ...[
              Center(child: leading),
              const SizedBox(height: HxSpace.x6),
            ],
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: destinationsHeight,
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: HxMotion.slow,
                          curve: HxMotion.emphasized,
                          top: selectedOffset + (_slotHeight - _bubbleSize) / 2,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: _bubbleSize,
                              height: _bubbleSize,
                              decoration: BoxDecoration(
                                color: hx.primary,
                                borderRadius: HxRadius.pillAll,
                              ),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            for (var i = 0; i < tabs.length; i++)
                              _RailItem(
                                icon: tabs[i].icon,
                                label: tabs[i].label,
                                selected: currentIndex == i,
                                height: _slotHeight,
                                onTap: () => onTap(i),
                              ),
                            if (hasTools) ...[
                              SizedBox(
                                height: _dividerHeight,
                                child: Center(
                                  child: Container(
                                    width: 28,
                                    height: 1,
                                    color: hx.outlineVariant,
                                  ),
                                ),
                              ),
                              for (var i = 0; i < tools.length; i++)
                                _RailItem(
                                  icon: tools[i].icon,
                                  label: tools[i].label,
                                  selected: currentTool == i,
                                  height: _slotHeight,
                                  onTap: () => onToolTap?.call(tools[i]),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onQuickAddTap != null) ...[
              const SizedBox(height: HxSpace.x4),
              Center(
                child: HxQuickAddButton(
                  open: quickAddOpen,
                  onTap: onQuickAddTap!,
                  size: 52,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(height: HxSpace.x4),
              Center(child: trailing),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () {
              if (selected) return;
              Haptics.selection();
              onTap();
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: height,
              child: Center(
                child: Icon(
                  icon,
                  size: 24,
                  color: selected ? hx.onPrimary : hx.secondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
