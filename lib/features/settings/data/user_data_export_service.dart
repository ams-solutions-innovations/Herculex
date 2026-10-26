import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/local_data_wipe.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ExportShareCallback = Future<ShareResult> Function(XFile file);

final userDataExportServiceProvider = Provider<UserDataExportService>((ref) {
  return UserDataExportService(
    database: ref.watch(appDatabaseProvider),
    profileRepository: ref.watch(localProfileRepositoryProvider),
    preferences: ref.watch(sharedPreferencesProvider),
  );
});

/// Builds a complete GDPR Article 20 portable JSON archive of all user-owned
/// local data (profile, non-sensitive preferences, every user SQLite table, and
/// custom catalogue entries) and opens the native OS share/save sheet.
class UserDataExportService {
  UserDataExportService({
    required GeneratedDatabase database,
    required LocalProfileRepository profileRepository,
    required SharedPreferences preferences,
    Clock clock = const SystemClock(),
    Future<Directory> Function()? tempDirectoryProvider,
    ExportShareCallback? shareFile,
  }) : _database = database,
       _profileRepository = profileRepository,
       _preferences = preferences,
       _clock = clock,
       _tempDirectoryProvider = tempDirectoryProvider ?? getTemporaryDirectory,
       _shareFile = shareFile ?? _defaultShare;

  final GeneratedDatabase _database;
  final LocalProfileRepository _profileRepository;
  final SharedPreferences _preferences;
  final Clock _clock;
  final Future<Directory> Function() _tempDirectoryProvider;
  final ExportShareCallback _shareFile;

  static const _excludedPreferencePrefixes = <String>[
    'supabase.',
    'herculex.auth_',
  ];

  static Future<ShareResult> _defaultShare(XFile file) {
    return Share.shareXFiles([file], subject: 'Herculex Data Export');
  }

  /// Generates the JSON payload as a structured map (without writing to disk).
  Future<Map<String, Object?>> buildExportPayload() async {
    final now = _clock.now().toUtc();
    final tablesPayload = <String, List<Map<String, Object?>>>{};

    for (final table in fullyClearedTables) {
      final rows = await _database.customSelect('SELECT * FROM $table').get();
      tablesPayload[table] = rows.map((r) => _sanitizeRow(r.data)).toList();
    }

    final customCatalogue = <String, List<Map<String, Object?>>>{};
    for (final table in catalogueTables) {
      final rows = await _database
          .customSelect('SELECT * FROM $table WHERE is_custom = 1')
          .get();
      customCatalogue[table] = rows.map((r) => _sanitizeRow(r.data)).toList();
    }

    // Include custom catalogue child metadata rows without dumping 45k seeded rows.
    final customExerciseMuscles = await _database
        .customSelect(
          'SELECT m.* FROM exercise_muscles m '
          'JOIN exercise_catalog e ON e.id = m.exercise_id '
          'WHERE e.is_custom = 1',
        )
        .get();
    if (customExerciseMuscles.isNotEmpty) {
      customCatalogue['exercise_muscles'] = customExerciseMuscles
          .map((r) => _sanitizeRow(r.data))
          .toList();
    }

    final customExerciseAliases = await _database
        .customSelect(
          'SELECT a.* FROM exercise_aliases a '
          'JOIN exercise_catalog e ON e.id = a.exercise_id '
          'WHERE e.is_custom = 1',
        )
        .get();
    if (customExerciseAliases.isNotEmpty) {
      customCatalogue['exercise_aliases'] = customExerciseAliases
          .map((r) => _sanitizeRow(r.data))
          .toList();
    }

    final customFoodMicros = await _database
        .customSelect(
          'SELECT m.* FROM food_micros m '
          'JOIN foods f ON f.id = m.food_id '
          'WHERE f.is_custom = 1',
        )
        .get();
    if (customFoodMicros.isNotEmpty) {
      customCatalogue['food_micros'] = customFoodMicros
          .map((r) => _sanitizeRow(r.data))
          .toList();
    }

    final exportedPreferences = <String, Object?>{};
    final sortedKeys = _preferences.getKeys().toList()..sort();
    for (final key in sortedKeys) {
      if (_isExcludedPreferenceKey(key)) continue;
      exportedPreferences[key] = _preferences.get(key);
    }

    return <String, Object?>{
      'format': 'herculex_user_data_export_v1',
      'exportedAtUtc': now.toIso8601String(),
      'schemaVersion': _database.schemaVersion,
      'profile': _profileRepository.currentProfile?.toJson(),
      'preferences': exportedPreferences,
      'tables': tablesPayload,
      'customCatalogue': customCatalogue,
    };
  }

  /// Writes the export JSON to a temporary file and opens the OS share sheet.
  Future<File> exportAndShare() async {
    final payload = await buildExportPayload();
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    final tempDir = await _tempDirectoryProvider();
    final dateStamp = DateFormat('yyyy-MM-dd').format(_clock.now());
    final file = File(p.join(tempDir.path, 'herculex_export_$dateStamp.json'));
    await file.writeAsString(encoded, flush: true);
    await _shareFile(
      XFile(
        file.path,
        mimeType: 'application/json',
        name: p.basename(file.path),
      ),
    );
    return file;
  }

  static bool _isExcludedPreferenceKey(String key) {
    final lower = key.toLowerCase();
    for (final prefix in _excludedPreferencePrefixes) {
      if (lower.startsWith(prefix)) return true;
    }
    return lower.contains('token') || lower.contains('secret');
  }

  static Map<String, Object?> _sanitizeRow(Map<String, Object?> raw) {
    return raw.map((key, value) {
      if (value is Uint8List) {
        return MapEntry(key, base64Encode(value));
      }
      if (value is DateTime) {
        return MapEntry(key, value.toUtc().toIso8601String());
      }
      return MapEntry(key, value);
    });
  }
}
