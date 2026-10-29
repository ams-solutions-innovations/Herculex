// Uploads the bundled EU food catalogue into the shared, read-only
// `food_catalogue` table that the web app searches (W4). Phones keep using
// their bundled copy; this only feeds the web.
//
//   $env:SUPABASE_URL = 'https://ldzgyzigvbwofbswitrv.supabase.co'
//   $env:SUPABASE_SERVICE_ROLE_KEY = '<service role key — never commit it>'
//   dart run tool/web/upload_food_catalogue.dart [--dry-run]
//
// Rows are stored with the raw catalogue item as JSON so the client maps them
// through the same FoodCatalogueImporter code the phone uses — a food looked
// up on the web is byte-identical to the one in the phone's database.
// Idempotent: re-running upserts by catalogue_id.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _assetPath = 'assets/data/food_database_eu.v1.json';
const _sourceSchemaVersion = 'herculex-food-catalogue/v1';
const _batchSize = 500;

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final url = Platform.environment['SUPABASE_URL'];
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (!dryRun && (url == null || serviceKey == null)) {
    stderr.writeln('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');
    exit(64);
  }

  final document =
      jsonDecode(await File(_assetPath).readAsString()) as Map<String, dynamic>;
  if (document['schemaVersion'] != _sourceSchemaVersion) {
    stderr.writeln('Unexpected schemaVersion ${document['schemaVersion']}');
    exit(65);
  }
  final foods = (document['foods'] as List).cast<Map<String, dynamic>>();
  final expected = (document['statistics'] as Map?)?['foodCount'];
  if (expected != foods.length) {
    stderr.writeln('Count mismatch: $expected in metadata, ${foods.length} rows');
    exit(65);
  }

  final rows = [
    for (final item in foods)
      if (item['id'] != null)
        {
          'catalogue_id': item['id'].toString(),
          'name': item['name']?.toString() ?? 'Unknown food',
          'brand': _blankToNull((item['catalogue'] as Map?)?['brand']),
          'barcode': _blankToNull(item['barcode']),
          'item': item,
          'source_version': _sourceSchemaVersion,
        },
  ];
  stdout.writeln('${rows.length} foods ready');
  if (dryRun) return;

  final endpoint = Uri.parse('$url/rest/v1/food_catalogue');
  final client = http.Client();
  try {
    for (var start = 0; start < rows.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, rows.length);
      final response = await client.post(
        endpoint,
        headers: {
          'apikey': serviceKey!,
          'Authorization': 'Bearer $serviceKey',
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: jsonEncode(rows.sublist(start, end)),
      );
      if (response.statusCode >= 300) {
        stderr.writeln('Batch $start-$end failed: ${response.statusCode}');
        stderr.writeln(response.body);
        exit(1);
      }
      stdout.writeln('uploaded $end / ${rows.length}');
    }
  } finally {
    client.close();
  }
}

String? _blankToNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
