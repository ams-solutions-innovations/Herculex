import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/core/storage/local_photo_store.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrition_targets_view.dart';
import 'package:herculex/features/physique/domain/physique_direction.dart';
import 'package:herculex/features/physique/presentation/save_physique_goal.dart';
import 'package:herculex/features/physique/presentation/widgets/phone_only_notice.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

part 'dream_physique_view/_parts.part.dart';
part 'dream_physique_view/_setup.part.dart';
part 'dream_physique_view/_analyzing.part.dart';
part 'dream_physique_view/_results.part.dart';

/// Dream Physique: compare today's photos with a goal photo, review the AI's
/// timeframe and muscle priorities, then save them as a goal.
///
/// Three states on one screen — setup, analyzing and results — laid out after
/// the "Dream Physique AI" Claude Design prototype.
class DreamPhysiqueView extends ConsumerStatefulWidget {
  const DreamPhysiqueView({super.key});

  @override
  ConsumerState<DreamPhysiqueView> createState() => _DreamPhysiqueViewState();
}

class _DreamPhysiqueViewState extends ConsumerState<DreamPhysiqueView> {
  /// Front, side and back. Slots stay put when one is cleared, so a pose label
  /// never moves to a different photo.
  static const _poses = ['front', 'side', 'back'];

  static const _intentOptions = [
    'Shoulders',
    'Abs',
    'Arms',
    'Back',
    'Legs',
    'Leaner overall',
  ];

  /// The analysis is a single request; these only pace the waiting screen.
  static const _analysisSteps = [
    'Reading your photos',
    'Estimating body-fat range',
    'Mapping muscle differences',
    'Building your timeline',
  ];

  final List<File?> _poseFiles = List.filled(_poses.length, null);
  File? _targetFile;
  final Set<String> _intents = {};

  bool _analyzing = false;
  int _analysisStep = 0;
  Timer? _stepTimer;

  /// Bumped by Cancel, so a response that arrives afterwards is dropped.
  int _analysisRun = 0;

  bool _privacyConsentGranted = false;
  bool _saving = false;
  bool _saved = false;
  bool _assessmentOpen = false;
  String? _error;
  DreamPhysiqueAnalysisResult? _result;
  List<ProgrammingMusclePriority> _reviewedProgrammingPriorities = [];
  List<ProgressPhotoData> _savedPhotos = [];
  Map<String, double> _measurements = {};
  bool _loadingData = true;

  List<File> get _currentFiles => _poseFiles.whereType<File>().toList();

  bool get _readyToAnalyze =>
      _currentFiles.isNotEmpty && _targetFile != null && _privacyConsentGranted;

  @override
  void initState() {
    super.initState();
    // Saved photos are files in the phone's sandbox; there is nothing to load
    // in a browser, where the photo steps are replaced by a notice.
    if (ref.read(platformCapabilitiesProvider).hasFileSystem) {
      _loadUserContext();
    } else {
      _loadingData = false;
    }
  }

  Future<void> _loadUserContext() async {
    try {
      final repo = ref.read(measurementsRepositoryProvider);
      final photos = await repo.getRecentPhotos(limit: 10);
      final meas = await repo.getLatestMeasurements();
      if (mounted) {
        setState(() {
          _savedPhotos = photos;
          _measurements = meas;
          _loadingData = false;
          // Pre-fill with the latest saved photo, in its own pose slot.
          if (photos.isNotEmpty) {
            final first = LocalPhotoStore.resolveSync(photos.first.filePath);
            if (first.existsSync()) {
              _poseFiles[_slotForPose(photos.first.pose)] = first;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    super.dispose();
  }

  int _slotForPose(String pose) {
    final index = _poses.indexOf(pose.toLowerCase());
    return index < 0 ? 0 : index;
  }

  int? get _firstEmptySlot {
    final index = _poseFiles.indexWhere((file) => file == null);
    return index < 0 ? null : index;
  }

  Future<File?> _pickImage(ImageSource source) async {
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(type: AiScanContextType.dreamPhysique),
          );
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      await ref.read(pendingAiScanServiceProvider).clearPendingContext();
      return picked == null ? null : File(picked.path);
    } catch (e) {
      if (mounted) setState(() => _error = 'Error selecting image: $e');
      return null;
    }
  }

  Future<void> _pickIntoSlot(int slot, ImageSource source) async {
    Haptics.light();
    final file = await _pickImage(source);
    if (file == null || !mounted) return;
    setState(() {
      _poseFiles[slot] = file;
      _error = null;
    });
  }

  Future<void> _pickWithCamera() async {
    final slot = _firstEmptySlot;
    if (slot == null) {
      setState(() => _error = 'All three slots are filled. Remove one first.');
      return;
    }
    await _pickIntoSlot(slot, ImageSource.camera);
  }

  /// Fills the empty slots in one go; the system multi-picker beats making
  /// the user repeat the same action three times.
  Future<void> _pickFromLibrary() async {
    Haptics.light();
    final empty = [
      for (var i = 0; i < _poseFiles.length; i++)
        if (_poseFiles[i] == null) i,
    ];
    if (empty.isEmpty) {
      setState(() => _error = 'All three slots are filled. Remove one first.');
      return;
    }
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(type: AiScanContextType.dreamPhysique),
          );
      final picked = await ImagePicker().pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      await ref.read(pendingAiScanServiceProvider).clearPendingContext();
      if (picked.isEmpty || !mounted) return;
      setState(() {
        for (var i = 0; i < picked.length && i < empty.length; i++) {
          _poseFiles[empty[i]] = File(picked[i].path);
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error selecting images: $e');
    }
  }

  Future<void> _pickTargetPhoto() async {
    Haptics.light();
    final file = await _pickImage(ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _targetFile = file;
      _error = null;
    });
  }

  void _clearSlot(int slot) {
    Haptics.light();
    setState(() => _poseFiles[slot] = null);
  }

  void _clearTarget() {
    Haptics.light();
    setState(() => _targetFile = null);
  }

  void _useSavedPhoto(ProgressPhotoData photo) {
    Haptics.selection();
    final file = LocalPhotoStore.resolveSync(photo.filePath);
    setState(() {
      final existing = _poseFiles.indexWhere((f) => f?.path == file.path);
      if (existing >= 0) {
        _poseFiles[existing] = null;
      } else {
        final own = _slotForPose(photo.pose);
        final slot = _poseFiles[own] == null ? own : (_firstEmptySlot ?? own);
        _poseFiles[slot] = file;
      }
      _error = null;
    });
  }

  void _toggleIntent(String intent) {
    Haptics.selection();
    setState(() {
      if (!_intents.remove(intent)) _intents.add(intent);
    });
  }

  void _toggleConsent() {
    Haptics.selection();
    setState(() {
      _privacyConsentGranted = !_privacyConsentGranted;
      _error = null;
    });
  }

  String? get _userNote => _intents.isEmpty
      ? null
      : 'What matters most to me: '
            '${_intentOptions.where(_intents.contains).join(', ')}.';

  Future<void> _startAnalysis() async {
    if (!_readyToAnalyze) return;

    Haptics.medium();
    final run = ++_analysisRun;
    final targetFile = _targetFile!;
    final currentFiles = _currentFiles;
    setState(() {
      _analyzing = true;
      _analysisStep = 0;
      _error = null;
    });
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      // Holds on the last step until the response arrives.
      if (_analysisStep < _analysisSteps.length - 1) {
        setState(() => _analysisStep++);
      }
    });

    try {
      final profile = ref.read(profileProvider).asData?.value;
      final service = ref.read(dreamPhysiqueServiceProvider);

      final result = await service.compareAndAnalyzePhysique(
        currentImages: currentFiles,
        targetImages: [targetFile],
        consentGranted: _privacyConsentGranted,
        profile: profile,
        measurements: _measurements,
        userNote: _userNote,
      );

      if (!mounted || run != _analysisRun) return;
      _stepTimer?.cancel();
      setState(() {
        _analyzing = false;
        _result = result;
        _saved = false;
        _assessmentOpen = false;
        _reviewedProgrammingPriorities =
            result.programmingProfile?.musclePriorities.toList() ?? [];
      });
      Haptics.heavy();
    } catch (e) {
      if (!mounted || run != _analysisRun) return;
      _stepTimer?.cancel();
      setState(() {
        _analyzing = false;
        _error = describeDreamPhysiqueError(e);
      });
    }
  }

  void _cancelAnalysis() {
    Haptics.selection();
    _analysisRun++;
    _stepTimer?.cancel();
    setState(() => _analyzing = false);
  }

  void _startOver() {
    Haptics.selection();
    setState(() {
      _result = null;
      _reviewedProgrammingPriorities = [];
      _privacyConsentGranted = false;
      _saved = false;
    });
  }

  void _setPriority(int index, ProgrammingPriorityLevel level) {
    Haptics.selection();
    setState(() {
      _reviewedProgrammingPriorities[index] =
          _reviewedProgrammingPriorities[index].copyWith(priority: level);
      _saved = false;
    });
  }

  void _toggleAssessment() {
    Haptics.selection();
    setState(() => _assessmentOpen = !_assessmentOpen);
  }

  /// Saves the analysis as the active goal (with its photo dialogs), then the
  /// reviewed priorities, then opens the goal's progress and roadmap.
  Future<void> _saveGoalAndPriorities() async {
    final result = _result;
    if (_saving || _saved || result == null || _targetFile == null) return;
    setState(() => _saving = true);
    try {
      final goalSaved = await savePhysiqueGoal(
        context,
        ref,
        result: result,
        currentPhotos: _currentFiles,
        targetPhotoCount: 1,
        targetPhoto: _targetFile,
      );
      if (!goalSaved || !mounted) return;
      final profile = result.programmingProfile;
      if (profile != null && _reviewedProgrammingPriorities.isNotEmpty) {
        await _persistProgrammingPriorities(profile);
      }
      if (!mounted) return;
      Haptics.success();
      setState(() => _saved = true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) context.pushReplacement(AppPaths.dreamPhysiqueProgress());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persistProgrammingPriorities(
    DreamPhysiqueProgrammingProfile profile,
  ) async {
    final db = ref.read(appDatabaseProvider);
    final payload = {
      'schemaVersion': profile.schemaVersion,
      'overallConfidence': profile.overallConfidence,
      'musclePriorities': [
        for (final priority in _reviewedProgrammingPriorities)
          {
            'muscleId': priority.muscleId,
            'priority': priority.priority.wireValue,
            'confidence': priority.confidence,
            'rationale': priority.rationale,
            'uncertainties': priority.uncertainties,
          },
      ],
      'uncertainties': profile.uncertainties,
    };
    await db.transaction(() async {
      await db
          .update(db.physiqueProgrammingProfiles)
          .write(
            const PhysiqueProgrammingProfilesCompanion(active: Value(false)),
          );
      await db
          .into(db.physiqueProgrammingProfiles)
          .insert(
            PhysiqueProgrammingProfilesCompanion.insert(
              prioritiesJson: jsonEncode(payload),
              source: const Value('gemini_confirmed'),
              modelVersion: Value('schema-${profile.schemaVersion}'),
            ),
          );
    });
  }

  Future<void> _openNutritionTargets() async {
    Haptics.selection();
    final customTargets = ref.read(nutritionTargetsProvider).asData?.value;
    NutritionTargetData? initialTarget;
    if (customTargets != null) {
      for (final target in customTargets) {
        if (target.appliesTo == 'global') {
          initialTarget = target;
          break;
        }
      }
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TargetEditorView(initialTarget: initialTarget),
      ),
    );
    if (saved == true && mounted) {
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nutrition targets updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).asData?.value;

    if (!ref.watch(platformCapabilitiesProvider).hasFileSystem) {
      return const HxScreenShell(
        title: 'Dream Physique',
        titleIcon: Icons.auto_awesome,
        children: [PhysiquePhoneOnlyNotice()],
      );
    }

    final result = _result;
    final Widget? pinned = _loadingData || _analyzing
        ? null
        : result == null
        ? _buildAnalyzeButton()
        : _buildSaveButton();

    return HxScreenShell(
      title: 'Dream Physique',
      titleIcon: Icons.auto_awesome,
      actions: [
        IconButton(
          key: const Key('open-dream-physique-history'),
          icon: const Icon(Icons.history_rounded),
          tooltip: 'History',
          onPressed: () => context.push(AppRoutes.dreamPhysiqueHistory),
        ),
      ],
      pinnedBottom: pinned,
      children: _loadingData
          ? const [
              Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ]
          : [
              if (_error != null) ...[
                _DpErrorCard(message: _error!),
                const SizedBox(height: HxSpace.x4),
              ],
              if (_analyzing)
                _buildAnalyzingView()
              else if (result != null)
                _buildResultsView(result, profile)
              else
                _buildSetupView(),
            ],
    );
  }
}
