import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/error/error_log.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/presentation/sheets/tdee_estimate_sheet.dart';

/// Minimum tappable height (platform touch-target floor).
const double _kMinTarget = 44;

/// Inline status chip under "Maintenance calories" (D-05, D-08): always says
/// how the current maintenance estimate was reached and how far to trust it,
/// and opens [TdeeEstimateSheet] on tap.
///
/// It describes the estimate, never the text being typed in the field above.
/// Once an estimate exists it is never blank and never an error look: cold
/// start, load failure and a stored cold-start row all read "Calibrating".
class TdeeEstimateBadge extends ConsumerWidget {
  const TdeeEstimateBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Report a failed read once, on the transition into the error state.
    ref.listen<AsyncValue<TdeeEstimateResult?>>(latestTdeeEstimateProvider, (
      previous,
      next,
    ) {
      if (next.hasError && !(previous?.hasError ?? false)) {
        ErrorLog.instance.record(
          next.error!,
          source: 'tdee',
          stack: next.stackTrace,
          details: 'latest TDEE estimate read failed',
        );
      }
    });

    final profile = ref.watch(profileProvider);
    final latest = ref.watch(latestTdeeEstimateProvider);
    final estimate = ref.watch(tdeeEstimateProvider);

    final Widget content;
    if ((profile.isLoading && !profile.hasValue) ||
        (latest.isLoading && !latest.hasValue)) {
      // Layout stability only: a local read, so no spinner.
      content = const SizedBox(key: ValueKey('loading'), height: _kMinTarget);
    } else if (estimate == null) {
      // The profile lacks weight, height or age: there is no estimate to
      // describe and no maintenance number on screen to decorate.
      content = const SizedBox.shrink(key: ValueKey('none'));
    } else {
      content = _Badge(
        key: ValueKey(estimate.badgeState),
        state: estimate.badgeState,
        confidence: estimate.confidence,
      );
    }

    return AnimatedSwitcher(duration: HxMotion.base, child: content);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.state, required this.confidence});

  final TdeeBadgeState state;
  final TdeeConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final visuals = tdeeBadgeVisuals(hx, state);
    final label = state.label(confidence);
    // "Measured · High confidence" -> "Measured, High confidence".
    final spoken = label.replaceFirst(' · ', ', ').replaceFirst(' — ', ', ');

    void open() => showTdeeEstimateSheet(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: 'Maintenance estimate: $spoken. Double tap for details.',
        // The visible pill is ~24px tall; this wrapper lifts the hit area to
        // the 44px floor without inflating the visual.
        child: GestureDetector(
          key: const ValueKey('tdee_badge_target'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.selection();
            open();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _kMinTarget),
            child: Center(
              widthFactor: 1,
              child: HxPill(
                selected: true,
                accent: visuals.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: HxSpace.x2,
                  vertical: HxSpace.x1,
                ),
                onTap: open,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(visuals.icon, size: 16, color: visuals.accent),
                    const SizedBox(width: HxSpace.x1),
                    Flexible(
                      child: Text(
                        label,
                        softWrap: true,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          // Accent decorates icon, border and tint only,
                          // so contrast holds in every theme.
                          color: hx.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: HxSpace.x1),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: hx.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
