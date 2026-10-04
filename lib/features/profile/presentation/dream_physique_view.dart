import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrition_targets_view.dart';
import 'package:herculex/features/physique/presentation/save_physique_goal.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';

class DreamPhysiqueView extends ConsumerStatefulWidget {
  const DreamPhysiqueView({super.key});

  @override
  ConsumerState<DreamPhysiqueView> createState() => _DreamPhysiqueViewState();
}

class _DreamPhysiqueViewState extends ConsumerState<DreamPhysiqueView> {
  static const _maxComparisonPhotos = 4;
  static const _maxCurrentPhotos = 3;

  final List<File> _currentFiles = [];
  final List<File> _targetFiles = [];
  final _userNoteCtrl = TextEditingController();

  bool _analyzing = false;
  bool _privacyConsentGranted = false;
  bool _savingPriorities = false;
  String? _error;
  DreamPhysiqueAnalysisResult? _result;
  List<ProgrammingMusclePriority> _reviewedProgrammingPriorities = [];
  List<ProgressPhotoData> _savedPhotos = [];
  Map<String, double> _measurements = {};
  bool _loadingData = true;

  @override
  void initState() {
    super.initState();
    _loadUserContext();
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
          // Auto-select latest saved front photo if available
          if (photos.isNotEmpty) {
            final first = File(photos.first.filePath);
            if (first.existsSync()) {
              _currentFiles.add(first);
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
    _userNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCurrentPhoto(ImageSource source) async {
    Haptics.light();
    if (_currentFiles.length >= _maxCurrentPhotos ||
        _currentFiles.length + _targetFiles.length >= _maxComparisonPhotos) {
      setState(() {
        _error = 'You can use up to $_maxComparisonPhotos photos in total.';
      });
      return;
    }
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(type: AiScanContextType.dreamPhysique),
          );
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      await ref.read(pendingAiScanServiceProvider).clearPendingContext();
      if (picked != null && mounted) {
        setState(() {
          _currentFiles.add(File(picked.path));
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Error selecting image: $e');
    }
  }

  /// The gallery flow deliberately uses the system multi-picker. Comparing a
  /// front, side and back image together is more useful than making the user
  /// repeat the same action three times.
  Future<void> _pickCurrentPhotos() async {
    Haptics.light();
    final remainingSlots = [
      _maxComparisonPhotos - _currentFiles.length - _targetFiles.length,
      _maxCurrentPhotos - _currentFiles.length,
    ].reduce((a, b) => a < b ? a : b);
    if (remainingSlots <= 0) {
      setState(
        () =>
            _error = 'You can use up to $_maxComparisonPhotos photos in total.',
      );
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
      if (picked.isNotEmpty && mounted) {
        setState(() {
          final existingPaths = _currentFiles.map((file) => file.path).toSet();
          _currentFiles.addAll(
            picked
                .map((image) => File(image.path))
                .where((file) => !existingPaths.contains(file.path))
                .take(remainingSlots),
          );
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error selecting images: $e');
    }
  }

  Future<void> _pickTargetPhotos() async {
    Haptics.light();
    final remainingSlots =
        _maxComparisonPhotos - _currentFiles.length - _targetFiles.length;
    if (remainingSlots <= 0) {
      setState(() {
        _error = 'You can use up to $_maxComparisonPhotos photos in total.';
      });
      return;
    }
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(type: AiScanContextType.dreamPhysique),
          );
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      await ref.read(pendingAiScanServiceProvider).clearPendingContext();
      if (picked.isNotEmpty && mounted) {
        setState(() {
          final existingPaths = _targetFiles.map((file) => file.path).toSet();
          _targetFiles.addAll(
            picked
                .map((image) => File(image.path))
                .where((file) => !existingPaths.contains(file.path))
                .take(remainingSlots),
          );
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Error selecting target image: $e');
    }
  }

  void _toggleSavedPhoto(ProgressPhotoData photo) {
    Haptics.selection();
    final file = File(photo.filePath);
    final existingIndex = _currentFiles.indexWhere(
      (selected) => selected.path == file.path,
    );
    if (existingIndex < 0 &&
        (_currentFiles.length >= _maxCurrentPhotos ||
            _currentFiles.length + _targetFiles.length >=
                _maxComparisonPhotos)) {
      setState(() {
        _error = 'You can use up to $_maxComparisonPhotos photos in total.';
      });
      return;
    }
    setState(() {
      if (existingIndex >= 0) {
        _currentFiles.removeAt(existingIndex);
      } else {
        _currentFiles.add(file);
      }
      _error = null;
    });
  }

  Future<void> _startAnalysis() async {
    if (_currentFiles.isEmpty) {
      setState(
        () =>
            _error = 'Please add at least one photo of your current physique.',
      );
      return;
    }
    if (_targetFiles.isEmpty) {
      setState(
        () => _error = 'Please select a target photo of your dream physique.',
      );
      return;
    }
    if (!_privacyConsentGranted) {
      setState(
        () => _error =
            'Confirm the photo privacy notice before starting the analysis.',
      );
      return;
    }

    Haptics.medium();
    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final profile = ref.read(profileProvider).asData?.value;
      final service = ref.read(dreamPhysiqueServiceProvider);

      final result = await service.compareAndAnalyzePhysique(
        currentImages: _currentFiles,
        targetImages: _targetFiles,
        consentGranted: _privacyConsentGranted,
        profile: profile,
        measurements: _measurements,
        userNote: _userNoteCtrl.text.trim().isEmpty
            ? null
            : _userNoteCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _result = result;
        _reviewedProgrammingPriorities =
            result.programmingProfile?.musclePriorities.toList() ?? [];
      });
      Haptics.heavy();
      if (!mounted) return;
      final saved = await savePhysiqueGoal(
        context,
        ref,
        result: result,
        currentPhotos: _currentFiles,
        targetPhotoCount: _targetFiles.length,
      );
      if (saved) await _adoptTargetWeight(profile, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = _analysisErrorMessage(e);
      });
    }
  }

  /// The saved physique goal becomes the active one, so the profile's target
  /// weight follows it (current weight + the projected change).
  Future<void> _adoptTargetWeight(
    Profile? profile,
    DreamPhysiqueAnalysisResult result,
  ) async {
    final current = profile?.weightKg;
    if (profile == null || current == null) return;
    final target = double.parse(
      (current + result.weightChangeKg).toStringAsFixed(1),
    );
    if (target <= 0) return;
    await ref
        .read(localProfileRepositoryProvider)
        .save(profile.copyWith(targetWeightKg: target), syncToLog: false);
    await ref.read(goalWeightProvider.notifier).set(target);
  }

  String _analysisErrorMessage(Object error) {
    final message = error.toString().replaceAll('Exception: ', '');
    if (message.contains('Gemini API request failed (401)') ||
        message.contains('Gemini server authorization failed')) {
      return 'Herculex AI is not authorised on the server yet. Your photos are '
          'still selected; ask the administrator to replace the server '
          'GEMINI_API_KEY with a valid Google AI Studio API key, then try again.';
    }
    return message;
  }

  Future<void> _saveProgrammingPriorities(
    DreamPhysiqueProgrammingProfile profile,
  ) async {
    if (_savingPriorities || _reviewedProgrammingPriorities.isEmpty) return;
    setState(() => _savingPriorities = true);
    final db = ref.read(appDatabaseProvider);
    try {
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
      if (!mounted) return;
      Haptics.success();
      await _showSavedDialog(
        title: 'Priorities saved',
        message: 'Your reviewed priorities are ready to use in Smart programs.',
        icon: Icons.check_circle_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _savingPriorities = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).asData?.value;

    return HxScreenShell(
      title: 'Dream Physique AI',
      actions: [
        IconButton(
          key: const Key('open-dream-physique-history'),
          icon: const Icon(Icons.history_rounded),
          tooltip: 'History',
          onPressed: () => context.push(AppRoutes.dreamPhysiqueHistory),
        ),
      ],
      children: _loadingData
          ? const [
              Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ]
          : [
              if (_error != null) ...[
                _buildErrorCard(_error!),
                const SizedBox(height: 16),
              ],
              if (_result == null && !_analyzing) ...[
                // ── Setup Mode ──
                _buildSetupView(theme, profile),
              ] else if (_analyzing) ...[
                // ── Analyzing Loading State ──
                _buildLoadingView(theme),
              ] else if (_result != null) ...[
                // ── Rich Results View ──
                _buildResultsView(theme, profile),
              ],
            ],
    );
  }

  Widget _buildSetupView(ThemeData theme, Profile? profile) {
    final weight = profile?.weightKg;
    final height = profile?.heightCm;
    final macro = ref.watch(baselineTargetsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Intro Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.primary.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI comparison and goal roadmap',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select your current physique and role model photo for an accurate timeframe, muscle, and BF% projection.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── 1. Current Physique Section ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '1. Your current physique',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  onPressed: () => _pickCurrentPhoto(ImageSource.camera),
                  tooltip: 'Camera',
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  onPressed: _pickCurrentPhotos,
                  tooltip: 'Choose multiple from gallery',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Select up to 3 saved or gallery photos at once (front, side and back work best).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 12),

        // Selected current photos preview
        if (_currentFiles.isNotEmpty) ...[
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _currentFiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final file = _currentFiles[idx];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        file,
                        width: 95,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          Haptics.light();
                          setState(() => _currentFiles.removeAt(idx));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Saved progress photos carousel
        if (_savedPhotos.isNotEmpty) ...[
          Text(
            'Select from progress gallery:',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 95,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _savedPhotos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final photo = _savedPhotos[index];
                final file = File(photo.filePath);
                final isSelected = _currentFiles.any(
                  (f) => f.path == file.path,
                );

                return GestureDetector(
                  onTap: () => _toggleSavedPhoto(photo),
                  child: Container(
                    width: 75,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: file.existsSync()
                              ? Image.file(file, fit: BoxFit.cover)
                              : Container(
                                  color: AppColors.surfaceContainer,
                                  child: const Icon(Icons.image, size: 20),
                                ),
                        ),
                        if (isSelected)
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 2,
                          left: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              photo.pose.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 24),

        // ── 2. Target / Dream Physique Section ──
        Text(
          '2. Target Dream Physique',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Add one or more photos of the physique you want to achieve (from gallery or web).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 12),

        if (_targetFiles.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final file in _targetFiles)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        file,
                        width: 104,
                        height: 130,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => setState(() => _targetFiles.remove(file)),
                        child: const CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.black87,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        if (_targetFiles.isNotEmpty) const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickTargetPhotos,
          child: Container(
            height: _targetFiles.isEmpty ? 160 : 58,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _targetFiles.isNotEmpty
                    ? AppColors.primary
                    : AppColors.outlineVariant.withValues(alpha: 0.4),
                width: _targetFiles.isNotEmpty ? 2 : 1,
              ),
            ),
            child: _targetFiles.isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 40,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose target photos from gallery',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Supports JPG, PNG, WEBP',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined),
                      SizedBox(width: 8),
                      Text('Add more target photos'),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 20),

        // Current Profile Context summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statSnippet(
                'Weight',
                '${weight?.toStringAsFixed(1) ?? "--"} kg',
              ),
              _statSnippet(
                'Height',
                '${height?.toStringAsFixed(0) ?? "--"} cm',
              ),
              _statSnippet(
                'Daily Calories',
                macro != null ? '${macro.kcal} kcal' : '--',
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Explicit, per-analysis consent. This state is intentionally kept in
        // memory only and survives recoverable request failures.
        Material(
          color: AppColors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _privacyConsentGranted
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: const Key('dream-physique-privacy-consent'),
            value: _privacyConsentGranted,
            onChanged: (value) {
              Haptics.selection();
              setState(() {
                _privacyConsentGranted = value ?? false;
                _error = null;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
            title: const Text(
              'I agree to send these photos to Herculex AI (powered by Google Gemini)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'The images are sent only for this analysis. Herculex does not persist them on its servers. Google processes them to produce the result.',
                style: TextStyle(fontSize: 11, height: 1.35),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Trigger Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const Key('dream-physique-start-analysis'),
            onPressed: _privacyConsentGranted ? _startAnalysis : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text(
              'Compare and create plan with Herculex AI',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statSnippet(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildLoadingView(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Herculex AI is comparing physiques...',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Analyzing muscle mass, fat reduction, and calculating timeline',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsView(ThemeData theme, Profile? profile) {
    final r = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Side by Side Visual Card ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Current Photo Thumbnail
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Current',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child:
                              _currentFiles.isNotEmpty &&
                                  _currentFiles.first.existsSync()
                              ? Image.file(
                                  _currentFiles.first,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  height: 140,
                                  color: AppColors.surfaceContainerLowest,
                                  child: const Icon(Icons.person),
                                ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${r.currentEstimatedBf.toStringAsFixed(1)}% BF',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Center Transition
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            r.timeframeRange,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Target Photo Thumbnail
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Goal (Dream${_targetFiles.length > 1 ? ' • ${_targetFiles.length} photos' : ''})',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child:
                              _targetFiles.isNotEmpty &&
                                  _targetFiles.first.existsSync()
                              ? Image.file(
                                  _targetFiles.first,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  height: 140,
                                  color: AppColors.surfaceContainerLowest,
                                  child: const Icon(Icons.star),
                                ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${r.targetBfPercent.toStringAsFixed(1)}% BF',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── 4 Main Metric Cards Grid ──
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                title: 'Timeframe',
                value: r.timeframeRange,
                subtitle: 'Realistic estimate',
                icon: Icons.timer_outlined,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                title: 'Weight Change',
                value:
                    '${r.weightChangeKg >= 0 ? "+" : ""}${r.weightChangeKg.toStringAsFixed(1)} kg',
                subtitle: r.weightChangeKg <= 0 ? 'Net loss' : 'Net gain',
                icon: Icons.monitor_weight_outlined,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                title: 'Muscle Needed',
                value: '+${r.leanMuscleGainKg.toStringAsFixed(1)} kg',
                subtitle: 'Lean muscle mass',
                icon: Icons.fitness_center,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                title: 'Fat Loss',
                value: '-${r.fatLossKg.toStringAsFixed(1)} kg',
                subtitle: 'Target BF: ${r.targetBfPercent.toStringAsFixed(0)}%',
                icon: Icons.local_fire_department_outlined,
                color: Colors.deepOrangeAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Reviewable Programming Profile ──
        if (r.programmingProfile != null)
          _buildProgrammingProfileReview(theme, r.programmingProfile!)
        else ...[
          Row(
            children: [
              Icon(
                Icons.format_list_bulleted,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Aesthetic Muscle Group Focus',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Review these legacy analysis priorities. No program has been changed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final p in r.musclePriorities) ...[
            _MusclePriorityCard(priority: p),
            const SizedBox(height: 8),
          ],
        ],

        const SizedBox(height: 20),

        _SectionCard(
          title: 'Detected target aesthetic',
          icon: Icons.auto_awesome_outlined,
          content: r.targetAestheticStyle,
          theme: theme,
        ),
        const SizedBox(height: 12),

        // ── Nutrition Strategy Card ──
        _SectionCard(
          title: 'Nutrition Strategy',
          icon: Icons.restaurant_outlined,
          content: r.nutritionStrategy,
          theme: theme,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('edit-nutrition-targets-from-dream-physique'),
            onPressed: _openNutritionTargets,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Update nutrition targets'),
          ),
        ),
        const SizedBox(height: 12),

        // ── Training Strategy Card ──
        _SectionCard(
          title: 'Training Strategy',
          icon: Icons.sports_gymnastics_outlined,
          content: r.trainingAdvice,
          theme: theme,
        ),
        const SizedBox(height: 12),

        // ── Overall Assessment Card ──
        _SectionCard(
          title: 'Overall Assessment',
          icon: Icons.psychology_outlined,
          content: r.overallAssessment,
          theme: theme,
        ),

        const SizedBox(height: 28),

        // Action Buttons
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () {
              Haptics.selection();
              setState(() {
                _result = null;
                _reviewedProgrammingPriorities = [];
                _privacyConsentGranted = false;
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('New analysis / Change photos'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
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
      await _showSavedDialog(
        title: 'Nutrition targets updated',
        message:
            'Your daily calories and macros are now active for nutrition tracking.',
        icon: Icons.restaurant_menu_rounded,
      );
    }
  }

  Future<void> _showSavedDialog({
    required String title,
    required String message,
    required IconData icon,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: AppColors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 32),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgrammingProfileReview(
    ThemeData theme,
    DreamPhysiqueProgrammingProfile profile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.fact_check_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review before programming',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'This is an editable analysis only. Herculex has not changed or activated any training program.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.tune, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Programming priorities',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              'AI confidence ${(profile.overallConfidence * 100).round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Change a priority or remove it if the visual comparison does not match your intent.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 12),
        if (_reviewedProgrammingPriorities.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'No AI priorities selected. You can run a new analysis or choose priorities manually later.',
            ),
          )
        else
          for (
            var index = 0;
            index < _reviewedProgrammingPriorities.length;
            index++
          ) ...[
            _ProgrammingPriorityReviewCard(
              key: ValueKey(
                'programming-priority-${_reviewedProgrammingPriorities[index].muscleId}',
              ),
              priority: _reviewedProgrammingPriorities[index],
              onPriorityChanged: (value) {
                setState(() {
                  _reviewedProgrammingPriorities[index] =
                      _reviewedProgrammingPriorities[index].copyWith(
                        priority: value,
                      );
                });
              },
              onRemove: () {
                Haptics.light();
                setState(() => _reviewedProgrammingPriorities.removeAt(index));
              },
            ),
            const SizedBox(height: 8),
          ],
        if (profile.uncertainties.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionCard(
            title: 'Analysis limitations',
            icon: Icons.info_outline,
            content: profile.uncertainties.map((item) => '• $item').join('\n'),
            theme: theme,
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('confirm-dream-physique-programming-profile'),
            onPressed:
                _reviewedProgrammingPriorities.isEmpty || _savingPriorities
                ? null
                : () => _saveProgrammingPriorities(profile),
            icon: _savingPriorities
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(
              _savingPriorities
                  ? 'Saving priorities…'
                  : 'Save priorities & continue',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade400),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgrammingPriorityReviewCard extends StatelessWidget {
  final ProgrammingMusclePriority priority;
  final ValueChanged<ProgrammingPriorityLevel> onPriorityChanged;
  final VoidCallback onRemove;

  const _ProgrammingPriorityReviewCard({
    super.key,
    required this.priority,
    required this.onPriorityChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _muscleLabel(priority.muscleId),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(priority.confidence * 100).round()}% confidence',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<ProgrammingPriorityLevel>(
                  value: priority.priority,
                  borderRadius: BorderRadius.circular(12),
                  items: ProgrammingPriorityLevel.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_priorityLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onPriorityChanged(value);
                  },
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove priority',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            priority.rationale,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
          if (priority.uncertainties.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              priority.uncertainties.join(' '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _priorityLabel(ProgrammingPriorityLevel value) {
    return switch (value) {
      ProgrammingPriorityLevel.high => 'High',
      ProgrammingPriorityLevel.medium => 'Medium',
      ProgrammingPriorityLevel.maintenance => 'Maintenance',
    };
  }

  static String _muscleLabel(String muscleId) {
    const labels = <String, String>{
      'chest': 'Chest',
      'back': 'Back',
      'lats': 'Lats',
      'traps': 'Traps',
      'front_delts': 'Front delts',
      'side_delts': 'Side delts',
      'rear_delts': 'Rear delts',
      'biceps': 'Biceps',
      'triceps': 'Triceps',
      'forearms': 'Forearms',
      'abs': 'Abs',
      'obliques': 'Obliques',
      'neck': 'Neck',
      'quads': 'Quads',
      'hamstrings': 'Hamstrings',
      'glutes': 'Glutes',
      'calves': 'Calves',
      'adductors': 'Adductors',
      'abductors': 'Abductors',
    };
    return labels[muscleId] ?? muscleId;
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary.withValues(alpha: 0.8),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _MusclePriorityCard extends StatelessWidget {
  final MusclePriority priority;

  const _MusclePriorityCard({required this.priority});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedPriority = priority.priority.toLowerCase();
    final isHigh = normalizedPriority == 'high';
    final isMaintenance = normalizedPriority == 'maintenance';
    final badgeColor = isHigh
        ? Colors.redAccent
        : isMaintenance
        ? Colors.blueAccent
        : Colors.orangeAccent;
    final badgeText = isHigh
        ? 'HIGH PRIORITY'
        : isMaintenance
        ? 'MAINTENANCE'
        : 'MEDIUM PRIORITY';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHigh
              ? badgeColor.withValues(alpha: 0.4)
              : AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  priority.group,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            priority.focus,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String content;
  final ThemeData theme;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.content,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
