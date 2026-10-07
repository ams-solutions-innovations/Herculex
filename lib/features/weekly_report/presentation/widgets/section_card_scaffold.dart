import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// The four UI-SPEC type roles the report uses (Body 16, Label 14,
/// Heading 20, all 400 or 600). Kept here so the section cards and the AI
/// card share one definition and never reach for the 11/15/18/19 sizes of the
/// global text theme.
abstract final class ReportText {
  static TextStyle _make(
    TextStyle? base,
    double size,
    FontWeight weight,
    double height,
    Color color,
  ) => (base ?? const TextStyle()).copyWith(
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color,
  );

  /// Section card titles: 20 / 600 / 1.2 on the display face.
  static TextStyle heading(BuildContext context) => _make(
    Theme.of(context).textTheme.headlineSmall,
    20,
    FontWeight.w600,
    1.2,
    context.hx.onSurface,
  );

  /// Narrative, suggestions and row text: 16 / 400 / 1.5.
  static TextStyle body(BuildContext context) => _make(
    Theme.of(context).textTheme.bodyLarge,
    16,
    FontWeight.w400,
    1.5,
    context.hx.onSurface,
  );

  /// Captions, notes and the empty-section line: 14 / 400 / 1.5.
  static TextStyle label(BuildContext context) => _make(
    Theme.of(context).textTheme.bodyMedium,
    14,
    FontWeight.w400,
    1.5,
    context.hx.onSurfaceVariant,
  );
}

/// Shared frame of the four measured section cards: an [HxCard] with the
/// domain [accent] (never the brand colour, which is reserved for the Herculex
/// AI card), a heading row, and either [body] or the single empty-section
/// label.
class SectionCardScaffold extends StatelessWidget {
  const SectionCardScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    this.accent,
  });

  /// The one empty-section line (UI-SPEC copywriting contract).
  static const String noDataLabel = 'No data this week';

  final String title;
  final IconData icon;
  final Color? accent;

  /// Null means the section has no data this week.
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accent ?? hx.onSurfaceVariant),
              const SizedBox(width: HxSpace.x2),
              Expanded(child: Text(title, style: ReportText.heading(context))),
            ],
          ),
          const SizedBox(height: HxSpace.x4),
          body ?? Text(noDataLabel, style: ReportText.label(context)),
        ],
      ),
    );
  }
}

/// Lays [tiles] out two per row with `x2` gaps, so a card with an odd number
/// of tiles keeps the last one at half width instead of stretching.
class ReportTileGrid extends StatelessWidget {
  const ReportTileGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: HxSpace.x2));
      final second = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: HxSpace.x2),
              Expanded(child: second ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// Signed number for deltas: `+1.5`, `-0.4`, `0`.
String signedNumber(double value, {int fractionDigits = 1}) {
  final text = value.abs().toStringAsFixed(fractionDigits);
  if (double.parse(text) == 0) return '0';
  return value < 0 ? '-$text' : '+$text';
}
