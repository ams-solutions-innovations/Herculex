import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/food_catalogue_importer.dart';
import 'package:herculex/features/nutrition/data/food_catalogue_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The network half of [RemoteFoodCatalogueSource]: raw catalogue items (the
/// same JSON objects as `food_database_eu.v1.json`'s `foods`), fetched from
/// the shared `food_catalogue` table.
abstract interface class FoodCatalogueRemote {
  Future<List<Map<String, dynamic>>> search(String query, {int limit});
  Future<List<Map<String, dynamic>>> byBarcodes(List<String> barcodes);
  Future<List<Map<String, dynamic>>> byIds(List<String> catalogueIds);
}

class SupabaseFoodCatalogueRemote implements FoodCatalogueRemote {
  const SupabaseFoodCatalogueRemote(this._client);

  final SupabaseClient _client;

  List<Map<String, dynamic>> _items(Object? rows) => [
    for (final row in (rows as List? ?? const []))
      if (row is Map && row['item'] is Map)
        (row['item'] as Map).cast<String, dynamic>(),
  ];

  @override
  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 30,
  }) async => _items(
    await _client.rpc(
      'search_food_catalogue',
      params: {'q': query, 'max_results': limit},
    ),
  );

  @override
  Future<List<Map<String, dynamic>>> byBarcodes(List<String> barcodes) async =>
      _items(
        await _client
            .from('food_catalogue')
            .select('item')
            .inFilter('barcode', barcodes)
            .limit(10),
      );

  @override
  Future<List<Map<String, dynamic>>> byIds(List<String> catalogueIds) async =>
      _items(
        await _client
            .from('food_catalogue')
            .select('item')
            .inFilter('catalogue_id', catalogueIds),
      );
}

/// Web [FoodCatalogueSource]: fetches catalogue foods on demand and caches
/// them in the local `foods` table as ordinary (non-custom) catalogue rows,
/// mapped by the very [FoodCatalogueImporter] the phone's bundled import
/// uses — so a food here is byte-identical to the phone's copy, and nothing
/// downstream (search, picker, logging, snapshots, sync) knows the
/// difference. Non-custom rows never enter the sync outbox (the triggers
/// skip them), so caching is invisible to the server.
class RemoteFoodCatalogueSource implements FoodCatalogueSource {
  RemoteFoodCatalogueSource(
    this._db,
    this._remote, {
    this.debounce = const Duration(milliseconds: 250),
    this.searchLimit = 30,
  });

  final AppDatabase _db;
  final FoodCatalogueRemote _remote;

  /// Typing fires a search per keystroke; only a query that stays put this
  /// long reaches the network.
  final Duration debounce;
  final int searchLimit;

  static const _maxRememberedQueries = 200;
  static const _idChunk = 100;

  /// Queries already fetched this session, oldest first.
  final _searched = LinkedHashSet<String>();
  int _searchTicket = 0;

  /// Writes run one after another: there is no unique index on
  /// `foods.catalogue_id`, so two overlapping lookups of the same food would
  /// otherwise both insert it.
  Future<void> _writes = Future.value();

  @override
  Future<void> ensureSearchResults(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2 || _searched.contains(q)) return;

    final ticket = ++_searchTicket;
    await Future<void>.delayed(debounce);
    if (ticket != _searchTicket) return; // superseded by a newer query

    final items = await _remote.search(q, limit: searchLimit);
    await _store(items);
    _searched.add(q);
    if (_searched.length > _maxRememberedQueries) {
      _searched.remove(_searched.first);
    }
  }

  @override
  Future<void> ensureBarcode(List<String> candidates) async {
    if (candidates.isEmpty) return;
    final local = await (_db.select(
      _db.foods,
    )..where((t) => t.barcode.isIn(candidates))).get();
    if (local.isNotEmpty) return;
    await _store(await _remote.byBarcodes(candidates));
  }

  @override
  Future<void> ensureFoods(Set<String> catalogueRefs) async {
    if (catalogueRefs.isEmpty) return;
    final present = await _localIds(catalogueRefs);
    final missing = catalogueRefs.difference(present.keys.toSet()).toList();
    for (var start = 0; start < missing.length; start += _idChunk) {
      final end = (start + _idChunk).clamp(0, missing.length);
      await _store(await _remote.byIds(missing.sublist(start, end)));
    }
  }

  Future<Map<String, int>> _localIds(Iterable<String> catalogueIds) async {
    final rows = await (_db.select(
      _db.foods,
    )..where((t) => t.catalogueId.isIn(catalogueIds))).get();
    return {for (final f in rows) f.catalogueId!: f.id};
  }

  Future<void> _store(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return _writes;
    return _writes = _writes.then((_) => _write(items));
  }

  Future<void> _write(List<Map<String, dynamic>> items) async {
    final byId = {
      for (final item in items)
        if (item['id'] != null) item['id'].toString(): item,
    };
    if (byId.isEmpty) return;
    final existing = await _localIds(byId.keys);
    await _db.batch((batch) {
      for (final MapEntry(key: catalogueId, value: item) in byId.entries) {
        final companion = FoodCatalogueImporter.companionFor(item);
        final localId = existing[catalogueId];
        if (localId == null) {
          batch.insert(_db.foods, companion);
        } else {
          batch.update(
            _db.foods,
            companion,
            where: (t) => t.id.equals(localId),
          );
        }
      }
    });
  }
}
