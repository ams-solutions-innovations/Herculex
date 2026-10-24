part of '../check_in_sheet.dart';

extension _CheckInCaptureSteps on _CheckInSheetState {
  Future<void> _pick(ImageSource source) async {
    if (_busy) {
      return;
    }
    final pending = ref.read(pendingAiScanServiceProvider);
    final capture = widget.capture ?? _defaultCapture;
    final pose = _pose;
    XFile? file;
    try {
      await pending.setPendingContext(
        PendingAiScanContext(
          type: AiScanContextType.physiqueCheckin,
          extra: {
            'goalId': widget.goal.id,
            'pose': pose,
            'photos': _sources.map((p, f) => MapEntry(p, f.path)),
            'updateRoadmap': widget.updateRoadmap,
          },
          createdAt: ref.read(clockProvider).now(),
        ),
      );
      file = await capture(source);
    } on Object {
      if (mounted) {
        _setCaptureState(() => _notice = _CheckInSheetState._unreadable);
      }
    } finally {
      await pending.clearPendingContext();
    }
    if (file == null || !mounted) {
      return;
    }
    _setCaptureState(() {
      _sources[pose] = File(file!.path);
      _notice = null;
    });
  }

  Future<void> _discardStaged() async {
    final photos = [..._staged];
    _staged.clear();
    for (final p in photos) {
      await _flow.discardStaged(p.photo);
    }
  }

  Future<void> _continue({required bool baseline}) async {
    if (_sources.isEmpty || _busy) {
      return;
    }
    _setCaptureState(() {
      _busy = true;
      _notice = null;
      _progress = [
        'Removing location data...',
        if (_blur) 'Checking for faces...',
      ];
    });
    await ref.read(physiquePrivacyPreferencesProvider).setBlurFaces(_blur);
    await _discardStaged();
    final staged = <StagedPosePhoto>[];
    try {
      for (final p in _sources.entries) {
        staged.add(
          StagedPosePhoto(
            pose: p.key,
            photo: await _flow.stage(p.value, blurFaces: _blur),
          ),
        );
      }
      if (!mounted) {
        for (final p in staged) {
          await _flow.discardStaged(p.photo);
        }
        return;
      }
      if (staged.any((p) => p.photo.noFaceFound)) {
        final choice = await NoFaceFoundDialog.show(context);
        if (choice != NoFaceChoice.saveWithoutBlur || !mounted) {
          for (final p in staged) {
            await _flow.discardStaged(p.photo);
          }
          _backToPose(null);
          return;
        }
      }
      _staged.addAll(staged);
      if (baseline) {
        await _saveBaseline();
        return;
      }
      final accepted = ref
          .read(physiquePrivacyPreferencesProvider)
          .hasAcceptedConsent(dreamPhysiqueImageConsentVersion);
      if (accepted) {
        await _analyse(analyze: true);
      } else {
        _setCaptureState(() {
          _busy = false;
          _step = _Step.consent;
        });
      }
    } on Object catch (error) {
      for (final p in staged) {
        await _flow.discardStaged(p.photo);
      }
      _staged.clear();
      _backToPose(
        error is PhotoSanitizeException
            ? _CheckInSheetState._unreadable
            : _CheckInSheetState._storageFailed,
      );
    }
  }

  void _backToPose(String? notice) {
    if (!mounted) {
      return;
    }
    _setCaptureState(() {
      _busy = false;
      _step = _Step.pose;
      _notice = notice;
    });
  }

  Future<void> _saveBaseline() async {
    try {
      await _flow.saveBaseline(goal: widget.goal, photos: [..._staged]);
      _staged.clear();
      if (!mounted) {
        return;
      }
      final notices = widget.outerNotices;
      Navigator.of(context).pop();
      notices.show(
        _sources.length == 1
            ? 'Baseline photo saved.'
            : 'Baseline photos saved.',
      );
    } on Object {
      if (mounted) {
        _setCaptureState(() {
          _busy = false;
          _notice = _CheckInSheetState._storageFailed;
        });
      }
    }
  }
}
