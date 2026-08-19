import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
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
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null && mounted) {
        setState(() {
          _currentFiles.add(File(picked.path));
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Napaka pri izbiri slike: $e');
    }
  }

  Future<void> _pickTargetPhoto() async {
    Haptics.light();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() {
          _targetFile = File(picked.path);
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Napaka pri izbiri ciljne slike: $e');
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
      setState(() => _error = 'Prosimo, dodajte vsaj eno sliko svoje trenutne postave.');
      return;
    }
    if (_targetFile == null) {
      setState(() => _error = 'Prosimo, izberite ciljno sliko želene sanjske postave.');
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
        userNote: _userNoteCtrl.text.trim().isEmpty ? null : _userNoteCtrl.text.trim(),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dream Physique AI'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
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
            ),
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
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI primerjava in načrt do cilja',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Izberite svojo trenutno postavo in sliko vzornika za natančen izračun časovnega okvirja, mišic in BF%.',
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
              '1. Vaša trenutna postava',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  onPressed: () => _pickCurrentPhoto(ImageSource.camera),
                  tooltip: 'Kamera',
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  onPressed: () => _pickCurrentPhoto(ImageSource.gallery),
                  tooltip: 'Galerija',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Izberite med shranjenimi slikami ali naložite novo.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
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
                          child: const Icon(Icons.close,
                              size: 12, color: Colors.white),
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
            'Izbira iz galerije napredka:',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _savedPhotos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final photo = _savedPhotos[idx];
                final file = File(photo.filePath);
                final isSelected =
                    _currentFiles.any((f) => f.path == file.path);

                return GestureDetector(
                  onTap: () => _toggleSavedPhoto(photo),
                  child: Container(
                    width: 70,
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
                                  child: const Icon(Icons.broken_image, size: 20),
                                ),
                        ),
                        if (isSelected)
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(Icons.check_circle,
                                  color: Colors.white, size: 20),
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
          '2. Ciljna sanjska postava (Dream Physique)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Naložite sliko postave, ki jo želite doseči (iz galerije ali spleta).',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
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
                              horizontal: 10, vertical: 4),
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
                                'Zamenjaj sliko',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11),
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
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 40, color: AppColors.primary),
                      const SizedBox(height: 8),
                      Text(
                        'Izberi ciljno fotografijo iz galerije',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Podpira JPG, PNG, WEBP',
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
          'Želen stil estetike',
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
              _statSnippet('Teža', '${weight?.toStringAsFixed(1) ?? "--"} kg'),
              _statSnippet('Višina', '${height?.toStringAsFixed(0) ?? "--"} cm'),
              _statSnippet('Dnevne kalorije',
                  macro != null ? '${macro.kcal} kcal' : '--'),
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
              'Primerjaj in ustvari načrt z Gemini AI',
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
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
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
              'Gemini AI primerja postavi...',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Analiza mišične mase, zmanjšanja telesne maščobe in izračun časovnega okvirja',
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
                          'Trenutno',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _currentFiles.isNotEmpty &&
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
                          child: Icon(Icons.arrow_forward_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
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
                          'Cilj (Dream)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _targetFile != null &&
                                  _targetFile!.existsSync()
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
                title: 'Časovni okvir',
                value: r.timeframeRange,
                subtitle: 'Realna ocena',
                icon: Icons.timer_outlined,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                title: 'Sprememba teže',
                value:
                    '${r.weightChangeKg >= 0 ? "+" : ""}${r.weightChangeKg.toStringAsFixed(1)} kg',
                subtitle: r.weightChangeKg <= 0 ? 'Neto znižanje' : 'Neto prirast',
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
                title: 'Potrebne mišice',
                value: '+${r.leanMuscleGainKg.toStringAsFixed(1)} kg',
                subtitle: 'Pusta mišična masa',
                icon: Icons.fitness_center,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                title: 'Izguba maščobe',
                value: '-${r.fatLossKg.toStringAsFixed(1)} kg',
                subtitle: 'Ciljni BF: ${r.targetBfPercent.toStringAsFixed(0)}%',
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
            Icon(Icons.format_list_bulleted,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Fokus mišičnih skupin za estetiko',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Za dosego ciljne simetrije dajte prednost tem mišicam:',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
        ),
        const SizedBox(height: 12),

        for (final p in r.musclePriorities) ...[
          _MusclePriorityCard(priority: p),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 20),

        // ── Nutrition Strategy Card ──
        _SectionCard(
          title: 'Prehranska strategija',
          icon: Icons.restaurant_outlined,
          content: r.nutritionStrategy,
          theme: theme,
        ),
        const SizedBox(height: 12),

        // ── Training Strategy Card ──
        _SectionCard(
          title: 'Strategija treninga',
          icon: Icons.sports_gymnastics_outlined,
          content: r.trainingAdvice,
          theme: theme,
        ),
        const SizedBox(height: 12),

        // ── Overall Assessment Card ──
        _SectionCard(
          title: 'Zaključna ocena',
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
            label: const Text('Nova analiza / Spremeni slike'),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
