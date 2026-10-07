import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';

/// Card-level loading indicator (UI-SPEC: adaptive, 24, centred).
class PhysiqueLoading extends StatelessWidget {
  const PhysiqueLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: HxSpace.x4),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(),
        ),
      ),
    );
  }
}

/// Provider error line with a retry that invalidates the failed provider.
class PhysiqueLoadError extends StatelessWidget {
  const PhysiqueLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Couldn't load this right now.",
          style: PhysiqueText.body(context),
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
