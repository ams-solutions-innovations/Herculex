import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../data/measurements_repository.dart';

final _allMeasurementsProvider =
    StreamProvider<List<BodyMeasurementData>>((ref) {
  return ref.watch(measurementsRepositoryProvider).watchAll();
});

final _photosProvider =
    StreamProvider.family<List<ProgressPhotoData>, String>((ref, pose) {
  return ref.watch(measurementsRepositoryProvider).watchPhotos(pose: pose);
});

/// Body measurements overview (§17): Stacked list of measurement metrics
/// navigating to dedicated detail pages, plus progress photos tab.
class MeasurementsView extends ConsumerStatefulWidget {
  const MeasurementsView({super.key});

  @override
  ConsumerState<MeasurementsView> createState() => _MeasurementsViewState();
}

class _MeasurementsViewState extends ConsumerState<MeasurementsView> {
  static const _labels = <String, String>{
    'bodyweight': 'Bodyweight',
    'neck': 'Neck',
    'chest': 'Chest',
    'arms_l': 'Arm (L)',
    'arms_r': 'Arm (R)',
    'waist': 'Waist',
    'hips': 'Hips',
    'thigh_l': 'Thigh (L)',
    'thigh_r': 'Thigh (R)',
    'calf_l': 'Calf (L)',
    'calf_r': 'Calf (R)',
    'back': 'Back',
  };

  static IconData _getMetricIcon(String metric) {
    switch (metric) {
      case 'bodyweight':
        return Icons.monitor_weight_outlined;
      case 'chest':
        return Icons.fitness_center_outlined;
      case 'waist':
      case 'hips':
        return Icons.accessibility_new_outlined;
      case 'arms_l':
      case 'arms_r':
        return Icons.sports_gymnastics;
      case 'thigh_l':
      case 'thigh_r':
      case 'calf_l':
      case 'calf_r':
        return Icons.directions_walk_outlined;
      default:
        return Icons.straighten;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allMeasurementsAsync = ref.watch(_allMeasurementsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Measurements'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Metrics'), Tab(text: 'Photos')],
          ),
        ),
        body: TabBarView(
          children: [
            // ── Tab 1: Metrics (Stacked List View) ──
            allMeasurementsAsync.when(
              data: (allRows) {
                // Group measurements by metric key
                final Map<String, List<BodyMeasurementData>> grouped = {};
                for (final row in allRows) {
                  grouped.putIfAbsent(row.metric, () => []).add(row);
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: MeasurementsRepository.builtInMetrics.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final metricKey =
                        MeasurementsRepository.builtInMetrics[index];
                    final label = _labels[metricKey] ?? metricKey;
                    final unit = metricKey == 'bodyweight' ? 'kg' : 'cm';
                    final rows = grouped[metricKey] ?? [];

                    final latest = rows.isNotEmpty ? rows.last : null;
                    final previous = rows.length >= 2 ? rows[rows.length - 2] : null;

                    double? diff;
                    if (latest != null && previous != null) {
                      diff = latest.value - previous.value;
                    }

                    return _MetricStackedCard(
                      metricKey: metricKey,
                      label: label,
                      unit: unit,
                      icon: _getMetricIcon(metricKey),
                      latest: latest,
                      diff: diff,
                      onTap: () {
                        Haptics.selection();
                        context.push('/measurements/$metricKey');
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading metrics: $e')),
            ),

            // ── Tab 2: Progress Photos ──
            _PhotosTab(onAddPhoto: _capturePhoto),
          ],
        ),
      ),
    );
  }

  Future<void> _capturePhoto() async {
    Haptics.light();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final pose = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in ['front', 'side', 'back'])
              ListTile(
                title: Text(p[0].toUpperCase() + p.substring(1)),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (pose == null || !mounted) return;

    final file = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (file == null || !mounted) return;

    await ref.read(measurementsRepositoryProvider).addPhoto(
          dateIso: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          pose: pose,
          filePath: file.path,
        );
  }
}

class _MetricStackedCard extends StatelessWidget {
  final String metricKey;
  final String label;
  final String unit;
  final IconData icon;
  final BodyMeasurementData? latest;
  final double? diff;
  final VoidCallback onTap;

  const _MetricStackedCard({
    required this.metricKey,
    required this.label,
    required this.unit,
    required this.icon,
    required this.latest,
    required this.diff,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String valueSubtitle = 'No entries yet';
    if (latest != null) {
      final date = DateTime.tryParse(latest!.dateIso);
      final formattedDate = date != null
          ? DateFormat('d MMM').format(date)
          : latest!.dateIso;
      valueSubtitle = '${latest!.value.toStringAsFixed(1)} $unit • $formattedDate';
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon Avatar
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 14),

                // Label and Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        valueSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: latest != null
                              ? AppColors.secondary
                              : AppColors.secondary.withValues(alpha: 0.6),
                          fontWeight: latest != null
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),

                // Trend badge if change exists
                if (diff != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (metricKey == 'bodyweight'
                              ? (diff! < 0 ? Colors.green : Colors.orange)
                              : (diff! > 0 ? Colors.green : Colors.blue))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${diff! >= 0 ? '+' : ''}${diff!.toStringAsFixed(1)} $unit',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: metricKey == 'bodyweight'
                            ? (diff! < 0 ? Colors.green : Colors.orange)
                            : (diff! > 0 ? Colors.green : Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                Icon(
                  Icons.chevron_right,
                  color: AppColors.secondary.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotosTab extends ConsumerStatefulWidget {
  final VoidCallback onAddPhoto;
  const _PhotosTab({required this.onAddPhoto});

  @override
  ConsumerState<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends ConsumerState<_PhotosTab> {
  String _pose = 'front';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photosAsync = ref.watch(_photosProvider(_pose));

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'front', label: Text('Front')),
                ButtonSegment(value: 'side', label: Text('Side')),
                ButtonSegment(value: 'back', label: Text('Back')),
              ],
              selected: {_pose},
              onSelectionChanged: (s) {
                Haptics.selection();
                setState(() => _pose = s.first);
              },
            ),
          ),
          Expanded(
            child: photosAsync.when(
              data: (photos) => photos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera_outlined,
                              size: 48,
                              color: AppColors.secondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text('No $_pose photos yet',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.secondary)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: photos.length,
                      itemBuilder: (context, i) {
                        final photo = photos[i];
                        return _PhotoCard(
                          photo: photo,
                          onDelete: () => ref
                              .read(measurementsRepositoryProvider)
                              .deletePhoto(photo.id),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onAddPhoto,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Add Photo'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final ProgressPhotoData photo;
  final VoidCallback onDelete;
  const _PhotoCard({required this.photo, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(photo.filePath);
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: file.existsSync()
              ? Image.file(file, fit: BoxFit.cover)
              : Container(
                  color: AppColors.surfaceContainer,
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.secondary),
                ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Text(photo.dateIso,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white)),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              Haptics.medium();
              onDelete();
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}