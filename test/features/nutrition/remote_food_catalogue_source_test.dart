import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/food_catalogue_importer.dart';
import 'package:herculex/features/nutrition/data/remote_food_catalogue_source.dart';

Map<String, dynamic> _item(String id, String name, {String? barcode}) => {
  'id': id,
  'name': name,
  'barcode': barcode,
  'referenceBasis': '100 g',
  'catalogue': {'brand': 'Herculex Farms', 'category': 'Meat'},
  'nutrients': {
    'energy_kcal': 165,
    'protein': 31,
    'carbohydrates': 0,
    'fat': 3.6,
  },
  'serving': {'amount': 100, 'unit': 'g', 'weightGramsOrMl': 100},
};

class _FakeRemote implements FoodCatalogueRemote {
  final catalogue = <Map<String, dynamic>>[
    _item('eu-1', 'Chicken breast', barcode: '3800000000011'),
    _item('eu-2', 'Chickpeas'),
    _item('eu-3', 'Oat flakes'),
  ];
  final searches = <String>[];
  final idLookups = <List<String>>[];
  final barcodeLookups = <List<String>>[];

  @override
  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 30,
  }) async {
    searches.add(query);
    return catalogue
        .where((f) => (f['name'] as String).toLowerCase().contains(query))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> byIds(List<String> catalogueIds) async {
    idLookups.add(catalogueIds);
    return catalogue.where((f) => catalogueIds.contains(f['id'])).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> byBarcodes(List<String> barcodes) async {
    barcodeLookups.add(barcodes);
    return catalogue.where((f) => barcodes.contains(f['barcode'])).toList();
  }
}

void main() {
  late AppDatabase db;
  late _FakeRemote remote;
  late RemoteFoodCatalogueSource source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = _FakeRemote();
    source = RemoteFoodCatalogueSource(db, remote, debounce: Duration.zero);
  });

  tearDown(() => db.close());

  Future<List<FoodData>> catalogueFoods() =>
      (db.select(db.foods)..where((t) => t.catalogueId.isNotNull())).get();

  test('a search caches matches as non-custom catalogue rows', () async {
    await source.ensureSearchResults('Chick');

    final foods = await catalogueFoods();
    expect(foods.map((f) => f.catalogueId), unorderedEquals(['eu-1', 'eu-2']));
    expect(foods.every((f) => !f.isCustom), isTrue);
    expect(foods.first.source, 'food_catalogue_v1');
    // Non-custom catalogue rows never reach the sync outbox.
    expect(await db.select(db.pendingSyncOps).get(), isEmpty);
  });

  test('rows match what the bundled import would have written', () async {
    await source.ensureSearchResults('oat');
    final cached = (await catalogueFoods()).single;
    final expected = FoodCatalogueImporter.companionFor(remote.catalogue[2]);
    expect(cached.name, expected.name.value);
    expect(cached.kcalPer100g, expected.kcalPer100g.value);
    expect(cached.servingLabel, expected.servingLabel.value);
  });

  test('a repeated query is served from the cache', () async {
    await source.ensureSearchResults('chick');
    await source.ensureSearchResults(' CHICK ');
    expect(remote.searches, ['chick']);
    expect(await catalogueFoods(), hasLength(2));
  });

  test('only the latest of overlapping queries reaches the network', () async {
    final debounced = RemoteFoodCatalogueSource(
      db,
      remote,
      debounce: const Duration(milliseconds: 20),
    );
    await Future.wait([
      debounced.ensureSearchResults('ch'),
      debounced.ensureSearchResults('chi'),
      debounced.ensureSearchResults('chic'),
    ]);
    expect(remote.searches, ['chic']);
  });

  test('ensureFoods fetches only refs that are not local yet', () async {
    await source.ensureSearchResults('oat');
    await source.ensureFoods({'eu-1', 'eu-3'});

    expect(remote.idLookups, [
      ['eu-1'],
    ]);
    expect(
      (await catalogueFoods()).map((f) => f.catalogueId),
      unorderedEquals(['eu-1', 'eu-3']),
    );
  });

  test('a known barcode is not fetched again', () async {
    await source.ensureBarcode(['3800000000011']);
    await source.ensureBarcode(['3800000000011']);
    expect(remote.barcodeLookups, hasLength(1));
    expect((await catalogueFoods()).single.catalogueId, 'eu-1');
  });

  test(
    're-fetching a cached food updates it instead of duplicating it',
    () async {
      await source.ensureFoods({'eu-2'});
      remote.catalogue[1] = _item('eu-2', 'Chickpeas, cooked');
      await source.ensureSearchResults('chickpeas');

      final foods = await catalogueFoods();
      expect(foods, hasLength(1));
      expect(foods.single.name, 'Chickpeas, cooked');
    },
  );
}
