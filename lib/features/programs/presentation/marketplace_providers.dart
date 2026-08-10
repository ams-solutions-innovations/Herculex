import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/preset_catalog_repository.dart';
import '../data/program_csv_io.dart';
import '../domain/preset_program.dart';
import '../domain/program_csv.dart';

final presetCatalogRepositoryProvider =
    Provider<PresetCatalogRepository>((ref) => const PresetCatalogRepository());

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
