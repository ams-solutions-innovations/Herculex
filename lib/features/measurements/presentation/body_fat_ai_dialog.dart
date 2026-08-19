import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../profile/domain/profile.dart';
import '../data/body_fat_ai_service.dart';

class BodyFatAiDialog extends ConsumerStatefulWidget {
  const BodyFatAiDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BodyFatAiDialog(),
    );
  }

  @override
  ConsumerState<BodyFatAiDialog> createState() => _BodyFatAiDialogState();
}

class _BodyFatAiDialogState extends ConsumerState<BodyFatAiDialog> {
  final _noteCtrl = TextEditingController();
  final List<File> _selectedFiles = [];

  bool _analyzing = false;
  bool _saving = false;
  String? _error;
  BodyFatAiResult? _result;
  Map<String, double> _latestMeasurements = {};
  List<ProgressPhotoData> _savedPhotos = [];
  bool _loadingContext = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final repo = ref.read(measurementsRepositoryProvider);
      final measurements = await repo.getLatestMeasurements();
      final photos = await repo.getRecentPhotos(limit: 12);
      if (mounted) {
        setState(() {
          _latestMeasurements = measurements;
          _savedPhotos = photos;
          _loadingContext = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingContext = false);
      }
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFromGalleryOrCamera(ImageSource source) async {
    Haptics.light();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null && mounted) {
        setState(() {
          _selectedFiles.add(File(picked.path));
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Napaka pri izbiri slike: $e');
    }
  }

  void _toggleSavedPhoto(ProgressPhotoData photo) {
    Haptics.selection();
    final file = File(photo.filePath);
    setState(() {
      final existingIndex =
          _selectedFiles.indexWhere((f) => f.path == file.path);
      if (existingIndex >= 0) {
        _selectedFiles.removeAt(existingIndex);
      } else {
        _selectedFiles.add(file);
      }
      _error = null;
    });
  }

  Future<void> _runAnalysis() async {
    Haptics.medium();
    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final profile = ref.read(profileProvider).asData?.value;
      final aiService = ref.read(bodyFatAiServiceProvider);

      final result = await aiService.estimateBodyFat(
        imageFiles: _selectedFiles,
        profile: profile,
        measurements: _latestMeasurements,
        userNote: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
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

  Future<void> _saveToMeasurements() async {
    if (_result == null) return;
    Haptics.medium();
    setState(() => _saving = true);

    try {
      final repo = ref.read(measurementsRepositoryProvider);
      final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());

      await repo.logMeasurement(
        dateIso: todayIso,
        metric: 'body_fat',
        value: _result!.estimatedBfPercent,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Telesna maščoba (${_result!.estimatedBfPercent.toStringAsFixed(1)} %) shranjena!',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Napaka pri shranjevanju: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).asData?.value;
    final mediaQuery = MediaQuery.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, scrollController) => Container(
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.auto_awesome,
                        size: 22, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gemini AI Ocena telesne maščobe',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Multimodalna analiza fotografij in meritev',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  if (_loadingContext)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else ...[
                    // ── Biometrics Context Card ──
                    _buildBiometricContext(profile),
                    const SizedBox(height: 16),

                    if (_error != null) ...[
                      _buildErrorBox(_error!),
                      const SizedBox(height: 16),
                    ],

                    if (_result == null && !_analyzing) ...[
                      // ── Photo Selection Section ──
                      _buildPhotoSection(theme),
                      const SizedBox(height: 20),

                      // ── Note Field ──
                      Text(
                        'Opomba o počutju / sliki (neobvezno)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Npr. zjutraj na tešče, dobra osvetlitev...',
                          filled: true,
                          fillColor: AppColors.surfaceContainer,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Trigger Button ──
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _runAnalysis,
                          icon: const Icon(Icons.auto_awesome),
                          label: Text(
                            _selectedFiles.isNotEmpty
                                ? 'Analiziraj (${_selectedFiles.length} slik) z Gemini AI'
                                : 'Izračunaj oceno po meritvah & profilu',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ] else if (_analyzing) ...[
                      const SizedBox(height: 48),
                      Center(
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 20),
                            Text(
                              'Gemini AI analizira kompozicijo telesa...',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Ocena vaskularnosti, definicije mišic in porazdelitve maščobe',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                    ] else if (_result != null) ...[
                      // ── Result Display ──
                      _buildResultCards(theme, profile),
                      const SizedBox(height: 24),

                      // ── Save Button ──
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _saveToMeasurements,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(
                            _saving ? 'Shranjevanje...' : 'Shrani v Body Measurements',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _result = null),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Ponovna analiza'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricContext(Profile? profile) {
    final theme = Theme.of(context);
    final weight = profile?.weightKg;
    final height = profile?.heightCm;
    final isMale = profile?.sex != BiologicalSex.female;
    final waist = _latestMeasurements['waist'];
    final neck = _latestMeasurements['neck'];

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
            children: [
              Icon(Icons.person_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Biometrični profil',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _contextChip(
                'Spol',
                isMale ? 'Moški' : 'Ženska',
                Icons.wc,
              ),
              if (weight != null)
                _contextChip('Teža', '${weight.toStringAsFixed(1)} kg',
                    Icons.monitor_weight_outlined),
              if (height != null)
                _contextChip('Višina', '${height.toStringAsFixed(0)} cm',
                    Icons.height),
              if (waist != null)
                _contextChip('Pas', '${waist.toStringAsFixed(1)} cm',
                    Icons.straighten),
              if (neck != null)
                _contextChip('Vrat', '${neck.toStringAsFixed(1)} cm',
                    Icons.straighten),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contextChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.secondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Fotografije telesa (${_selectedFiles.length} izbranih)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  tooltip: 'Kamera',
                  onPressed: () =>
                      _pickFromGalleryOrCamera(ImageSource.camera),
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  tooltip: 'Galerija',
                  onPressed: () =>
                      _pickFromGalleryOrCamera(ImageSource.gallery),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Za najbolj natančno oceno izberite fotografijo od spredaj, s strani ali hrbta.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 12),

        // Selected photos preview
        if (_selectedFiles.isNotEmpty) ...[
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedFiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final file = _selectedFiles[idx];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        file,
                        width: 90,
                        height: 110,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          Haptics.light();
                          setState(() => _selectedFiles.removeAt(idx));
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
          const SizedBox(height: 16),
        ],

        // Saved progress photos picker (if any available)
        if (_savedPhotos.isNotEmpty) ...[
          Text(
            'Izberi iz shranjenih fotografij napredka:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w600,
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
                final isSelected =
                    _selectedFiles.any((f) => f.path == file.path);

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
                              child: Icon(Icons.check_circle,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        Positioned(
                          bottom: 2,
                          left: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
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
                                  fontWeight: FontWeight.bold),
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
      ],
    );
  }

  Widget _buildResultCards(ThemeData theme, Profile? profile) {
    final r = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main BF% Gauge Card ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.18),
                AppColors.primary.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          r.isAiGenerated
                              ? 'Gemini Multimodalna ocena'
                              : 'Biometrični izračun',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (r.confidence != null)
                    Text(
                      'Zanesljivost: ${(r.confidence! * 100).toStringAsFixed(0)} %',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${r.estimatedBfPercent.toStringAsFixed(1)} %',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: -1,
                ),
              ),
              if (r.bfRangeMin != null && r.bfRangeMax != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Razpon: ${r.bfRangeMin!.toStringAsFixed(1)} % - ${r.bfRangeMax!.toStringAsFixed(1)} %',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Lean vs Fat Mass Row ──
        if (r.leanMassKg != null && r.fatMassKg != null)
          Row(
            children: [
              Expanded(
                child: _massCard(
                  title: 'Čista mišična masa',
                  value: '${r.leanMassKg!.toStringAsFixed(1)} kg',
                  subtitle: 'Pusta telesna masa',
                  icon: Icons.fitness_center,
                  accentColor: Colors.blueAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _massCard(
                  title: 'Masa maščobe',
                  value: '${r.fatMassKg!.toStringAsFixed(1)} kg',
                  subtitle: 'Telesna maščoba',
                  icon: Icons.pie_chart_outline,
                  accentColor: Colors.orangeAccent,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),

        // ── Analysis Explanation ──
        _infoSection(
          title: 'Vizualna & Biometrična analiza',
          icon: Icons.psychology_alt_outlined,
          content: r.explanation,
          theme: theme,
        ),

        if (r.fatDistribution != null && r.fatDistribution!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoSection(
            title: 'Porazdelitev maščobe',
            icon: Icons.accessibility_new,
            content: r.fatDistribution!,
            theme: theme,
          ),
        ],

        if (r.recommendations != null && r.recommendations!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoSection(
            title: 'Priporočilo za trening & prehrano',
            icon: Icons.lightbulb_outline,
            content: r.recommendations!,
            theme: theme,
          ),
        ],
      ],
    );
  }

  Widget _massCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
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
              Icon(icon, size: 16, color: accentColor),
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

  Widget _infoSection({
    required String title,
    required IconData icon,
    required String content,
    required ThemeData theme,
  }) {
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

  Widget _buildErrorBox(String error) {
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
