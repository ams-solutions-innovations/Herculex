import 'package:flutter/material.dart';

/// How far an in-workout swap reaches into the program.
enum SwapChoice { today, thisWave, futureWaves, entireBlock, permanent }

class SwapScopeDialog extends StatelessWidget {
  const SwapScopeDialog({
    super.key,
    required this.exerciseName,
    required this.percentage,
    required this.hasWaves,
  });

  final String exerciseName;
  final int? percentage;
  final bool hasWaves;

  @override
  Widget build(BuildContext context) {
    final match = percentage == null ? '' : ' ($percentage% match)';
    return SimpleDialog(
      title: const Text('Apply replacement to'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Replace with $exerciseName$match.'),
        ),
        _option(context, SwapChoice.today, 'Today only', null),
        if (hasWaves) ...[
          _option(
            context,
            SwapChoice.thisWave,
            'This wave',
            'This continuous run of the exercise; later waves keep theirs.',
          ),
          _option(
            context,
            SwapChoice.futureWaves,
            'This and future waves',
            'Keeps earlier waves, replaces this one and all later ones.',
          ),
          _option(
            context,
            SwapChoice.entireBlock,
            'Entire block',
            'Every week of the program.',
          ),
        ] else
          _option(
            context,
            SwapChoice.permanent,
            'Permanently',
            'Replace it in this routine for every future session.',
          ),
      ],
    );
  }

  Widget _option(
    BuildContext context,
    SwapChoice choice,
    String title,
    String? subtitle,
  ) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () => Navigator.pop(context, choice),
    );
  }
}
