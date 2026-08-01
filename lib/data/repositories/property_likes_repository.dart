import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:flutter/foundation.dart';

/// A tenant's "like" on a property, as seen by the landlord.
class PropertyLike {
  const PropertyLike({
    required this.propertyId,
    required this.tenantId,
    required this.tenantName,
    this.tenantPhotoUrl = '',
    this.ownerUserId = '',
    this.introMessage = '',
    this.budgetSnapshot = '',
    this.moveInSnapshot = '',
    this.createdAt,
    this.budgetMax,
    this.rooms,
    this.occupation,
    this.numChildren,
    this.hasPets,
    this.hasCar,
    this.wfh,
    this.household,
    this.lifeStage,
    this.monthlyIncome,
    this.age,
    this.isOleh,
    this.verified,
    this.smoker,
    this.hasGuarantor,
    this.leaseMonths,
    this.incomeProofReady,
    this.workLat,
    this.workLon,
    this.religiousLifestyle,
    this.shabbatObservant,
    this.keepsKosher,
    this.petType,
    this.hostsGuests,
    this.playsInstrument,
  });

  final String propertyId;
  final String tenantId;
  final String tenantName;
  final String tenantPhotoUrl;
  final String ownerUserId;

  /// Optional short note (≤140 chars) the tenant attaches to their like so they
  /// can stand out to the landlord. Empty when not provided (old likes have none).
  final String introMessage;

  /// Optional budget snapshot the tenant chose to share (e.g. "עד ₪6,500").
  final String budgetSnapshot;

  /// Optional move-in snapshot (e.g. "כניסה מיידית"). Empty when not provided.
  final String moveInSnapshot;

  final DateTime? createdAt;

  // ── Structured tenant attribute snapshot ────────────────────────────────────
  // Real tenant attributes captured at like-time so they reach the landlord's
  // candidate deck (and its filters) cross-device. All optional/nullable: old
  // likes carry none, and null means "unknown" (never excludes in the matcher).
  final int? budgetMax;
  final double? rooms;
  final String? occupation;
  final int? numChildren;
  final bool? hasPets;
  final bool? hasCar;
  final bool? wfh;
  final String? household;
  final String? lifeStage;
  final int? monthlyIncome;
  final int? age;
  final bool? isOleh;
  final bool? verified;
  final bool? smoker;
  final bool? hasGuarantor;
  final int? leaseMonths;
  final bool? incomeProofReady;

  /// Tenant's work-location coords, snapshotted so the landlord's commute filter
  /// (מרחק ממקום העבודה) can measure distance to each liked property.
  final double? workLat;
  final double? workLon;

  // Lifestyle / religious deal-breaker snapshot (Israeli market).
  final String? religiousLifestyle;
  final bool? shabbatObservant;
  final bool? keepsKosher;
  final String? petType;
  final bool? hostsGuests;
  final bool? playsInstrument;

  bool get hasIntro =>
      introMessage.isNotEmpty ||
      budgetSnapshot.isNotEmpty ||
      moveInSnapshot.isNotEmpty;

  // ── Defensive parsers: DynamoDB may return numbers as num OR String ──────────
  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static double? _double(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static bool? _bool(Object? v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory PropertyLike.fromRow(Map<String, dynamic> row) {
    DateTime? parseDate(Object? v) =>
        v is String ? DateTime.tryParse(v) : null;
    return PropertyLike(
      propertyId: row['propertyId']?.toString() ?? '',
      tenantId: row['tenantId']?.toString() ?? '',
      tenantName: row['tenantName']?.toString() ?? '',
      tenantPhotoUrl: row['tenantPhotoUrl']?.toString() ?? '',
      ownerUserId: row['ownerUserId']?.toString() ?? '',
      introMessage: row['introMessage']?.toString() ?? '',
      budgetSnapshot: row['budgetSnapshot']?.toString() ?? '',
      moveInSnapshot: row['moveInSnapshot']?.toString() ?? '',
      createdAt: parseDate(row['createdAt']),
      budgetMax: _int(row['budgetMax']),
      rooms: _double(row['rooms']),
      occupation: _str(row['occupation']),
      numChildren: _int(row['numChildren']),
      hasPets: _bool(row['hasPets']),
      hasCar: _bool(row['hasCar']),
      wfh: _bool(row['wfh']),
      household: _str(row['household']),
      lifeStage: _str(row['lifeStage']),
      monthlyIncome: _int(row['monthlyIncome']),
      age: _int(row['age']),
      isOleh: _bool(row['isOleh']),
      verified: _bool(row['verified']),
      smoker: _bool(row['smoker']),
      hasGuarantor: _bool(row['hasGuarantor']),
      leaseMonths: _int(row['leaseMonths']),
      incomeProofReady: _bool(row['incomeProofReady']),
      workLat: _double(row['workLat']),
      workLon: _double(row['workLon']),
      religiousLifestyle: _str(row['religiousLifestyle']),
      shabbatObservant: _bool(row['shabbatObservant']),
      keepsKosher: _bool(row['keepsKosher']),
      petType: _str(row['petType']),
      hostsGuests: _bool(row['hostsGuests']),
      playsInstrument: _bool(row['playsInstrument']),
    );
  }
}

/// Cross-user "likes" on properties. A tenant who likes a property writes a row
/// here (keyed by property + tenant); the property's landlord reads the rows for
/// each of their properties to see who is interested. This is what makes a like
/// from one device visible to the owner on another device.
///
/// The like routes hit the `property_likes` table (verified live). The backend
/// key + table exist regardless of the optional analytics env, so this is gated
/// only on the API gateway being configured.
class PropertyLikesRepository {
  PropertyLikesRepository({AwsApiClient? client})
      : _api = client ?? AwsApiClient.instance;

  final AwsApiClient _api;
  static const String _path = '/property_likes';

  bool get isConfigured => AppConfig.hasAwsCoreConfig;

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static String likeId(String propertyId, String tenantId) =>
      'like_${_safe(propertyId)}_${_safe(tenantId)}';

  /// Max length of the optional [introMessage] note. Enforced here so a long
  /// note never reaches the backend even if a caller forgets to clamp.
  static const int introMessageMaxLength = 140;

  Future<void> addLike({
    required String propertyId,
    required String ownerUserId,
    required String tenantId,
    required String tenantName,
    String tenantPhotoUrl = '',
    String introMessage = '',
    String budgetSnapshot = '',
    String moveInSnapshot = '',
    DateTime? at,
    // Structured tenant attribute snapshot — each written ONLY when non-null so
    // old-style payloads (no profile in scope) stay byte-identical.
    int? budgetMax,
    double? rooms,
    String? occupation,
    int? numChildren,
    bool? hasPets,
    bool? hasCar,
    bool? wfh,
    String? household,
    String? lifeStage,
    int? monthlyIncome,
    int? age,
    bool? isOleh,
    bool? verified,
    bool? smoker,
    bool? hasGuarantor,
    int? leaseMonths,
    bool? incomeProofReady,
    double? workLat,
    double? workLon,
    String? religiousLifestyle,
    bool? shabbatObservant,
    bool? keepsKosher,
    String? petType,
    bool? hostsGuests,
    bool? playsInstrument,
  }) async {
    if (!isConfigured || propertyId.isEmpty || tenantId.isEmpty) return;
    try {
      await _api.post(
        _path,
        buildAddLikeBody(
          propertyId: propertyId,
          ownerUserId: ownerUserId,
          tenantId: tenantId,
          tenantName: tenantName,
          tenantPhotoUrl: tenantPhotoUrl,
          introMessage: introMessage,
          budgetSnapshot: budgetSnapshot,
          moveInSnapshot: moveInSnapshot,
          at: at,
          budgetMax: budgetMax,
          rooms: rooms,
          occupation: occupation,
          numChildren: numChildren,
          hasPets: hasPets,
          hasCar: hasCar,
          wfh: wfh,
          household: household,
          lifeStage: lifeStage,
          monthlyIncome: monthlyIncome,
          age: age,
          isOleh: isOleh,
          verified: verified,
          smoker: smoker,
          hasGuarantor: hasGuarantor,
          leaseMonths: leaseMonths,
          incomeProofReady: incomeProofReady,
          workLat: workLat,
          workLon: workLon,
          religiousLifestyle: religiousLifestyle,
          shabbatObservant: shabbatObservant,
          keepsKosher: keepsKosher,
          petType: petType,
          hostsGuests: hostsGuests,
          playsInstrument: playsInstrument,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('PropertyLikesRepository.addLike failed: $e');
    }
  }

  /// Builds the exact JSON body [addLike] posts. Pure and side-effect-free so the
  /// "only send optional fields when present" contract is unit-testable without a
  /// live gateway. Each optional attribute is emitted ONLY when non-null (and
  /// non-blank for strings), so old-style payloads stay byte-identical.
  @visibleForTesting
  static Map<String, dynamic> buildAddLikeBody({
    required String propertyId,
    required String ownerUserId,
    required String tenantId,
    required String tenantName,
    String tenantPhotoUrl = '',
    String introMessage = '',
    String budgetSnapshot = '',
    String moveInSnapshot = '',
    DateTime? at,
    int? budgetMax,
    double? rooms,
    String? occupation,
    int? numChildren,
    bool? hasPets,
    bool? hasCar,
    bool? wfh,
    String? household,
    String? lifeStage,
    int? monthlyIncome,
    int? age,
    bool? isOleh,
    bool? verified,
    bool? smoker,
    bool? hasGuarantor,
    int? leaseMonths,
    bool? incomeProofReady,
    double? workLat,
    double? workLon,
    String? religiousLifestyle,
    bool? shabbatObservant,
    bool? keepsKosher,
    String? petType,
    bool? hostsGuests,
    bool? playsInstrument,
  }) {
    final note = introMessage.trim();
    final clampedNote = note.length > introMessageMaxLength
        ? note.substring(0, introMessageMaxLength)
        : note;
    return {
      'id': likeId(propertyId, tenantId),
      'propertyId': propertyId,
      'ownerUserId': ownerUserId,
      'tenantId': tenantId,
      'tenantName': tenantName,
      'tenantPhotoUrl': tenantPhotoUrl,
      // Only send the optional fields when present, so the payload stays
      // identical to old likes when no note is attached.
      if (clampedNote.isNotEmpty) 'introMessage': clampedNote,
      if (budgetSnapshot.trim().isNotEmpty)
        'budgetSnapshot': budgetSnapshot.trim(),
      if (moveInSnapshot.trim().isNotEmpty)
        'moveInSnapshot': moveInSnapshot.trim(),
      if (budgetMax != null) 'budgetMax': budgetMax,
      if (rooms != null) 'rooms': rooms,
      if (occupation != null && occupation.trim().isNotEmpty)
        'occupation': occupation.trim(),
      if (numChildren != null) 'numChildren': numChildren,
      if (hasPets != null) 'hasPets': hasPets,
      if (hasCar != null) 'hasCar': hasCar,
      if (wfh != null) 'wfh': wfh,
      if (household != null && household.trim().isNotEmpty)
        'household': household.trim(),
      if (lifeStage != null && lifeStage.trim().isNotEmpty)
        'lifeStage': lifeStage.trim(),
      if (monthlyIncome != null) 'monthlyIncome': monthlyIncome,
      if (age != null) 'age': age,
      if (isOleh != null) 'isOleh': isOleh,
      if (verified != null) 'verified': verified,
      if (smoker != null) 'smoker': smoker,
      if (hasGuarantor != null) 'hasGuarantor': hasGuarantor,
      if (leaseMonths != null) 'leaseMonths': leaseMonths,
      if (incomeProofReady != null) 'incomeProofReady': incomeProofReady,
      if (workLat != null) 'workLat': workLat,
      if (workLon != null) 'workLon': workLon,
      if (religiousLifestyle != null && religiousLifestyle.trim().isNotEmpty)
        'religiousLifestyle': religiousLifestyle.trim(),
      if (shabbatObservant != null) 'shabbatObservant': shabbatObservant,
      if (keepsKosher != null) 'keepsKosher': keepsKosher,
      if (petType != null && petType.trim().isNotEmpty) 'petType': petType.trim(),
      if (hostsGuests != null) 'hostsGuests': hostsGuests,
      if (playsInstrument != null) 'playsInstrument': playsInstrument,
      'createdAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  Future<void> removeLike({
    required String propertyId,
    required String tenantId,
  }) async {
    if (!isConfigured || propertyId.isEmpty || tenantId.isEmpty) return;
    try {
      await _api.delete('$_path/${likeId(propertyId, tenantId)}');
    } catch (e) {
      if (kDebugMode) debugPrint('PropertyLikesRepository.removeLike failed: $e');
    }
  }

  // ── Public engagement counts (views + likes) ────────────────────────────────

  /// Records that [viewerId] viewed [propertyId]. Idempotent per viewer, so the
  /// count reflects DISTINCT viewers.
  Future<void> recordView({
    required String propertyId,
    required String viewerId,
  }) async {
    if (!isConfigured || propertyId.isEmpty || viewerId.isEmpty) return;
    try {
      await _api.post('/property_views', {
        'id': 'view_${_safe(propertyId)}_${_safe(viewerId)}',
        'propertyId': propertyId,
        'userId': viewerId,
        'viewedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('PropertyLikesRepository.recordView failed: $e');
    }
  }

  /// Returns null on error (vs 0 for a real empty count) so callers don't
  /// clobber real persisted counts with a 0 on a transient failure.
  Future<int?> viewCount(String propertyId) => _count('/property_views', propertyId);
  Future<int?> likeCount(String propertyId) => _count('/property_likes', propertyId);

  Future<int?> _count(String path, String propertyId) async {
    if (!isConfigured || propertyId.isEmpty) return 0;
    try {
      final res = await _api.get('$path/count', query: {'propertyId': propertyId});
      final c = res['count'];
      return c is num ? c.toInt() : 0;
    } catch (e) {
      // Signal error as null (not 0) so callers skip the update instead of
      // persisting a fake zero over the real count.
      debugPrint('PropertyLikesRepository._count($path) error (returning null): $e');
      return null;
    }
  }

  /// All tenants who liked [propertyId]. Returns null on error (vs [] for a
  /// real "no likes yet") so callers don't drop the property on a transient
  /// failure.
  Future<List<PropertyLike>?> likesForProperty(String propertyId) async {
    if (!isConfigured || propertyId.isEmpty) return const [];
    try {
      final res = await _api.get(_path, query: {'propertyId': propertyId});
      final items = res['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((e) => PropertyLike.fromRow(Map<String, dynamic>.from(e)))
          .where((l) => l.tenantId.isNotEmpty)
          .toList();
    } catch (e) {
      // Signal error as null (not []) so callers keep prior data.
      debugPrint('PropertyLikesRepository.likesForProperty error (returning null): $e');
      return null;
    }
  }
}
