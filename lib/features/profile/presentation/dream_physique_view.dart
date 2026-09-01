import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../services/pending_ai_scan_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../ui/ui.dart';
import '../../nutrition/domain/macro_targets.dart';
import '../data/dream_physique_service.dart';
import '../domain/profile.dart';

class DreamPhysiqueView extends ConsumerStatefulWidget {
  const DreamPhysiqueView({super.key});

  @override
  ConsumerState<DreamPhysiqueView> createState() => _DreamPhysiqueViewState();
}

class _DreamPhysiqueViewState extends ConsumerState<DreamPhysiqueView> {
  final List<File> _currentFiles = [];
  File? _targetFile;
  String _selectedGoalStyle = 'Lean & Aesthetic';
  final _userNoteCtrl = TextEditingController();

  bool _analyzing = false;
  String? _error;
  DreamPhysiqueAnalysisResult? _result;
  List<ProgressPhotoData> _savedPhotos = [];
  Map<String, double> _measurements = {};
  bool _loadingData = true;

  static const _goalStyles = [
    'Lean & Aesthetic',
    'Athletic / V-Taper',
    'Classic Muscular',
    'Defined Cut',
  ];

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

  Future<void> _pickTargetPhoto() async {
    Haptics.light();
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(type: AiScanContextType.dreamPhysique),
          );
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      await ref.read(pendingAiScanServiceProvider).clearPendingContext();
      if (picked != null && mounted) {
        setState(() {
          _targetFile = File(picked.path);
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
    setState(() {
      final idx = _currentFiles.indexWhere((f) => f.path == file.path);
      if (idx >= 0) {
        _currentFiles.removeAt(idx);
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
    if (_targetFile == null) {
      setState(
        () => _error = 'Please select a target photo of your dream physique.',
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
        targetImage: _targetFile!,
        profile: profile,
        measurements: _measurements,
        targetGoalStyle: _selectedGoalStyle,
        userNote: _userNoteCtrl.text.trim().isEmpty
            ? null
            : _userNoteCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _result = result;
      });
      Haptics.heavy();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).asData?.value;

    return HxScreenShell(
      title: 'Dream Physique AI',
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
    final macro = profile != null ? MacroTargets.fromProfile(profile) : null;

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
                  onPressed: () => _pickCurrentPhoto(ImageSource.gallery),
                  tooltip: 'Gallery',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Select from saved photos or upload a new one.',
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
          'Upload a photo of the physique you want to achieve (from gallery or web).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 12),

        GestureDetector(
          onTap: _pickTargetPhoto,
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _targetFile != null
                    ? AppColors.primary
                    : AppColors.outlineVariant.withValues(alpha: 0.4),
                width: _targetFile != null ? 2 : 1,
              ),
            ),
            child: _targetFile != null && _targetFile!.existsSync()
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.file(_targetFile!, fit: BoxFit.cover),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Change photo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 40,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose target photo from gallery',
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
                  ),
          ),
        ),

        const SizedBox(height: 24),

        // ── 3. Target Aesthetic Style ──
        Text(
          'Desired aesthetic style',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _goalStyles.map((style) {
            final selected = _selectedGoalStyle == style;
            return ChoiceChip(
              label: Text(style),
              selected: selected,
              onSelected: (_) {
                Haptics.selection();
                setState(() => _selectedGoalStyle = style);
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              side: BorderSide(
                color: selected
                    ? AppColors.primary
                    : AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            );
          }).toList(),
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

        const SizedBox(height: 28),

        // Trigger Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _startAnalysis,
            icon: const Icon(Icons.auto_awesome),
            label: const Text(
              'Compare and create plan with Gemini AI',
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
              'Gemini AI is comparing physiques...',
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
                          'Goal (Dream)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child:
                              _targetFile != null && _targetFile!.existsSync()
                              ? Image.file(
                                  _targetFile!,
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

        // ── Muscle Priority Matrix ──
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
          'To achieve target symmetry, prioritize these muscles:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 12),

        for (final p in r.musclePriorities) ...[
          _MusclePriorityCard(priority: p),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 20),

        // ── Nutrition Strategy Card ──
        _SectionCard(
          title: 'Nutrition Strategy',
          icon: Icons.restaurant_outlined,
          content: r.nutritionStrategy,
          theme: theme,
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
              setState(() => _result = null);
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
    final isHigh = priority.priority.toLowerCase() == 'high';
    final badgeColor = isHigh ? Colors.redAccent : Colors.orangeAccent;
    final badgeText = isHigh ? 'VISOKA PRIORITETA' : 'SREDNJA PRIORITETA';

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
