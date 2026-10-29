import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Lays [children] out in as many equal columns as fit, so a list of cards
/// reads as a grid in a wide window and stays a plain column on a phone.
///
/// Children keep their own height (a template tile and a folder tile need not
/// match), and go to the columns in turn, so reading order is left to right,
/// then down. Not lazy: use it for lists of a few dozen, and a sliver grid for
/// long ones.
class HxMasonry extends StatelessWidget {
  const HxMasonry({
    super.key,
    required this.children,
    this.minColumnWidth = 380,
    this.maxColumns = 3,
    this.gap = 12,
  });

  final List<Widget> children;

  /// A column is never narrower than this, so the column count follows the
  /// width available.
  final double minColumnWidth;
  final int maxColumns;

  /// Space between columns. Tiles bring their own bottom margin.
  final double gap;

  /// How many columns [width] fits.
  static int columnsFor(
    double width, {
    double minColumnWidth = 380,
    int maxColumns = 3,
    double gap = 12,
  }) {
    if (!width.isFinite) return 1;
    final fit = ((width + gap) / (minColumnWidth + gap)).floor();
    return math.max(1, math.min(maxColumns, fit));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          constraints.maxWidth,
          minColumnWidth: minColumnWidth,
          maxColumns: maxColumns,
          gap: gap,
        );
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        }
        final lanes = List.generate(columns, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          lanes[i % columns].add(children[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: lanes[c],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
