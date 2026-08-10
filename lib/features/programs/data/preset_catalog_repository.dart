import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/preset_program.dart';
import '../domain/program_csv.dart';

/// Loads the bundled program marketplace catalog from app assets. Pure asset
/// I/O — no database access, so preset programs can be previewed without
/// writing anything until the user chooses to import one.
class PresetCatalogRepository {
  const PresetCatalogRepository();

  Future<List<PresetProgramMeta>> loadCatalog() async {
    final raw = await rootBundle.loadString('assets/programs/catalog.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['programs'] as List;
    return list
        .map((e) => PresetProgramMeta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> loadCsv(PresetProgramMeta meta) {
    return rootBundle.loadString(meta.file);
  }

  Future<ProgramCsvDocument> loadDocument(PresetProgramMeta meta) async {
    final csv = await loadCsv(meta);
    return ProgramCsv.decode(csv);
  }
}
