import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';

class PropertyAnalyticsSnapshot {
  const PropertyAnalyticsSnapshot({
    required this.liveViewers,
    required this.likesToday,
    required this.likesTodayDate,
  });

  final int liveViewers;
  final int likesToday;
  final String likesTodayDate;
}

class PropertyAnalyticsRepository {
  PropertyAnalyticsRepository({
    String? viewSessionsTableId,
    String? likesTableId,
  })  : _viewSessionsTableId = viewSessionsTableId ??
            AppConfig.appwritePropertyViewSessionsTableId,
        _likesTableId = likesTableId ?? AppConfig.appwritePropertyLikesTableId;

  final String _viewSessionsTableId;
  final String _likesTableId;
  final _breaker = CircuitBreaker(name: 'appwrite-property-analytics');

  static const Duration activeViewerWindow = Duration(seconds: 45);

  // Cap on rows fetched per count. The shim's `total` is just `rows.length` and
  // it silently drops `greaterThan`/`isNotNull` queries, so counts must be done
  // client-side. This cap bounds the payload while comfortably covering any
  // realistic concurrent-viewer / per-day-like volume for a single property.
  static const int _countFetchLimit = 200;

  bool get isConfigured =>
      AppConfig.hasAppwriteCoreConfig &&
      AppConfig.appwriteDatabaseId.isNotEmpty &&
      _viewSessionsTableId.isNotEmpty &&
      _likesTableId.isNotEmpty;

  Future<PropertyAnalyticsSnapshot?> fetchSnapshot(
    String propertyId, {
    DateTime? now,
  }) async {
    if (!isConfigured || _breaker.isOpen) return null;
    final capturedNow = now ?? DateTime.now();
    final today = _dateKey(capturedNow);
    final cutoff = capturedNow.toUtc().subtract(activeViewerWindow);

    try {
      // The shim honours the `equal` filters but drops `greaterThan` and
      // reports `total` as the returned row count. So fetch the rows matching
      // the equal filters (capped) and re-apply the time window client-side.
      final activeRows = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.listRows(
            databaseId: appwriteDatabaseId,
            tableId: _viewSessionsTableId,
            queries: [
              Query.equal('propertyId', propertyId),
              Query.equal('active', true),
              Query.limit(_countFetchLimit),
            ],
          ),
        ),
      );
      final likeRows = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.listRows(
            databaseId: appwriteDatabaseId,
            tableId: _likesTableId,
            queries: [
              Query.equal('propertyId', propertyId),
              Query.equal('date', today),
              Query.limit(_countFetchLimit),
            ],
          ),
        ),
      );

      final liveViewers = activeRows.rows.where((row) {
        // Guard against rows the backend may not have filtered on `active`.
        if (row.data['active'] == false) return false;
        final lastSeen = _parseUtc(row.data['lastSeenAt']);
        return lastSeen != null && lastSeen.isAfter(cutoff);
      }).length;

      final likesToday = likeRows.rows.where((row) {
        // Re-confirm the day in case the backend ignored the `date` equal.
        return row.data['date']?.toString() == today;
      }).length;

      return PropertyAnalyticsSnapshot(
        liveViewers: liveViewers,
        likesToday: likesToday,
        likesTodayDate: today,
      );
    } on CircuitOpenException {
      return null;
    } catch (error) {
      _log('fetchSnapshot', propertyId, error);
      return null;
    }
  }

  Future<void> startViewSession({
    required String sessionId,
    required String propertyId,
    required String userId,
    required DateTime startedAt,
  }) async {
    if (!isConfigured || _breaker.isOpen) return;
    final nowUtc = startedAt.toUtc().toIso8601String();
    await _upsertViewSession(
      sessionId: sessionId,
      data: {
        'sessionId': sessionId,
        'propertyId': propertyId,
        'userId': userId,
        'startedAt': nowUtc,
        'lastSeenAt': nowUtc,
        'active': true,
        'durationSeconds': 0,
        'photoSwipeCount': 0,
        'currentPhotoIndex': 0,
      },
    );
  }

  Future<void> heartbeatViewSession({
    required String sessionId,
    required DateTime startedAt,
    required int photoSwipeCount,
    required int currentPhotoIndex,
    DateTime? now,
  }) async {
    if (!isConfigured || _breaker.isOpen) return;
    final capturedNow = now ?? DateTime.now();
    await _upsertViewSession(
      sessionId: sessionId,
      data: {
        'lastSeenAt': capturedNow.toUtc().toIso8601String(),
        'active': true,
        'durationSeconds': _durationSeconds(startedAt, capturedNow),
        'photoSwipeCount': photoSwipeCount,
        'currentPhotoIndex': currentPhotoIndex,
      },
    );
  }

  Future<void> endViewSession({
    required String sessionId,
    required DateTime startedAt,
    required int photoSwipeCount,
    required int currentPhotoIndex,
    DateTime? endedAt,
  }) async {
    if (!isConfigured || _breaker.isOpen) return;
    final capturedEndedAt = endedAt ?? DateTime.now();
    await _upsertViewSession(
      sessionId: sessionId,
      data: {
        'lastSeenAt': capturedEndedAt.toUtc().toIso8601String(),
        'endedAt': capturedEndedAt.toUtc().toIso8601String(),
        'active': false,
        'durationSeconds': _durationSeconds(startedAt, capturedEndedAt),
        'photoSwipeCount': photoSwipeCount,
        'currentPhotoIndex': currentPhotoIndex,
      },
    );
  }

  Future<void> recordLike({
    required String propertyId,
    required String userId,
    DateTime? likedAt,
  }) async {
    if (!isConfigured || _breaker.isOpen) return;
    final capturedLikedAt = likedAt ?? DateTime.now();
    final date = _dateKey(capturedLikedAt);
    final rowId = _likeRowId(propertyId, userId, date);

    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.upsertRow(
            databaseId: appwriteDatabaseId,
            tableId: _likesTableId,
            rowId: rowId,
            data: {
              'propertyId': propertyId,
              'userId': userId,
              'date': date,
              'likedAt': capturedLikedAt.toUtc().toIso8601String(),
            },
          ),
        ),
      );
    } on CircuitOpenException {
      return;
    } catch (error) {
      _log('recordLike', propertyId, error);
    }
  }

  Future<void> removeLike({
    required String propertyId,
    required String userId,
    DateTime? likedAt,
  }) async {
    if (!isConfigured || _breaker.isOpen) return;
    final date = _dateKey(likedAt ?? DateTime.now());
    final rowId = _likeRowId(propertyId, userId, date);

    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.deleteRow(
            databaseId: appwriteDatabaseId,
            tableId: _likesTableId,
            rowId: rowId,
          ),
        ),
      );
    } on CircuitOpenException {
      return;
    } catch (error) {
      _log('removeLike', propertyId, error);
    }
  }

  Future<void> _upsertViewSession({
    required String sessionId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.upsertRow(
            databaseId: appwriteDatabaseId,
            tableId: _viewSessionsTableId,
            rowId: _sessionRowId(sessionId),
            data: data,
          ),
        ),
      );
    } on CircuitOpenException {
      return;
    } catch (error) {
      _log('viewSession', sessionId, error);
    }
  }

  String _sessionRowId(String sessionId) {
    return InputSanitizer.sanitizeText(sessionId, maxLength: 64)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _likeRowId(String propertyId, String userId, String date) {
    final raw = 'like_${propertyId}_${userId}_$date';
    final sanitized = InputSanitizer.sanitizeText(raw, maxLength: 64)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (sanitized.isNotEmpty && raw.length <= 64) return sanitized;
    final hash = raw.codeUnits
        .fold<int>(0, (value, code) => ((value * 31) + code) & 0x7fffffff)
        .toRadixString(16);
    final prefix = sanitized.isEmpty
        ? 'like'
        : sanitized.substring(0, math.min(sanitized.length, 48));
    return '${prefix}_$hash';
  }

  int _durationSeconds(DateTime startedAt, DateTime endedAt) {
    final seconds = endedAt.difference(startedAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  DateTime? _parseUtc(Object? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toUtc();
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  void _log(String action, String id, Object error) {
    if (!kDebugMode) return;
    debugPrint('PropertyAnalyticsRepository.$action failed for $id: $error');
  }
}
