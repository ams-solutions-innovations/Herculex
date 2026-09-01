import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/presentation/exercise_artwork.dart';
import 'package:herculex/services/ai_service.dart';
import 'package:herculex/services/pending_ai_scan_service.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/theme/haptics.dart';
import 'package:image_picker/image_picker.dart';

/// Modal dialog / sheet for recognizing gym machines, setups and exercises
/// with Gemini AI vision.
class ExerciseAiScanDialog extends ConsumerStatefulWidget {
  final XFile? initialImage;

  const ExerciseAiScanDialog({super.key, this.initialImage});

  static Future<ExerciseCatalogData?> show(
    BuildContext context, {
    XFile? initialImage,
  }) {
    return showModalBottomSheet<ExerciseCatalogData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExerciseAiScanDialog(initialImage: initialImage),
    );
  }

  @override
  ConsumerState<ExerciseAiScanDialog> createState() =>
      _ExerciseAiScanDialogState();
}

class _ExerciseAiScanDialogState extends ConsumerState<ExerciseAiScanDialog> {
  XFile? _imageFile;
  bool _analyzing = false;
  String? _error;
  ExerciseAiScanResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) {
      _imageFile = widget.initialImage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runAnalysis(widget.initialImage!);
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    Haptics.light();
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(type: AiScanContextType.exercise),
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
          _imageFile = picked;
          _error = null;
        });
        await _runAnalysis(picked);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Napaka pri izbiri slike: $e');
      }
    }
  }

  Future<void> _runAnalysis(XFile file) async {
    setState(() {
      _analyzing = true;
      _error = null;
      _result = null;
    });

    try {
      final ai = ref.read(aiServiceProvider);
      final res = await ai.identifyExerciseDetailedFromImage(file);

      if (!mounted) return;

      if (res == null) {
        setState(() {
          _analyzing = false;
          _error =
              'Gemini AI na sliki ni zaznal fitnes naprave ali vaje. Poskusite znova z bolj jasnega kota.';
        });
      } else {
        setState(() {
          _analyzing = false;
          _result = res;
        });
        Haptics.medium();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = 'Napaka pri analizi: ';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
                    child: Icon(
                      Icons.fitness_center_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prepoznavanje fitnes naprave',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Gemini AI Vision analiza opreme in vaj',
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
                  if (_imageFile == null) ...[
                    _buildImagePickerPrompt(theme),
                  ] else ...[
                    _buildImagePreview(theme),
                    const SizedBox(height: 16),

                    if (_analyzing) ...[
                      _buildAnalyzingState(theme),
                    ] else if (_error != null) ...[
                      _buildErrorBox(_error!),
                      const SizedBox(height: 16),
                      _buildActionButtons(theme),
                    ] else if (_result != null) ...[
                      _buildResultView(theme),
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

  Widget _buildImagePickerPrompt(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Slikajte fitnes napravo ali opremo',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Gemini AI bo samodejno prepoznal napravo, določil ciljne mišične skupine in poiskal ustrezno vajo v Herculex katalogu.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galerija'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Kamera'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview(ThemeData theme) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 190,
            width: double.infinity,
            decoration: BoxDecoration(color: AppColors.surfaceContainer),
            child: Image.file(File(_imageFile!.path), fit: BoxFit.cover),
          ),
        ),
        Positioned(
          bottom: 8,
          right: 8,
          child: InkWell(
            onTap: () => _pickImage(ImageSource.camera),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Nova slika',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzingState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              'Gemini AI analizira fitnes napravo in opremo...',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Prepoznavanje biomehanike gibanja, opreme in iskanje vaje v bazi',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(ThemeData theme) {
    final res = _result!;
    final best = res.bestMatch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.primary.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Prepoznano',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      res.identifiedName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (res.description != null && res.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  res.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        if (best != null) ...[
          Text(
            'Ujemajoča vaja v katalogu',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          _ExerciseCard(
            exercise: best,
            isPrimary: true,
            onSelect: () {
              Haptics.selection();
              Navigator.of(context).pop(best);
            },
          ),
          const SizedBox(height: 20),
        ],

        if (res.alternativeMatches.isNotEmpty) ...[
          Text(
            'Podobne različice in opcije',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          for (final alt in res.alternativeMatches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ExerciseCard(
                exercise: alt,
                isPrimary: false,
                onSelect: () {
                  Haptics.selection();
                  Navigator.of(context).pop(alt);
                },
              ),
            ),
          const SizedBox(height: 12),
        ],

        if (best == null && res.alternativeMatches.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Naprava je bila prepoznana kot "", vendar v katalogu ni bilo najdenega natančnega ujemanja.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
        ],

        _buildActionButtons(theme),
      ],
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Ponovno slikaj'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBox(String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade300.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.red.shade300),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: Colors.red.shade300, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final ExerciseCatalogData exercise;
  final bool isPrimary;
  final VoidCallback onSelect;

  const _ExerciseCard({
    required this.exercise,
    required this.isPrimary,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPrimary
              ? AppColors.primaryContainer.withValues(alpha: 0.25)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPrimary
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.3),
            width: isPrimary ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            ExerciseArtwork(exercise: exercise, size: 48, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ' · ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSelect,
              style: FilledButton.styleFrom(
                backgroundColor: isPrimary
                    ? AppColors.primary
                    : AppColors.surfaceVariant,
                foregroundColor: isPrimary ? Colors.white : AppColors.onSurface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isPrimary ? 'Dodaj' : 'Izberi',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
