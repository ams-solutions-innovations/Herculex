part of '../workout_finish_view.dart';

/// Optional progress photo attached to the session.
class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.summary,
    required this.onPick,
    required this.onRemove,
  });

  final SessionSummary summary;
  final void Function(ImageSource source) onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final photo = s.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'WORKOUT PHOTO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              if (hasPhoto)
                InkWell(
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      'Remove',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasPhoto) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(photo),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onPick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: const Text('Camera', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onPick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text(
                      'Gallery',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onPick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: const Text('Take photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onPick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text('From gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceVariant,
                      foregroundColor: theme.colorScheme.onSurface,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
