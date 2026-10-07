import 'package:flutter/material.dart';

import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/domain/narrative_status.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// The Herculex AI card of the weekly report (RPT-02, D-10).
///
/// It is the only report card tinted with the brand colour and the only one
/// carrying the AI pill and glyph, so the interpreted text can never be
/// mistaken for a measured number. The widget reads no providers: the
/// [status], the saved [narrative] and the retry hooks all come from the
/// caller. Suggestions are advisory text with no actions (D-12), and a saved
/// narrative has no refresh affordance (D-02).
class AiNarrativeCard extends StatelessWidget {
  const AiNarrativeCard({
    super.key,
    required this.status,
    this.narrative,
    this.onRetry,
    this.retryEnabled = true,
  });

  final NarrativeStatus status;

  /// Shown when [status] is [NarrativeStatus.ready].
  final WeeklyNarrative? narrative;

  /// Retry hook for the pending, offline and quota states.
  final VoidCallback? onRetry;

  /// Whether Retry can be tapped right now. Driven by the caller (for
  /// example false while a retry is in flight), never fixed by [status].
  final bool retryEnabled;

  static const String _note =
      'Herculex AI interprets the numbers above. It does not change them.';
  static const String _loadingLabel = 'Herculex AI is reading your week…';
  static const String _pendingCopy =
      "Narrative pending. Herculex AI couldn't write this week's summary. "
      'Your numbers above are saved. Try again.';
  static const String _offlineCopy =
      "You're offline. Reconnect and tap Retry narrative.";
  static const String _quotaCopy =
      "You've used today's Herculex AI summaries. Your numbers above are "
      'saved. Try again tomorrow.';

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final saved = narrative;
    // A "ready" card with nothing to show falls back to the pending face
    // rather than rendering an empty card.
    final effective = status == NarrativeStatus.ready && saved == null
        ? NarrativeStatus.pending
        : status;

    return Semantics(
      label: 'Herculex AI interpretation',
      container: true,
      child: HxCard(
        accent: hx.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(accent: hx.primaryText),
            const SizedBox(height: HxSpace.x4),
            switch (effective) {
              NarrativeStatus.loading => const _Loading(),
              NarrativeStatus.ready => _Ready(narrative: saved),
              NarrativeStatus.pending => _Failure(
                message: _pendingCopy,
                onRetry: onRetry,
                enabled: retryEnabled,
              ),
              NarrativeStatus.offline => _Failure(
                message: _offlineCopy,
                onRetry: onRetry,
                enabled: retryEnabled,
              ),
              NarrativeStatus.quotaExhausted => _Failure(
                message: _quotaCopy,
                onRetry: onRetry,
                enabled: retryEnabled,
              ),
            },
            const SizedBox(height: HxSpace.x4),
            Text(_note, style: ReportText.label(context)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 20, color: accent),
        const SizedBox(width: HxSpace.x2),
        Expanded(
          child: Text("This week's read", style: ReportText.heading(context)),
        ),
        const SizedBox(width: HxSpace.x2),
        const HxTextPill(label: 'Herculex AI'),
      ],
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.narrative});

  final WeeklyNarrative? narrative;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final n = narrative;
    if (n == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(n.summary, style: ReportText.body(context)),
        const SizedBox(height: HxSpace.x4),
        for (final suggestion in n.suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: HxSpace.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: HxSpace.x1),
                  child: Icon(
                    Icons.arrow_right_alt,
                    size: 20,
                    color: hx.primaryText,
                  ),
                ),
                const SizedBox(width: HxSpace.x2),
                Expanded(
                  child: Text(suggestion, style: ReportText.body(context)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    // One-shot fade-in of the placeholder lines; nothing loops.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: HxMotion.slow,
      curve: HxMotion.emphasized,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final widthFactor in const [1.0, 0.9, 0.6])
            Padding(
              padding: const EdgeInsets.only(bottom: HxSpace.x2),
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                child: Container(
                  key: const ValueKey('narrative-skeleton-line'),
                  height: HxSpace.x4,
                  decoration: BoxDecoration(
                    color: hx.surfaceVariant,
                    borderRadius: BorderRadius.circular(HxRadius.sm / 3),
                  ),
                ),
              ),
            ),
          const SizedBox(height: HxSpace.x2),
          Text(AiNarrativeCard._loadingLabel, style: ReportText.label(context)),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.message,
    required this.onRetry,
    required this.enabled,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    final canRetry = enabled && retry != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: ReportText.body(context)),
        const SizedBox(height: HxSpace.x4),
        // PremiumButton has no disabled state of its own, so a disabled
        // Retry is dimmed, ignores taps and is announced as disabled.
        Semantics(
          button: true,
          enabled: canRetry,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: IgnorePointer(
              ignoring: !canRetry,
              child: Opacity(
                opacity: canRetry ? 1 : 0.4,
                child: PremiumButton(
                  text: 'Retry narrative',
                  onTap: retry ?? () {},
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
