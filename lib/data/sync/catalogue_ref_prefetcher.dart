/// Lets [SyncService] make sure the catalogue rows a pulled row points at are
/// in the local database *before* the row is applied.
///
/// Phones import the whole bundled food catalogue, so a food entry pulled from
/// another device always finds its `food_catalogue_ref` locally. A browser
/// only holds the foods it has looked up; without this, a pulled entry would
/// resolve to `food_id = NULL`, and editing it on the web would push the null
/// back and cut the link for every device.
///
/// An interface here (implemented in the nutrition feature) so `data/` never
/// imports `features/`.
abstract interface class CatalogueRefPrefetcher {
  /// Ensures every catalogue food in [catalogueRefs] exists in `foods`.
  /// Throws if they could not be fetched, so the caller can retry the table.
  Future<void> ensureFoods(Set<String> catalogueRefs);
}
