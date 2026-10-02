import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_check_in_flow.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_checkin_service.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/dialogs/no_face_found_dialog.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/sheet_snackbar_scope.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_block.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

part 'check_in_sheet/_steps.part.dart';

enum _Step { pose, privacy, consent, working, result }

/// Picks a photo from [source]; replaced in tests so no platform channel runs.
typedef CheckInCapture = Future<XFile?> Function(ImageSource source);

Future<XFile?> _defaultCapture(ImageSource source) => ImagePicker().pickImage(
  source: source,
  maxWidth: 2048,
  maxHeight: 2048,
  imageQuality: 90,
);

/// Add check-in (S3): pose, privacy options, consent, analysis and result. A
/// goal with no baseline photo gets a two-step baseline mode instead (no cap,
/// no AI). The sheet only sequences UI; the work lives in
/// [PhysiqueCheckInFlow].
class CheckInSheet extends ConsumerStatefulWidget {
  const CheckInSheet({
    super.key,
    required this.goal,
    required this.outerMessenger,
    this.resumed,
    this.capture,
  });

  final PhysiqueGoalData goal;
  final ResumedCapture? resumed;
  final CheckInCapture? capture;

  /// The messenger outside the sheet, so confirmations outlive it.
  final ScaffoldMessengerState outerMessenger;

  /// DRAFT copy pending legal review (RESEARCH A10, Open Question 7). The one
  /// place to edit it.
  static const _consentBody =
      'Your photos stay on this device. Herculex AI looks at them once to '
      "compare your progress, and Herculex doesn't keep a copy.";

  static Future<void> show(
    BuildContext context, {
    required PhysiqueGoalData goal,
    ResumedCapture? resumed,
    @visibleForTesting CheckInCapture? capture,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    return HxSheet.show<void>(
      context,
      builder: (_) => SheetSnackBarScope(
        child: CheckInSheet(
          goal: goal,
          resumed: resumed,
          capture: capture,
          outerMessenger: messenger,
        ),
      ),
    );
  }

  @override
  ConsumerState<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<CheckInSheet> {
  static const _aiUnavailable =
      "Herculex AI isn't available right now. Save your photo without "
      'analysis and it will still count as this week\'s check-in.';
  static const _quotaExhausted =
      "You've used today's Herculex AI check-ins. Try again tomorrow, or "
      'save your photo without analysis.';
  static const _unreadable =
      "We couldn't read that photo. Try another one or take a new picture.";
  static const _storageFailed =
      "We couldn't save your photo. Check your free storage and try again.";
  static const _noAnalysisReason =
      "Herculex AI couldn't review this photo, so this check-in is "
      'inconclusive.';

  late final PhysiqueCheckInFlow _flow;
  late bool _blur;
  _Step _step = _Step.pose;
  String _pose = 'front';
  File? _source;
  StagedPhoto? _staged;
  bool _busy = false;
  List<String> _progress = const [];
  String? _notice;
  _AnalysisError? _error;
  CheckInRecorded? _recorded;

  @override
  void initState() {
    super.initState();
    _flow = ref.read(physiqueCheckInFlowProvider);
    _blur = ref.read(physiquePrivacyPreferencesProvider).blurFaces;
    final resumed = widget.resumed;
    if (resumed != null) {
      _pose = resumed.pose;
      _source = File(resumed.path);
      _step = _Step.privacy;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(physiqueResumedCaptureProvider.notifier).state = null;
      });
    }
  }

  @override
  void dispose() {
    final staged = _staged;
    if (staged != null) _flow.discardStaged(staged);
    super.dispose();
  }

  bool get _baselineMode {
    final photos = ref.watch(physiquePhotosProvider(widget.goal.id));
    final rows = photos.asData?.value;
    return rows != null && !rows.any((p) => p.role == 'baseline');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _pick(ImageSource source) async {
    final pending = ref.read(pendingAiScanServiceProvider);
    final clock = ref.read(clockProvider);
    final capture = widget.capture ?? _defaultCapture;
    XFile? file;
    try {
      await pending.setPendingContext(
        PendingAiScanContext(
          type: AiScanContextType.physiqueCheckin,
          extra: {'goalId': widget.goal.id, 'pose': _pose},
          createdAt: clock.now(),
        ),
      );
      file = await capture(source);
    } on Object {
      if (mounted) setState(() => _notice = _unreadable);
    } finally {
      await pending.clearPendingContext();
    }
    if (file == null || !mounted) return;
    setState(() {
      _source = File(file!.path);
      _step = _Step.privacy;
      _notice = null;
    });
  }

  Future<void> _continue({required bool baseline}) async {
    final source = _source;
    if (source == null || _busy) return;
    final prefs = ref.read(physiquePrivacyPreferencesProvider);
    await prefs.setBlurFaces(_blur);
    if (!mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
      _progress = [
        'Removing location data...',
        if (_blur) 'Checking for faces...',
      ];
    });
    StagedPhoto staged;
    try {
      staged = await _flow.stage(source, blurFaces: _blur);
    } on PhotoSanitizeException {
      _backToPose(_unreadable);
      return;
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = _storageFailed;
        });
      }
      return;
    }
    if (!mounted) {
      await _flow.discardStaged(staged);
      return;
    }
    if (staged.noFaceFound) {
      final choice = await NoFaceFoundDialog.show(context);
      if (choice != NoFaceChoice.saveWithoutBlur) {
        await _flow.discardStaged(staged);
        _backToPose(null);
        return;
      }
      if (!mounted) {
        await _flow.discardStaged(staged);
        return;
      }
    }
    _staged = staged;
    if (baseline) {
      await _saveBaseline(staged);
      return;
    }
    final accepted = ref
        .read(physiquePrivacyPreferencesProvider)
        .hasAcceptedConsent(dreamPhysiqueImageConsentVersion);
    if (accepted) {
      await _analyse(analyze: true);
    } else {
      setState(() {
        _busy = false;
        _step = _Step.consent;
      });
    }
  }

  void _backToPose(String? notice) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _staged = null;
      _source = null;
      _step = _Step.pose;
      _notice = notice;
    });
  }

  Future<void> _saveBaseline(StagedPhoto staged) async {
    try {
      await _flow.saveBaseline(goal: widget.goal, staged: staged, pose: _pose);
      _staged = null;
      if (!mounted) return;
      final messenger = widget.outerMessenger;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Baseline photo saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object {
      // Keep the staged file so the user can retry from the same screen.
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = _storageFailed;
        });
      }
    }
  }

  Future<void> _acceptAndAnalyse() async {
    await ref
        .read(physiquePrivacyPreferencesProvider)
        .acceptConsent(dreamPhysiqueImageConsentVersion);
    if (!mounted) return;
    await _analyse(analyze: true);
  }

  Future<void> _analyse({required bool analyze}) async {
    final staged = _staged;
    if (staged == null) return;
    final ctx = ref.read(physiqueCheckInContextProvider(widget.goal.id));
    final consent = ref
        .read(physiquePrivacyPreferencesProvider)
        .hasAcceptedConsent(dreamPhysiqueImageConsentVersion);
    setState(() {
      _busy = true;
      _error = null;
      _step = _Step.working;
      _progress = [
        if (analyze) 'Comparing with your baseline...' else 'Saving...',
      ];
    });
    try {
      final outcome = await _flow.completeCheckIn(
        goal: widget.goal,
        staged: staged,
        pose: _pose,
        phase: ctx.phase,
        weeksInPhase: ctx.weeksInPhase,
        analyze: analyze,
        consentGranted: analyze && consent,
        weightKg: ctx.weightKg,
        weeklyTrendKg: ctx.weeklyTrendKg,
      );
      if (!mounted) return;
      switch (outcome) {
        case CheckInRecorded():
          _staged = null;
          setState(() {
            _busy = false;
            _recorded = outcome;
            _step = _Step.result;
          });
        case CheckInAiUnavailable(:final failure, :final message):
          setState(() {
            _busy = false;
            _error = _AnalysisError(
              text: switch (failure) {
                PhysiqueCheckInFailure.quotaExhausted => _quotaExhausted,
                PhysiqueCheckInFailure.invalidInput => message,
                _ => _aiUnavailable,
              },
              canRetry: failure != PhysiqueCheckInFailure.quotaExhausted,
            );
          });
        case BaselineSaved():
          break;
      }
    } on CheckInTooSoonException catch (e) {
      await _flow.discardStaged(staged);
      _staged = null;
      if (!mounted) return;
      final messenger = widget.outerMessenger;
      Navigator.of(context).pop();
      final next = DateFormat('EEE, MMM d').format(e.nextEligibleDate);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "You've already checked in this week. Your next check-in is "
            'available $next.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = const _AnalysisError(text: _storageFailed, canRetry: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseline = _baselineMode;
    final total = baseline ? 2 : 4;
    final index = switch (_step) {
      _Step.pose => 1,
      _Step.privacy => 2,
      _Step.consent => 3,
      _Step.working => baseline ? 2 : 3,
      _Step.result => 4,
    };

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) _snack('Hang on, almost done');
      },
      child: HxSheet(
        title: baseline ? 'Add baseline photo' : 'Add check-in',
        initialSize: 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step $index of $total',
              style: PhysiqueText.label(context, color: context.hx.secondary),
            ),
            const SizedBox(height: HxSpace.x4),
            if (_error != null)
              _ErrorView(
                text: _error!.text,
                onSaveWithoutAnalysis: () => _analyse(analyze: false),
                onTryAgain: _error!.canRetry
                    ? () => _analyse(analyze: true)
                    : null,
              )
            else
              switch (_step) {
                _Step.pose => _PoseStep(
                  pose: _pose,
                  notice: _notice,
                  onPose: (p) => setState(() => _pose = p),
                  onCamera: () => _pick(ImageSource.camera),
                  onLibrary: () => _pick(ImageSource.gallery),
                ),
                _Step.privacy => _PrivacyStep(
                  file: _source!,
                  blur: _blur,
                  notice: _notice,
                  busy: _busy,
                  progress: _progress,
                  onBlur: (v) => setState(() => _blur = v),
                  onContinue: () => _continue(baseline: baseline),
                ),
                _Step.consent => _ConsentStep(
                  body: CheckInSheet._consentBody,
                  onAnalyse: _acceptAndAnalyse,
                  onSaveWithoutAnalysis: () => _analyse(analyze: false),
                ),
                _Step.working => _ProcessingView(labels: _progress),
                _Step.result => _ResultStep(
                  recorded: _recorded!,
                  fallbackReason: _noAnalysisReason,
                  onDone: () => Navigator.of(context).pop(),
                ),
              },
          ],
        ),
      ),
    );
  }
}

class _AnalysisError {
  const _AnalysisError({required this.text, required this.canRetry});

  final String text;
  final bool canRetry;
}
