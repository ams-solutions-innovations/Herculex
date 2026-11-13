import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Page chrome shared by every onboarding screen: gradient backdrop, an
/// optional back / skip row, an optional segmented progress bar and a pill
/// call-to-action pinned to the bottom.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.child,
    this.onBack,
    this.onSkip,
    this.skipLabel = 'Skip',
    this.progressStep,
    this.progressTotal = 0,
    this.ctaLabel,
    this.onCta,
    this.footer,
    this.topPadding = 20,
  });

  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final String skipLabel;

  /// Zero-based index of the current step; null hides the progress bar.
  final int? progressStep;
  final int progressTotal;

  final String? ctaLabel;

  /// Null disables the CTA.
  final VoidCallback? onCta;

  /// Rendered under the CTA (links, legal text).
  final Widget? footer;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Scaffold(
      backgroundColor: hx.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [hx.gradientTop, hx.gradientMid, hx.gradientBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          if (onBack != null)
                            IconButton(
                              tooltip: 'Back',
                              icon: Icon(
                                Icons.arrow_back_rounded,
                                color: hx.onSurface,
                              ),
                              onPressed: onBack,
                            )
                          else
                            const SizedBox(width: 48),
                          const Spacer(),
                          if (onSkip != null)
                            TextButton(
                              onPressed: onSkip,
                              child: Text(
                                skipLabel,
                                style: TextStyle(
                                  color: hx.onSurfaceVariant,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (progressStep != null && progressTotal > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: OnboardingProgress(
                        step: progressStep!,
                        total: progressTotal,
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(24, topPadding, 24, 0),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - topPadding,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                  if (ctaLabel != null || footer != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (ctaLabel != null)
                            Opacity(
                              opacity: onCta == null ? 0.45 : 1,
                              child: PremiumButton(
                                expand: true,
                                text: ctaLabel!,
                                onTap: onCta ?? () {},
                              ),
                            ),
                          if (footer != null) ...[
                            const SizedBox(height: 12),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Equal-width segments; every segment up to and including [step] is filled.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.step,
    required this.total,
  });

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Semantics(
      label: 'Step ${step + 1} of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: HxSpace.x2),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? hx.primary : hx.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
