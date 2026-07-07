import 'package:dating_app/core/search/engine/feature_engineering.dart';

/// Auto-tagging for a newly uploaded listing, derived ONLY from verified
/// coordinates with strict thresholds — so a tag is never wrong or misleading.
/// The returned labels are folded into the listing's features; the user can
/// still remove any of them.
class GeoAutoTags {
  const GeoAutoTags._();

  /// Verified geo feature labels for a property at [lat]/[lon].
  static List<String> compute(double lat, double lon) {
    if (lat == 0 && lon == 0) return const <String>[];
    final out = <String>[];

    // Near the sea — within ~1.5km of the Mediterranean coastline (walkable).
    final seaKm = IsraelGeoIndex.coastKm(lat, lon);
    if (seaKm != null && seaKm <= 1.5) out.add('קרוב לים');

    // Near a public park/garden — within 500m of a real, named park.
    final parkKm = IsraelGeoIndex.parkKm(lat, lon);
    if (parkKm != null && parkKm <= 0.5) out.add('קרוב לפארק');

    return out;
  }
}
