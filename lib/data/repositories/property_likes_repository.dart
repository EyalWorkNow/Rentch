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

  bool get hasIntro =>
      introMessage.isNotEmpty ||
      budgetSnapshot.isNotEmpty ||
      moveInSnapshot.isNotEmpty;

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
  }) async {
    if (!isConfigured || propertyId.isEmpty || tenantId.isEmpty) return;
    final id = likeId(propertyId, tenantId);
    final note = introMessage.trim();
    final clampedNote = note.length > introMessageMaxLength
        ? note.substring(0, introMessageMaxLength)
        : note;
    try {
      await _api.post(_path, {
        'id': id,
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
        'createdAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('PropertyLikesRepository.addLike failed: $e');
    }
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

  Future<int> viewCount(String propertyId) => _count('/property_views', propertyId);
  Future<int> likeCount(String propertyId) => _count('/property_likes', propertyId);

  Future<int> _count(String path, String propertyId) async {
    if (!isConfigured || propertyId.isEmpty) return 0;
    try {
      final res = await _api.get('$path/count', query: {'propertyId': propertyId});
      final c = res['count'];
      return c is num ? c.toInt() : 0;
    } catch (e) {
      // ponytail: callers can't tell error-from-empty here — a 401/404/500
      // returns 0 just like a real zero count. Log the real error distinctly so
      // failures are observable. Upgrade path: surface an error state to callers.
      debugPrint('PropertyLikesRepository._count($path) error (returning 0): $e');
      return 0;
    }
  }

  /// All tenants who liked [propertyId].
  Future<List<PropertyLike>> likesForProperty(String propertyId) async {
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
      // ponytail: callers can't tell error-from-empty here — a 401/404/500
      // returns [] just like "no likes yet". Log the real error distinctly so
      // failures are observable. Upgrade path: surface an error state to callers.
      debugPrint('PropertyLikesRepository.likesForProperty error (returning []): $e');
      return const [];
    }
  }
}
