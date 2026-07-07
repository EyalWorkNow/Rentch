import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/data/models/rental_models.dart';

/// A basic, automatic 0–100 quality score for a listing, computed by our engine
/// from VERIFIED signals the moment it's uploaded — features, condition, how
/// complete the listing is, and its location access. Deterministic and honest
/// (no market comparison needed), so it works the instant a property is created.
class ListingScore {
  const ListingScore._();

  static const _premium = [
    'elevator', 'parking', 'balcony', 'mamad', 'ac',
    'renovated', 'furnished', 'storage', 'bars', 'accessible',
  ];

  /// 0–100.
  static int basic(RentalProperty p) {
    double s = 0;

    // Features — richer listing, higher score (up to 30).
    final feats = _premium.where((k) => p.featureFlags.isEnabled(k)).length;
    s += (feats / 6).clamp(0.0, 1.0) * 30;

    // Condition (up to 20).
    s += _conditionScore(p.condition) * 20;

    // Completeness — photos + core facts filled (up to 30).
    if (p.imageUrls.length >= 3) {
      s += 15;
    } else if (p.imageUrls.isNotEmpty) {
      s += 8;
    }
    if (p.sizeM2 > 0) s += 5;
    if (p.rooms > 0) s += 4;
    if (p.floor.trim().isNotEmpty) s += 3;
    if (p.neighborhood.trim().isNotEmpty || p.street.trim().isNotEmpty) s += 3;

    // Location access — near a park / the sea / centre (up to 20).
    if (p.lat != 0 || p.lon != 0) {
      s += IsraelGeoIndex.proximityKernel(
              IsraelGeoIndex.parkKm(p.lat, p.lon), scaleKm: 0.7) *
          8;
      s += IsraelGeoIndex.proximityKernel(
              IsraelGeoIndex.coastKm(p.lat, p.lon), scaleKm: 3.0) *
          7;
      s += IsraelGeoIndex.proximityKernel(
              IsraelGeoIndex.nearestCbdKm(p.lat, p.lon), scaleKm: 6.0) *
          5;
    }

    return s.round().clamp(0, 100);
  }

  static double _conditionScore(String condition) {
    final c = condition.trim();
    if (c.isEmpty) return 0.4;
    if (RegExp(r'חדש|משופ|מעולה|שמור').hasMatch(c)) return 1.0;
    if (RegExp(r'טוב|תקין|סביר').hasMatch(c)) return 0.7;
    if (RegExp(r'דורש|ישן|להשקע').hasMatch(c)) return 0.35;
    return 0.55;
  }

  static String label(int score) {
    if (score >= 85) return 'מודעה מצוינת 🏆';
    if (score >= 70) return 'מודעה טובה מאוד 👍';
    if (score >= 55) return 'מודעה טובה';
    return 'אפשר לשפר — הוסף תמונות ופרטים';
  }
}
