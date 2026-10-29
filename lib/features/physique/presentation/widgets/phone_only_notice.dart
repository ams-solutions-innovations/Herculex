import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Shown on the web in place of the photo steps of Dream Physique.
///
/// Photos are picked, kept and analysed on the phone — the files never sync,
/// and the browser has no app sandbox to hold them — so the browser offers
/// what does sync: the goal, the roadmap and the check-in results.
class PhysiquePhoneOnlyNotice extends StatelessWidget {
  const PhysiquePhoneOnlyNotice({super.key, this.showProgressButton = true});

  /// Whether to offer the progress screen, which is where synced goals live.
  final bool showProgressButton;

  static const title = 'Photo analysis runs in the phone app';
  static const body =
      'Your physique photos stay on your phone and are analysed there. Your '
      'Dream Physique goal, roadmap and check-in results sync to this account, '
      'so you can follow your progress here.';

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxCard(
      accent: hx.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(HxSpace.x2),
                decoration: BoxDecoration(
                  color: hx.primary,
                  borderRadius: BorderRadius.circular(HxRadius.md),
                ),
                child: Icon(
                  Icons.smartphone_rounded,
                  color: hx.onPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Text(
                  title,
                  style: PhysiqueText.heading(context, color: hx.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          Text(
            body,
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
          if (showProgressButton) ...[
            const SizedBox(height: HxSpace.x4),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.dreamPhysiqueProgress),
              icon: const Icon(Icons.show_chart_rounded),
              label: const Text('View my progress'),
            ),
          ],
        ],
      ),
    );
  }
}
