import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// Criteria collected by the AI search assistant (3-turn conversation).
class PropertySearchCriteria {
  const PropertySearchCriteria({
    this.city,
    this.minPrice,
    this.maxPrice,
    this.minRooms,
    this.amenityKeys = const {},
    this.vibe,
  });

  final String? city;
  final int? minPrice;
  final int? maxPrice;
  final double? minRooms;
  // PropertyFeatureSet keys, e.g. {'feat_parking','feat_balcony'}.
  final Set<String> amenityKeys;
  // Soft preference, not used as a hard filter for now.
  final String? vibe;
}

// Reads real listings from the AWS-backed properties table and matches them
// against the assistant's criteria.
//
// ponytail: city is filtered server-side (plain string equality — the pattern
// the app already relies on); price/rooms/amenities/active are filtered
// client-side over the capped page. Push these server-side once the AWS query
// layer's numeric/boolean equality semantics are confirmed.
class PropertySearchRepository {
  PropertySearchRepository({String? tableId})
      : _tableId = tableId ?? AppConfig.appwritePropertiesTableId;

  final String _tableId;
  final _breaker = CircuitBreaker(name: 'property-search');

  bool get isConfigured => AppConfig.canUseProperties && _tableId.isNotEmpty;

  Future<List<RentalProperty>> search(
    PropertySearchCriteria c, {
    int limit = 100,
  }) async {
    if (!isConfigured || _breaker.isOpen) return const [];

    final queries = <String>[
      if (c.city != null && c.city!.trim().isNotEmpty)
        Query.equal('city', c.city!.trim()),
      Query.limit(limit),
    ];

    try {
      final result = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.listRows(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            queries: queries,
          ),
        ),
      );

      final parsed = result.rows
          .map((row) => _safeParse(row.data))
          .whereType<RentalProperty>()
          .toList();

      return _filterAndRank(parsed, c);
    } on CircuitOpenException {
      return const [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PropertySearchRepository.search error: $e');
      }
      return const [];
    }
  }

  RentalProperty? _safeParse(Map<String, dynamic> data) {
    try {
      return RentalProperty.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  List<RentalProperty> _filterAndRank(
    List<RentalProperty> items,
    PropertySearchCriteria c,
  ) {
    final matched = items.where((p) {
      if (!p.isActive) return false;
      if (c.minPrice != null && p.price < c.minPrice!) return false;
      if (c.maxPrice != null && p.price > c.maxPrice!) return false;
      if (c.minRooms != null && p.rooms < c.minRooms!) return false;
      for (final key in c.amenityKeys) {
        if (!p.featureFlags.isEnabled(key)) return false;
      }
      return true;
    }).toList();

    matched.sort((a, b) => _score(b, c).compareTo(_score(a, c)));
    return matched;
  }

  // Higher = better match. Rewards proximity to budget midpoint, verified
  // listings, and having photos.
  double _score(RentalProperty p, PropertySearchCriteria c) {
    double s = 0;
    if (c.minPrice != null && c.maxPrice != null && c.maxPrice! > c.minPrice!) {
      final mid = (c.minPrice! + c.maxPrice!) / 2.0;
      final span = (c.maxPrice! - c.minPrice!).toDouble();
      s += 1.0 - ((p.price - mid).abs() / span).clamp(0.0, 1.0);
    }
    if (p.isVerifiedListing) s += 0.3;
    if (p.imageUrl.isNotEmpty) s += 0.2;
    return s;
  }
}
