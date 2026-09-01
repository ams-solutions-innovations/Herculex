import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/preset_catalog_repository.dart';
import '../data/program_csv_io.dart';
import '../domain/preset_program.dart';
import '../domain/program_csv.dart';
import '../domain/program_muscle_volume.dart';

final presetCatalogRepositoryProvider = Provider<PresetCatalogRepository>(
  (ref) => const PresetCatalogRepository(),
);

final presetCatalogProvider = FutureProvider<List<PresetProgramMeta>>((ref) {
  return ref.watch(presetCatalogRepositoryProvider).loadCatalog();
});

final presetProgramDocumentProvider =
    FutureProvider.family<ProgramCsvDocument, PresetProgramMeta>((ref, meta) {
      return ref.watch(presetCatalogRepositoryProvider).loadDocument(meta);
    });

final programCsvIoProvider = Provider<ProgramCsvIo>((ref) {
  return ProgramCsvIo(ref.watch(appDatabaseProvider));
});

final presetProgramVolumeProvider =
    FutureProvider.family<ProgramVolumeBreakdown, PresetProgramMeta>((
      ref,
      meta,
    ) async {
      final doc = await ref.watch(presetProgramDocumentProvider(meta).future);
      final db = ref.watch(appDatabaseProvider);
      final catalog = await db.select(db.exerciseCatalog).get();
      final exerciseToMuscle = <String, String>{
        for (final e in catalog) e.name.toLowerCase(): e.primaryMuscle,
      };
      for (final e in catalog) {
        if (e.aka != null) {
          for (final alias in e.aka!.split(',')) {
            if (alias.trim().isNotEmpty) {
              exerciseToMuscle[alias.trim().toLowerCase()] = e.primaryMuscle;
            }
          }
        }
      }
      return ProgramVolumeCalculator.computeFromCsv(
        doc,
        exerciseToMuscle: exerciseToMuscle,
      );
    });
