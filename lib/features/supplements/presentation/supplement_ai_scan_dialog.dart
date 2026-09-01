import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/nutrition/domain/nutrient_definitions.dart';
import 'package:herculex/features/supplements/data/supplement_ai_service.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';

/// Modal dialog / bottom sheet for analyzing supplement packaging, tubs,
/// bottles, and supplement facts labels with Gemini AI vision.
class SupplementAiScanDialog extends ConsumerStatefulWidget {
  final File? initialImage;

  const SupplementAiScanDialog({super.key, this.initialImage});

  static Future<SupplementAiResult?> show(
    BuildContext context, {
    File? initialImage,
  }) {
    return showModalBottomSheet<SupplementAiResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupplementAiScanDialog(initialImage: initialImage),
    );
  }

  @override
  ConsumerState<SupplementAiScanDialog> createState() =>
      _SupplementAiScanDialogState();
}

class _SupplementAiScanDialogState
    extends ConsumerState<SupplementAiScanDialog> {
  File? _imageFile;
  final _noteCtrl = TextEditingController();
  bool _analyzing = false;
  String? _error;
  SupplementAiResult? _result;

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

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    Haptics.light();
    try {
      await ref
          .read(pendingAiScanServiceProvider)
          .setPendingContext(
            PendingAiScanContext(type: AiScanContextType.supplement),
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
        final file = File(picked.path);
        setState(() {
          _imageFile = file;
          _error = null;
        });
        await _runAnalysis(file);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Napaka pri izbiri slike: $e');
      }
    }
  }

  Future<void> _runAnalysis(File file) async {
    setState(() {
      _analyzing = true;
      _error = null;
      _result = null;
    });

    try {
      final service = ref.read(supplementAiServiceProvider);
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      final res = await service.analyzeSupplementPhoto(
        imageFile: file,
        userNote: note,
      );

      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _result = res;
      });
      Haptics.medium();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = 'Napaka pri analizi dopolnila: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      color: const Color(0xFF9B59B6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.medication_outlined,
                      size: 22,
                      color: Color(0xFF9B59B6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Skeniranje prehranskega dopolnila',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Gemini AI Vision analiza deklaracije in odmerka',
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
        const SizedBox(height: 20),
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
              const Icon(
                Icons.auto_awesome,
                size: 52,
                color: Color(0xFF9B59B6),
              ),
              const SizedBox(height: 16),
              Text(
                'Slikajte embalažo ali deklaracijo dopolnila',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Gemini AI bo samodejno prebral ime izdelka, proizvajalca, priporočen odmerek ter razbral vsebnost vitaminov in mineralov.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  hintText: 'Opomba (neobvezno, npr. 2 kapsuli zjutraj)',
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
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
                        backgroundColor: const Color(0xFF9B59B6),
                        foregroundColor: Colors.white,
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
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(color: AppColors.surfaceContainer),
            child: Image.file(_imageFile!, fit: BoxFit.cover),
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B59B6)),
            ),
            SizedBox(height: 18),
            Text(
              'Gemini AI analizira prehransko dopolnilo in deklaracijo...',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6),
            Text(
              'Razbira ime izdelka, znamko, odmerek ter vsebnost vitaminov in mineralov',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(ThemeData theme) {
    final r = _result!;
    final byId = {for (final d in trackedNutrients) d.id: d};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF9B59B6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF9B59B6).withValues(alpha: 0.35),
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
                      color: const Color(0xFF9B59B6),
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
                  Text(
                    'Zanesljivost: ${(r.confidence * 100).toStringAsFixed(0)} %',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (r.description != null && r.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  r.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurface,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Ime dopolnila', r.name, Icons.label_outline),
              if (r.brand != null) ...[
                const Divider(height: 18),
                _detailRow('Znamka', r.brand!, Icons.business_outlined),
              ],
              if (r.doseAmount != null && r.doseUnit != null) ...[
                const Divider(height: 18),
                _detailRow(
                  'Priporočen odmerek',
                  '${r.doseAmount!.truncateToDouble() == r.doseAmount ? r.doseAmount!.toStringAsFixed(0) : r.doseAmount!.toStringAsFixed(1)} ${r.doseUnit}',
                  Icons.science_outlined,
                ),
              ],
              const Divider(height: 18),
              _detailRow(
                'Priporočen opomnik',
                r.schedule == SupplementSchedule.postWorkout
                    ? 'Po treningu'
                    : (r.schedule == SupplementSchedule.time &&
                              r.timeHHMM != null
                          ? 'Vsak dan ob ${r.timeHHMM}'
                          : 'Brez opomnika'),
                Icons.notifications_active_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (r.nutrients.isNotEmpty) ...[
          Text(
            'Zaznana mikrohranila in sestavine (na odmerek)',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: r.nutrients.entries.map((e) {
                final def = byId[e.key];
                final label = def?.label ?? e.key;
                final unit = def?.unit ?? '';
                final val = e.value.truncateToDouble() == e.value
                    ? e.value.toStringAsFixed(0)
                    : e.value.toStringAsFixed(1);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9B59B6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF9B59B6).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check,
                        size: 12,
                        color: Color(0xFF9B59B6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$label: ',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9B59B6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '$val $unit',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9B59B6),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],

        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: () {
              Haptics.selection();
              Navigator.of(context).pop(r);
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text(
              'Uporabi te podatke',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9B59B6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildActionButtons(theme),
      ],
    );
  }

  Widget _detailRow(String title, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF9B59B6)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
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
              padding: const EdgeInsets.symmetric(vertical: 13),
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
