import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';

/// Collects up to two photos of a product: the product itself and its
/// nutrition table. Either can be a camera shot or a gallery image.
///
/// Pops with the photos in the order the AI expects — product first, table
/// last — or null when dismissed.
class ProductPhotosSheet extends ConsumerStatefulWidget {
  const ProductPhotosSheet({
    super.key,
    required this.pendingContext,
    this.requireTable = true,
    this.confirmLabel = 'Continue',
  });

  /// Stored while the camera is open so Android can restore the flow if it
  /// kills the app in the background.
  final PendingAiScanContext Function() pendingContext;

  /// A nutrition label cannot be read without its table; a barcode lookup can
  /// identify the product from the product photo alone.
  final bool requireTable;
  final String confirmLabel;

  static Future<List<File>?> show(
    BuildContext context, {
    required PendingAiScanContext Function() pendingContext,
    bool requireTable = true,
    String confirmLabel = 'Continue',
  }) {
    return showModalBottomSheet<List<File>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductPhotosSheet(
        pendingContext: pendingContext,
        requireTable: requireTable,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  ConsumerState<ProductPhotosSheet> createState() => _ProductPhotosSheetState();
}

class _ProductPhotosSheetState extends ConsumerState<ProductPhotosSheet> {
  File? _product;
  File? _table;

  bool get _ready => widget.requireTable
      ? _table != null
      : (_product != null || _table != null);

  Future<void> _pick({required bool table}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take photo with camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose image from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final pending = ref.read(pendingAiScanServiceProvider);
    await pending.setPendingContext(widget.pendingContext());
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    await pending.clearPendingContext();
    if (picked == null || !mounted) return;
    setState(() {
      final file = File(picked.path);
      if (table) {
        _table = file;
      } else {
        _product = file;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.photo_camera_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scan product',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              widget.requireTable
                  ? 'Add up to two photos: the product and its nutrition '
                        'table. The table photo is required.'
                  : 'Add up to two photos: the product and its nutrition '
                        'table. One is enough.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PhotoSlot(
                    title: 'Product',
                    hint: widget.requireTable ? 'Optional' : 'Photo',
                    icon: Icons.fastfood_outlined,
                    file: _product,
                    onTap: () => _pick(table: false),
                    onClear: () => setState(() => _product = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PhotoSlot(
                    title: 'Nutrition table',
                    hint: widget.requireTable ? 'Required' : 'Photo',
                    icon: Icons.table_chart_outlined,
                    file: _table,
                    onTap: () => _pick(table: true),
                    onClear: () => setState(() => _table = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _ready
                    ? () => Navigator.of(context).pop([?_product, ?_table])
                    : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(widget.confirmLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.title,
    required this.hint,
    required this.icon,
    required this.file,
    required this.onTap,
    required this.onClear,
  });

  final String title;
  final String hint;
  final IconData icon;
  final File? file;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
              ),
              image: hasFile
                  ? DecorationImage(image: FileImage(file!), fit: BoxFit.cover)
                  : null,
            ),
            child: hasFile
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: AppColors.primary, size: 30),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
          ),
          if (hasFile)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
