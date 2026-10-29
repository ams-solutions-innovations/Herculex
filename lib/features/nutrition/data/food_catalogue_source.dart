import 'package:herculex/data/sync/catalogue_ref_prefetcher.dart';

/// Where catalogue foods come from before they are rows in the local `foods`
/// table.
///
/// Phones import the bundled EU catalogue on first run, so every lookup is
/// already local ([BundledFoodCatalogueSource] does nothing). The web can't
/// ship 49 MB, so it fetches what a search, a barcode or a synced entry needs
/// from Supabase and caches it locally ([RemoteFoodCatalogueSource]) — after
/// which every existing query, the picker and food logging work unchanged.
abstract interface class FoodCatalogueSource implements CatalogueRefPrefetcher {
  /// Makes sure catalogue foods matching [query] are in `foods`.
  Future<void> ensureSearchResults(String query);

  /// Makes sure the catalogue food with any of these barcodes is in `foods`.
  Future<void> ensureBarcode(List<String> candidates);
}

class BundledFoodCatalogueSource implements FoodCatalogueSource {
  const BundledFoodCatalogueSource();

  @override
  Future<void> ensureSearchResults(String query) async {}

  @override
  Future<void> ensureBarcode(List<String> candidates) async {}

  @override
  Future<void> ensureFoods(Set<String> catalogueRefs) async {}
}
