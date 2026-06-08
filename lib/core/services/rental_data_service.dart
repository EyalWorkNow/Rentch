import 'dart:convert';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/core/services/cache_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

// Result type for paginated property loading.
class PropertyPage {
  const PropertyPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });
  final List<RentalProperty> items;
  final bool hasMore;
  final String? nextCursor;
  bool get isEmpty => items.isEmpty;
}

class RentalDataService {
  static const String assetPath = 'assets/data/proxy_listings.json';

  // One circuit breaker shared across all Appwrite property calls.
  final _breaker = CircuitBreaker(name: 'appwrite-properties');

  // ── Public API ────────────────────────────────────────────────────────────────

  // Loads the first page of listings.
  // Falls back to the bundled JSON asset when Appwrite is unavailable.
  Future<PropertyPage> loadFirstPage({String areaId = 'all_israel'}) async {
    final remote = await _loadPage(offset: 0, areaId: areaId);
    if (remote != null) return remote;

    // Asset fallback: return at most [AppConfig.propertyPageSize] items so
    // the initial load is bounded even if the JSON file is large.
    final all = await _loadAssetListings();
    final capped = all.take(AppConfig.propertyPageSize).toList();
    return PropertyPage(items: capped, hasMore: all.length > capped.length);
  }

  // Loads subsequent pages. Call when the swipe deck runs low.
  Future<PropertyPage> loadPage({
    required int offset,
    String? cursor,
    String areaId = 'all_israel',
  }) async {
    final remote = await _loadPage(
      offset: offset,
      cursor: cursor,
      areaId: areaId,
    );
    if (remote != null) return remote;

    // Asset fallback for subsequent pages
    final all = await _loadAssetListings();
    final end = (offset + AppConfig.propertyPageSize).clamp(0, all.length);
    if (offset >= all.length) {
      return const PropertyPage(items: [], hasMore: false);
    }
    return PropertyPage(
      items: all.sublist(offset, end),
      hasMore: end < all.length,
    );
  }

  // ── Remote loading ────────────────────────────────────────────────────────────

  Future<PropertyPage?> _loadPage({
    required int offset,
    String? cursor,
    required String areaId,
  }) async {
    if (!AppConfig.canUseProperties) return null;
    if (_breaker.isOpen) return null;

    final cacheKey = '$areaId:${cursor ?? offset}';
    final cached = AppCache.instance.propertyPages.get(cacheKey);
    if (cached != null) {
      return PropertyPage(
        items: cached
            .map((row) => _propertyFromRow(row))
            .where((p) => p.id.trim().isNotEmpty)
            .toList(),
        hasMore: false,
      );
    }

    try {
      final query = <String, String>{
        'status': 'active',
        'limit': AppConfig.propertyPageSize.toString(),
      };
      if (cursor != null && cursor.isNotEmpty) {
        query['lastKey'] = cursor;
      }

      final payload = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => aws.get(
            '/${AppConfig.appwritePropertiesTableId}',
            query: query,
          ),
        ),
      );

      final rows = payload['items'] ?? payload['rows'];
      if (rows is! List) return null;

      final rawRows = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      AppCache.instance.propertyPages.put(cacheKey, rawRows);

      final items = rawRows
          .map((row) => _propertyFromRow(row))
          .where((p) => p.id.trim().isNotEmpty)
          .toList();

      final nextCursor = payload['lastKey']?.toString();
      final hasMore = payload['hasMore'] == true &&
          nextCursor != null &&
          nextCursor.isNotEmpty;

      return PropertyPage(
        items: items,
        hasMore: hasMore,
        nextCursor: hasMore ? nextCursor : null,
      );
    } on CircuitOpenException {
      return null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('RentalDataService: remote page load failed: $error');
      }
      return null;
    }
  }

  // ── Asset fallback ────────────────────────────────────────────────────────────

  List<RentalProperty>? _assetCache;

  Future<List<RentalProperty>> _loadAssetListings() async {
    if (_assetCache != null) return _assetCache!;
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    _assetCache = decoded
        .map((item) =>
            RentalProperty.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    return _assetCache!;
  }

  // ── Row mapping ───────────────────────────────────────────────────────────────

  RentalProperty _propertyFromRow(Map<String, dynamic> data) {
    final media = _decodeMedia(data['media']);
    final virtualTour = _decodeVirtualTour(data);
    final features = _decodeJsonValue(data['features']);
    final featureLabels = _decodeStringList(data['featureLabels']);
    return RentalProperty.fromJson({
      'id': data['propertyId'] ?? '',
      'sourceUrl': data['sourceUrl'] ?? data['url'] ?? '',
      'ownerUserId': data['ownerUserId'] ?? '',
      'price': _asInt(data['price']),
      'rooms': _asDouble(data['rooms']),
      'sizeM2': _asInt(data['sizeM2']),
      'floor': data['floor']?.toString() ?? '',
      'totalFloors': data['totalFloors']?.toString() ?? '',
      'city': data['city']?.toString() ?? '',
      'neighborhood': data['neighborhood']?.toString() ?? '',
      'street': data['street']?.toString() ?? '',
      'streetNumber': _asInt(data['streetNumber'], defaultValue: -1),
      'lat': _asDouble(data['lat']),
      'lon': _asDouble(data['lon']),
      'propertyType': data['propertyType']?.toString() ?? 'דירה',
      'entryDate': data['entryDate']?.toString() ?? '',
      'condition': data['condition']?.toString() ?? '',
      'ownerName': data['ownerName']?.toString() ?? 'בעל הנכס',
      'agencyListing': _asBool(data['agencyListing']),
      'features': features,
      'featureLabels': featureLabels,
      'media': media,
      'imageUrls': media
          .where((item) => item['type'] == 'image')
          .map((item) => item['url'] as String)
          .toList(),
      'videoUrls': media
          .where((item) => item['type'] == 'video')
          .map((item) => item['url'] as String)
          .toList(),
      'transactionType': data['transactionType']?.toString() ?? 'rent',
      'model3d': _decodeJsonMap(data['model3d']),
      'legal': _decodeJsonMap(data['legal']),
      'priceHistory': _decodeJsonList(data['priceHistory']),
      'marketSignals': _decodeJsonMap(data['marketSignals']),
      'verification': _decodeJsonMap(data['verification']),
      'verifiedListing': _asBool(data['verifiedListing']),
      'verificationMethod': data['verificationMethod']?.toString() ?? '',
      'verificationVideoUrl': data['verificationVideoUrl']?.toString() ?? '',
      'verifiedAt': data['verifiedAt'],
      'createdAt': data['createdAt'] ?? data[r'$createdAt'],
      if (virtualTour != null) 'virtualTour': virtualTour,
    });
  }

  List<String> _decodeStringList(Object? rawValue) {
    if (rawValue is List) {
      return rawValue.whereType<String>().toList();
    }
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {}
    return const [];
  }

  List<dynamic> _decodeJsonList(Object? rawValue) {
    if (rawValue is List) return rawValue;
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(rawValue);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _decodeJsonMap(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) return rawValue;
    if (rawValue is Map) return Map<String, dynamic>.from(rawValue);
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Object? _decodeJsonValue(Object? rawValue) {
    if (rawValue is Map || rawValue is List) return rawValue;
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(rawValue);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _decodeMedia(Object? rawValue) {
    if (rawValue is List) {
      return rawValue
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Map<String, dynamic>? _decodeVirtualTour(Map<String, dynamic> data) {
    final raw = data['virtualTour'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final viewerUrl = data['tourViewerUrl']?.toString().trim() ?? '';
    final status = data['tourStatus']?.toString().trim() ?? '';
    if (viewerUrl.isEmpty && status.isEmpty) return null;
    return {
      'id': data['tourId']?.toString() ?? data['propertyId']?.toString() ?? '',
      'provider': data['tourProvider']?.toString() ?? 'unknown',
      'status': status.isEmpty ? 'ready' : status,
      'viewerUrl': viewerUrl,
      'downloadUrl': data['tourDownloadUrl']?.toString() ?? '',
      'previewImageUrl': data['tourPreviewImageUrl']?.toString() ?? '',
      'format': data['tourFormat']?.toString() ?? '',
      'updatedAt': data['updatedAt']?.toString(),
    };
  }

  int _asInt(Object? value, {int defaultValue = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? defaultValue;
  }

  double _asDouble(Object? value, {double defaultValue = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? defaultValue;
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  // ── Scaffolding helpers (unchanged — used by DatingProvider) ─────────────────

  TenantProfile createDefaultTenantProfile() {
    return const TenantProfile(
      id: 'tenant-local',
      name: 'נועה לוי',
      bio:
          'מחפשת דירה שקטה ומוארת במרכז, עדיפות לבניין עם מעלית ומרחב עבודה נוח. עובדת בהייטק, שוכרת מסודרת, כניסה גמישה.',
      photoUrls: [
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
        'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
      ],
      budgetMax: 9000,
      desiredRooms: 2.5,
      moveInWindow: 'כניסה תוך 60 יום',
      importantDetails: [
        'ערבות בנקאית מוכנה',
        'ללא חיות מחמד',
        'עבודה קבועה',
        'עדיפות לחניה',
      ],
    );
  }

  List<AppReview> createTenantReviews() {
    return const [
      AppReview(
        id: 'tenant-review-1',
        authorName: 'מיכל, בעלת דירה קודמת',
        rating: 5,
        text: 'שוכרת מסודרת, תקשורת ברורה ותשלומים בזמן.',
      ),
      AppReview(
        id: 'tenant-review-2',
        authorName: 'אורן, שותף לשעבר',
        rating: 4,
        text: 'נעימה, שומרת על דירה נקייה ומכבדת שכנים.',
      ),
    ];
  }

  List<AppReview> createPropertyReviews(RentalProperty property) {
    final area =
        property.neighborhood.isEmpty ? property.city : property.neighborhood;
    return [
      AppReview(
        id: '${property.id}-review-1',
        authorName: 'שוכר קודם',
        rating: property.features.contains('מעלית') ? 5 : 4,
        text:
            'הדירה באזור $area, התחזוקה הייתה טובה והתקשורת עם בעל הנכס הייתה זמינה.',
      ),
    ];
  }

  List<SearchArea> createSearchAreas() {
    return const [
      SearchArea(
        id: 'all_israel',
        name: 'כל הארץ',
        center: LatLng(32.07, 34.87),
        polygon: [
          LatLng(31.65, 34.50),
          LatLng(31.65, 35.30),
          LatLng(32.50, 35.30),
          LatLng(32.50, 34.50),
        ],
      ),
      SearchArea(
        id: 'central_tel_aviv',
        name: 'תל אביב מרכז',
        center: LatLng(32.075, 34.785),
        polygon: [
          LatLng(32.048, 34.752),
          LatLng(32.063, 34.747),
          LatLng(32.085, 34.749),
          LatLng(32.106, 34.754),
          LatLng(32.120, 34.763),
          LatLng(32.128, 34.780),
          LatLng(32.125, 34.810),
          LatLng(32.118, 34.830),
          LatLng(32.100, 34.838),
          LatLng(32.075, 34.836),
          LatLng(32.055, 34.831),
          LatLng(32.043, 34.816),
          LatLng(32.040, 34.795),
          LatLng(32.044, 34.771),
        ],
      ),
      SearchArea(
        id: 'gush_dan',
        name: 'גוש דן',
        center: LatLng(32.065, 34.805),
        polygon: [
          LatLng(31.994, 34.745),
          LatLng(32.018, 34.737),
          LatLng(32.048, 34.735),
          LatLng(32.085, 34.738),
          LatLng(32.120, 34.743),
          LatLng(32.140, 34.758),
          LatLng(32.148, 34.786),
          LatLng(32.145, 34.820),
          LatLng(32.138, 34.855),
          LatLng(32.118, 34.872),
          LatLng(32.080, 34.876),
          LatLng(32.040, 34.872),
          LatLng(32.005, 34.860),
          LatLng(31.990, 34.838),
          LatLng(31.988, 34.805),
          LatLng(31.990, 34.773),
        ],
      ),
      SearchArea(
        id: 'hasharon',
        name: 'השרון',
        center: LatLng(32.220, 34.870),
        polygon: [
          LatLng(32.118, 34.775),
          LatLng(32.140, 34.758),
          LatLng(32.165, 34.757),
          LatLng(32.200, 34.780),
          LatLng(32.250, 34.805),
          LatLng(32.340, 34.840),
          LatLng(32.360, 34.870),
          LatLng(32.350, 34.920),
          LatLng(32.310, 34.940),
          LatLng(32.260, 34.930),
          LatLng(32.210, 34.920),
          LatLng(32.170, 34.910),
          LatLng(32.140, 34.890),
          LatLng(32.120, 34.860),
          LatLng(32.115, 34.820),
        ],
      ),
      SearchArea(
        id: 'south_center',
        name: 'מרכז-דרום',
        center: LatLng(31.90, 34.90),
        polygon: [
          LatLng(31.75, 34.70),
          LatLng(31.75, 35.10),
          LatLng(32.00, 35.10),
          LatLng(32.00, 34.70),
        ],
      ),
    ];
  }
}
