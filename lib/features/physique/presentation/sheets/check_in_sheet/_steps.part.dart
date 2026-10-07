part of '../check_in_sheet.dart';

/// Inline, non-blocking message (no blame, no danger colour).
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HxSpace.x4),
      decoration: BoxDecoration(
        color: hx.warning.withValues(alpha: 0.14),
        borderRadius: HxRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 20, color: hx.warning),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Text(
                  text,
                  style: PhysiqueText.body(context, color: hx.onSurface),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PoseStep extends StatelessWidget {
  const _PoseStep({
    required this.pose,
    required this.notice,
    required this.onPose,
    required this.onCamera,
    required this.onLibrary,
  });

  final String pose;
  final String? notice;
  final ValueChanged<String> onPose;
  final VoidCallback onCamera;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notice != null) ...[
          _Notice(text: notice!),
          const SizedBox(height: HxSpace.x4),
        ],
        Wrap(
          spacing: HxSpace.x2,
          runSpacing: HxSpace.x2,
          children: [
            for (final id in const ['front', 'side', 'back'])
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  widthFactor: 1,
                  child: HxPill(
                    selected: pose == id,
                    onTap: () => onPose(id),
                    child: Text(id[0].toUpperCase() + id.substring(1)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: HxSpace.x6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onCamera,
            child: const Text('Take photo'),
          ),
        ),
        const SizedBox(height: HxSpace.x3),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onLibrary,
            child: const Text('Choose from library'),
          ),
        ),
      ],
    );
  }
}

class _PrivacyStep extends StatelessWidget {
  const _PrivacyStep({
    required this.file,
    required this.blur,
    required this.notice,
    required this.busy,
    required this.progress,
    required this.onBlur,
    required this.onContinue,
  });

  final File file;
  final bool blur;
  final String? notice;
  final bool busy;
  final List<String> progress;
  final ValueChanged<bool> onBlur;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    if (busy) return _ProcessingView(labels: progress);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notice != null) ...[
          _Notice(text: notice!),
          const SizedBox(height: HxSpace.x4),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ClipRRect(
            borderRadius: HxRadius.mdAll,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              cacheWidth: 960,
              errorBuilder: (context, _, _) => Container(
                height: 160,
                color: hx.surfaceVariant,
                alignment: Alignment.center,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 24,
                  color: hx.tertiary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: blur,
          onChanged: onBlur,
          title: Text(
            'Blur my face',
            style: PhysiqueText.bodyStrong(context, color: hx.onSurface),
          ),
          subtitle: Text(
            'Happens on your device. The original face is never saved.',
            style: PhysiqueText.label(context, color: hx.secondary),
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        Text(
          'Location and camera details are removed from every photo.',
          style: PhysiqueText.label(context, color: hx.secondary),
        ),
        const SizedBox(height: HxSpace.x6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onContinue,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}

class _ConsentStep extends StatelessWidget {
  const _ConsentStep({
    required this.body,
    required this.onAnalyse,
    required this.onSaveWithoutAnalysis,
  });

  final String body;
  final VoidCallback onAnalyse;
  final VoidCallback onSaveWithoutAnalysis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          body,
          style: PhysiqueText.body(context, color: context.hx.onSurface),
        ),
        const SizedBox(height: HxSpace.x6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onAnalyse,
            child: const Text('Analyze my progress'),
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onSaveWithoutAnalysis,
            child: const Text('Save photo without analysis'),
          ),
        ),
      ],
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(height: HxSpace.x4),
            for (final label in labels)
              Text(
                label,
                textAlign: TextAlign.center,
                style: PhysiqueText.label(context, color: context.hx.secondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.text,
    required this.onSaveWithoutAnalysis,
    required this.onTryAgain,
  });

  final String text;
  final VoidCallback onSaveWithoutAnalysis;
  final VoidCallback? onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Notice(text: text),
        const SizedBox(height: HxSpace.x6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onSaveWithoutAnalysis,
            child: const Text('Save without analysis'),
          ),
        ),
        if (onTryAgain != null) ...[
          const SizedBox(height: HxSpace.x2),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onTryAgain,
              child: const Text('Try again'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({
    required this.recorded,
    required this.fallbackReason,
    required this.onDone,
  });

  final CheckInRecorded recorded;
  final String fallbackReason;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final evidence = recorded.evidence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VerdictBlock(
          verdict: recorded.verdict,
          band: evidence?.band,
          confidence: evidence?.confidence ?? AssessmentConfidence.unknown,
          reason: (evidence?.reason.isNotEmpty ?? false)
              ? evidence!.reason
              : fallbackReason,
        ),
        const SizedBox(height: HxSpace.x6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onDone, child: const Text('Done')),
        ),
      ],
    );
  }
}
