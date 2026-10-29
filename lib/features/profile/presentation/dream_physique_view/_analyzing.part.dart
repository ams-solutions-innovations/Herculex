part of '../dream_physique_view.dart';

extension _DreamPhysiqueAnalyzing on _DreamPhysiqueViewState {
  Widget _buildAnalyzingView() {
    final hx = context.hx;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -60,
          right: -60,
          top: 10,
          height: 420,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    hx.primary.withValues(alpha: 0.22),
                    hx.primary.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.7],
                ),
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: HxSpace.x2),
            Row(
              children: [
                Expanded(
                  child: _scanPhoto(
                    _currentFiles.isEmpty ? null : _currentFiles.first,
                    tag: const _DpPhotoTag('NOW'),
                    border: hx.outlineVariant,
                    delay: 0,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _scanPhoto(
                    _targetFile,
                    tag: _DpPhotoTag('GOAL', color: hx.primary),
                    border: hx.primary.withValues(alpha: 0.45),
                    delay: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              'Comparing physiques',
              textAlign: TextAlign.center,
              style: _dpDisplay(26, letterSpacing: -0.5),
            ),
            const SizedBox(height: HxSpace.x1),
            Text(
              'Usually takes 15–30 seconds',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hx.secondary,
              ),
            ),
            const SizedBox(height: 22),
            for (
              var i = 0;
              i < _DreamPhysiqueViewState._analysisSteps.length;
              i++
            )
              _analysisStepRow(i),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                key: const Key('dream-physique-cancel-analysis'),
                onPressed: _cancelAnalysis,
                style: OutlinedButton.styleFrom(
                  foregroundColor: hx.secondary,
                  side: BorderSide(color: hx.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scanPhoto(
    File? file, {
    required Widget tag,
    required Color border,
    required double delay,
  }) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
        color: context.hx.surfaceContainerLowest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _DpPhoto(file),
            _DpScanLine(delay: delay),
            Positioned(left: 10, top: 10, child: tag),
          ],
        ),
      ),
    );
  }

  Widget _analysisStepRow(int index) {
    final hx = context.hx;
    final done = index < _analysisStep;
    final current = index == _analysisStep;
    return AnimatedContainer(
      duration: HxMotion.base,
      margin: const EdgeInsets.only(bottom: HxSpace.x1),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: current ? hx.primary.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: done
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 22,
                      color: hx.success,
                    )
                  : current
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: hx.primary,
                        backgroundColor: hx.primary.withValues(alpha: 0.25),
                      ),
                    )
                  : Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: hx.outline,
                    ),
            ),
          ),
          const SizedBox(width: HxSpace.x3),
          Expanded(
            child: Text(
              _DreamPhysiqueViewState._analysisSteps[index],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: done
                    ? hx.onSurfaceVariant
                    : current
                    ? hx.onSurface
                    : hx.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The glowing line that sweeps up and down a photo while it is analysed.
class _DpScanLine extends StatefulWidget {
  const _DpScanLine({required this.delay});

  /// Phase offset in seconds, so the two photos do not scan in lockstep.
  final double delay;

  @override
  State<_DpScanLine> createState() => _DpScanLineState();
}

class _DpScanLineState extends State<_DpScanLine>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 2400);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
    value: widget.delay * 1000 / _period.inMilliseconds,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Down for the first half of the period, back up for the second.
            final t = _controller.value;
            final travel = Curves.easeInOut.transform(
              t < 0.5 ? t * 2 : 2 - t * 2,
            );
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: travel * (constraints.maxHeight - 3),
                  child: child!,
                ),
              ],
            );
          },
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: hx.primaryText,
              boxShadow: [
                BoxShadow(
                  color: hx.primary.withValues(alpha: 0.6),
                  blurRadius: 18,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
