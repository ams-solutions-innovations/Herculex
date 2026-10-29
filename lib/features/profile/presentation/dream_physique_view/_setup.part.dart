part of '../dream_physique_view.dart';

extension _DreamPhysiqueSetup on _DreamPhysiqueViewState {
  static const _poseLabels = ['FRONT', 'SIDE', 'BACK'];
  static const _poseIcons = [
    Icons.accessibility_new_rounded,
    Icons.directions_walk_rounded,
    Icons.person_rounded,
  ];

  Widget _buildSetupView() {
    final hx = context.hx;
    final filled = _currentFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'Where you are.\n',
            children: [
              TextSpan(
                text: "Where you're going.",
                style: TextStyle(color: hx.primaryText),
              ),
            ],
          ),
          style: _dpDisplay(30, letterSpacing: -0.7, height: 1.05),
        ),
        const SizedBox(height: HxSpace.x2),
        Text(
          'Compare your physique with a goal photo. You get a realistic '
          'timeframe, body-fat path and muscle priorities.',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: hx.secondary,
          ),
        ),
        const SizedBox(height: 22),
        _stepHeader(
          done: filled > 0,
          title: 'You, today',
          count: '$filled / 3',
        ),
        const SizedBox(height: HxSpace.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _DreamPhysiqueViewState._poses.length; i++) ...[
              if (i > 0) const SizedBox(width: HxSpace.x2),
              Expanded(child: _poseSlot(i)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DpSecondaryButton(
                label: 'Camera',
                icon: Icons.photo_camera_rounded,
                onPressed: _pickWithCamera,
              ),
            ),
            const SizedBox(width: HxSpace.x2),
            Expanded(
              child: _DpSecondaryButton(
                key: const Key('dream-physique-progress-gallery'),
                label: _savedPhotos.isEmpty
                    ? 'Photo library'
                    : 'Progress gallery',
                icon: Icons.photo_library_rounded,
                onPressed: _savedPhotos.isEmpty
                    ? _pickFromLibrary
                    : _openProgressGallery,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _stepHeader(
          done: _targetFile != null,
          title: 'Your goal',
          count: '${_targetFile == null ? 0 : 1} / 1',
        ),
        const SizedBox(height: HxSpace.x3),
        _goalSlot(),
        const SizedBox(height: 22),
        const _DpEyebrow('WHAT MATTERS MOST? · OPTIONAL', spacing: 1.4),
        const SizedBox(height: HxSpace.x2),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final intent in _DreamPhysiqueViewState._intentOptions)
              _intentChip(intent),
          ],
        ),
        const SizedBox(height: 22),
        _privacyCard(),
      ],
    );
  }

  Widget _stepHeader({
    required bool done,
    required String title,
    required String count,
  }) {
    final hx = context.hx;
    return Row(
      children: [
        AnimatedContainer(
          duration: HxMotion.base,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: done ? hx.primary : hx.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 16, color: hx.onPrimary)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: _dpDisplay(18))),
        Text(
          count,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: hx.secondary,
          ),
        ),
      ],
    );
  }

  Widget _poseSlot(int index) {
    final hx = context.hx;
    final file = _poseFiles[index];
    final filled = file != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 148,
          child: _DpSlotBorder(
            radius: 18,
            dashed: !filled,
            color: filled ? hx.primary.withValues(alpha: 0.5) : hx.outline,
            background: hx.surfaceContainerLowest,
            child: filled
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      _DpPhoto(file),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _DpPhotoClose(onTap: () => _clearSlot(index)),
                      ),
                    ],
                  )
                : Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('dream-physique-slot-$index'),
                      onTap: () => _pickIntoSlot(index, ImageSource.gallery),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _poseIcons[index],
                            size: 34,
                            weight: 300,
                            color: hx.tertiary,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                size: 14,
                                color: hx.secondary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Add',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: hx.secondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _poseLabels[index],
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: filled ? hx.primaryText : hx.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _goalSlot() {
    final hx = context.hx;
    final file = _targetFile;
    return SizedBox(
      height: 196,
      child: _DpSlotBorder(
        radius: 22,
        dashed: file == null,
        color: file == null ? hx.outline : hx.primary.withValues(alpha: 0.5),
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [
            hx.primary.withValues(alpha: 0.14),
            hx.surfaceContainerLowest,
          ],
          stops: const [0, 0.7],
        ),
        child: file != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _DpPhoto(file, placeholderIcon: Icons.star_rounded),
                  const Positioned(
                    left: 10,
                    bottom: 10,
                    child: _DpPhotoTag('GOAL'),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _DpPhotoClose(onTap: _clearTarget, size: 28),
                  ),
                ],
              )
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('dream-physique-goal-slot'),
                  onTap: _pickTargetPhoto,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: hx.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.add_photo_alternate_rounded,
                            size: 28,
                            color: hx.primaryText,
                          ),
                        ),
                        const SizedBox(height: HxSpace.x2),
                        const Text(
                          'Add a goal photo',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: HxSpace.x2),
                        Text(
                          'A role model, an old photo of you, anything',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hx.secondary,
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

  Widget _intentChip(String intent) {
    final hx = context.hx;
    final on = _intents.contains(intent);
    return Material(
      color: on ? hx.primary.withValues(alpha: 0.16) : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: on ? hx.primary : hx.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _toggleIntent(intent),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          // widthFactor keeps the chip as wide as its label inside the Wrap.
          child: Center(
            widthFactor: 1,
            child: Text(
              intent,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: on ? hx.primaryText : hx.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Explicit, per-analysis consent. Kept in memory only, and survives a
  /// recoverable request failure.
  Widget _privacyCard() {
    final hx = context.hx;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleConsent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _dpCard(context, radius: 20),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, size: 20, color: hx.primaryText),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Text(
                'Photos are sent once to Herculex AI (Google Gemini) for this '
                'analysis and are not kept on our servers.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: hx.secondary,
                ),
              ),
            ),
            const SizedBox(width: HxSpace.x3),
            _DpToggle(
              key: const Key('dream-physique-privacy-consent'),
              value: _privacyConsentGranted,
              onChanged: (_) => _toggleConsent(),
            ),
          ],
        ),
      ),
    );
  }

  /// The CTA names whatever is still missing, and only starts the analysis
  /// once nothing is.
  Widget _buildAnalyzeButton() {
    final label = _currentFiles.isEmpty
        ? 'Add a photo of you'
        : _targetFile == null
        ? 'Add a goal photo'
        : !_privacyConsentGranted
        ? 'Allow photo analysis'
        : 'Analyze with Herculex AI';
    return _DpPrimaryButton(
      key: const Key('dream-physique-start-analysis'),
      label: label,
      icon: Icons.auto_awesome,
      onPressed: _readyToAnalyze ? _startAnalysis : null,
    );
  }

  Future<void> _openProgressGallery() async {
    Haptics.light();
    await HxSheet.show<void>(
      context,
      builder: (sheetContext) => HxSheet(
        title: 'Progress gallery',
        subtitle: 'Tap a photo to use it. It goes into its own pose slot.',
        trailing: TextButton(
          onPressed: () {
            Navigator.of(sheetContext).pop();
            _pickFromLibrary();
          },
          child: const Text('Photo library'),
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: HxSpace.x2,
            crossAxisSpacing: HxSpace.x2,
            childAspectRatio: 0.75,
            children: [
              for (final photo in _savedPhotos)
                _savedPhotoTile(photo, () {
                  _useSavedPhoto(photo);
                  setSheetState(() {});
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _savedPhotoTile(ProgressPhotoData photo, VoidCallback onTap) {
    final hx = context.hx;
    final file = LocalPhotoStore.resolveSync(photo.filePath);
    final selected = _poseFiles.any((f) => f?.path == file.path);
    return GestureDetector(
      onTap: onTap,
      child: _DpSlotBorder(
        radius: 14,
        dashed: false,
        color: selected ? hx.primary : hx.outlineVariant,
        background: hx.surfaceContainerLowest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _DpPhoto(file),
            if (selected)
              ColoredBox(
                color: hx.primary.withValues(alpha: 0.35),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: _DpPhotoTag(photo.pose.toUpperCase()),
            ),
          ],
        ),
      ),
    );
  }
}
