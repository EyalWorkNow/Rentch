import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/core/services/cache_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// Writes and reads discoverable user profiles in the Appwrite `users` table.
//
// Why this matters:
//   MatchService returns only demo profiles because nothing actually writes
//   to the users table when a user registers.  This repository is the write
//   path — call [upsertProfile] on every registration and every profile update
//   so live users appear in each other's discovery feeds.
//
// Table ID: APPWRITE_USERS_TABLE_ID (env var)
// Row ID  : Firebase UID — same ID stored in TenantProfile.id
//
// Visibility:
//   A row is queryable in discovery only when [discoverable] = true.
//   Set it to false on suspension, deletion, or user opt-out.

class UserRepository {
  UserRepository({String? tableId})
      : _tableId = tableId ?? AppConfig.appwriteUsersTableId;

  final String _tableId;
  final _breaker = CircuitBreaker(name: 'appwrite-users-write');

  bool get isConfigured =>
      AppConfig.hasAppwriteCoreConfig &&
      AppConfig.appwriteDatabaseId.isNotEmpty &&
      _tableId.isNotEmpty;

  // ── Write ─────────────────────────────────────────────────────────────────────

  // Called on registration and on every profile update.
  Future<bool> upsertProfile(
    TenantProfile profile, {
    String role = 'tenant',
    bool discoverable = true,
  }) async {
    if (!isConfigured) return false;
    if (profile.id.trim().isEmpty) return false;

    final sanitizedName = InputSanitizer.sanitizeText(
      profile.name,
      maxLength: 100,
    );
    if (sanitizedName.isEmpty) return false;

    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.upsertRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: _rowId(profile.id),
            data: _profileToRow(
              profile,
              sanitizedName: sanitizedName,
              role: role,
              discoverable: discoverable,
            ),
          ),
        ),
      );
      AppCache.instance.profiles.invalidate(profile.id);
      return true;
    } on CircuitOpenException {
      return false;
    } catch (e) {
      _log('upsert', profile.id, e);
      return false;
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────────

  /// Loads a user's profile from the backend by Firebase UID. Returns null if
  /// not configured, not found, or on error. Used on login so a returning user
  /// gets their saved profile instead of a fresh local default.
  Future<TenantProfile?> getProfile(String userId) async {
    if (!isConfigured || userId.trim().isEmpty) return null;
    try {
      final row = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.getRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: _rowId(userId),
          ),
        ),
      );
      final data = row.data;
      if (data.isEmpty) return null;
      final hasIdentity = (data['name'] ?? data['userId']) != null;
      if (!hasIdentity) return null;

      final photoUrlsRaw = (data['photoUrls'] ?? '').toString();
      final photos = photoUrlsRaw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final single = (data['photoUrl'] ?? '').toString().trim();
      if (photos.isEmpty && single.isNotEmpty) photos.add(single);

      return TenantProfile(
        id: userId,
        name: (data['name'] ?? '').toString(),
        bio: (data['bio'] ?? '').toString(),
        photoUrls: photos,
        budgetMax: _asInt(data['budgetMax']),
        desiredRooms: _asDouble(data['desiredRooms']),
        moveInWindow: (data['moveInWindow'] ?? '').toString(),
        importantDetails: const [],
      );
    } on CircuitOpenException {
      return null;
    } catch (e) {
      _log('getProfile', userId, e);
      return null;
    }
  }

  int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _asDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  // Hard-deletes the profile row — call on account deletion (GDPR).
  Future<bool> deleteProfile(String userId) async {
    if (!isConfigured || userId.trim().isEmpty) return false;
    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.deleteRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: _rowId(userId),
          ),
        ),
      );
      AppCache.instance.profiles.invalidate(userId);
      return true;
    } on CircuitOpenException {
      return false;
    } catch (e) {
      _log('delete', userId, e);
      return false;
    }
  }

  // Soft-hides from discovery without deleting data.
  Future<bool> setDiscoverable(String userId, {required bool discoverable}) async {
    if (!isConfigured || userId.trim().isEmpty) return false;
    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.upsertRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: _rowId(userId),
            data: {
              'discoverable': discoverable,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            },
          ),
        ),
      );
      AppCache.instance.profiles.invalidate(userId);
      return true;
    } on CircuitOpenException {
      return false;
    } catch (e) {
      _log('setDiscoverable', userId, e);
      return false;
    }
  }

  // ── Row mapping ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _profileToRow(
    TenantProfile profile, {
    required String sanitizedName,
    required String role,
    required bool discoverable,
  }) {
    return {
      'userId': profile.id,
      'name': sanitizedName,
      'bio': InputSanitizer.sanitizeText(profile.bio, maxLength: 500),
      'photoUrl': _safeUrl(profile.photoUrl),
      // Store all photo URLs as comma-separated (Appwrite Tables has no array type).
      'photoUrls': profile.photoUrls
          .map(_safeUrl)
          .where((u) => u.isNotEmpty)
          .take(6)
          .join(','),
      'budgetMax': profile.budgetMax,
      'desiredRooms': profile.desiredRooms,
      'moveInWindow': InputSanitizer.sanitizeText(
        profile.moveInWindow,
        maxLength: 100,
      ),
      'role': role,
      'discoverable': discoverable,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String _safeUrl(String url) =>
      url.isNotEmpty ? (InputSanitizer.sanitizeMediaUrl(url) ?? '') : '';

  String _rowId(String userId) {
    final sanitized =
        InputSanitizer.sanitizeText(userId, maxLength: 36)
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? ID.unique() : sanitized;
  }

  void _log(String action, String userId, Object error) {
    if (!kDebugMode) return;
    debugPrint('UserRepository.$action failed for $userId: $error');
  }
}
