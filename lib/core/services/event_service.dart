import 'dart:convert';
import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';

// Structured user-event logger.
//
// Why this replaces the app_state blob approach:
//   The previous design persisted all state in a single JSON payload per device.
//   That means every swipe, filter change, and message was a full overwrite of
//   a ~10 KB document.  At 1M users: 1M × 10 KB = 10 GB/write per sync cycle.
//
//   Structured events are append-only rows (~200 bytes each).  They enable:
//     • Real analytics queries ("how many left-swipes on premium listings?")
//     • Funnel analysis without re-reading every device's blob
//     • Replay / undo at the server level
//     • GDPR deletion of specific event types without touching other state
//
// Table schema (create in Appwrite console):
//   userId     : string  (indexed)
//   eventType  : string  (indexed)
//   propertyId : string  (optional, indexed)
//   matchId    : string  (optional)
//   sessionId  : string
//   metadata   : string  (JSON, max 2 KB)
//   createdAt  : string  (ISO-8601, indexed)
//
// Table ID: APPWRITE_EVENTS_TABLE_ID (env var)

enum UserEventType {
  // Discovery
  propertyViewed,
  swipeRight,
  swipeLeft,
  superLike,
  undoSwipe,
  propertySaved,
  propertyUnsaved,
  propertyReported,

  // Matching
  matchCreated,
  contractSent,
  ownerSigned,
  tenantSigned,

  // Chat
  messageSent,

  // Search
  filterChanged,
  searchPerformed,
  areaChanged,

  // Profile & account
  profileUpdated,
  photoUploaded,
  consentGranted,
  roleChanged,

  // Session
  sessionStarted,
  sessionEnded,

  // Property management (landlord)
  propertyAdded,
  propertyUpdated,
  propertyDeleted,
  tourUploaded,
}

class EventService {
  EventService({
    String? tableId,
    String? sessionId,
  })  : _tableId = tableId ?? AppConfig.appwriteEventsTableId,
        _sessionId = sessionId ?? _newSessionId();

  final String _tableId;
  final String _sessionId;
  final _breaker = CircuitBreaker(name: 'appwrite-events');

  // Lazily resolved once per service instance.
  String _userId = '';

  bool get isConfigured =>
      AppConfig.hasAppwriteCoreConfig &&
      AppConfig.appwriteDatabaseId.isNotEmpty &&
      _tableId.isNotEmpty;

  // Set the current user — call after login/registration.
  void setUserId(String userId) => _userId = userId;

  // ── Log ───────────────────────────────────────────────────────────────────────

  // Fire-and-forget: logs an event without blocking the UI.
  // Failures are swallowed — event loss is acceptable; blocking the user is not.
  void log(
    UserEventType type, {
    String? propertyId,
    String? matchId,
    Map<String, dynamic>? metadata,
  }) {
    if (!isConfigured || _userId.isEmpty) return;
    // Run async but don't await — never block callers.
    _writeEvent(
      type: type,
      propertyId: propertyId,
      matchId: matchId,
      metadata: metadata,
    );
  }

  Future<void> _writeEvent({
    required UserEventType type,
    String? propertyId,
    String? matchId,
    Map<String, dynamic>? metadata,
  }) async {
    if (_breaker.isOpen) return;
    try {
      final now = DateTime.now().toUtc();
      final rowId = 'ev_${now.microsecondsSinceEpoch}_'
          '${_rng.nextInt(0xFFFF).toRadixString(16)}';

      final data = <String, dynamic>{
        'userId': _userId,
        'eventType': type.name,
        'sessionId': _sessionId,
        'createdAt': now.toIso8601String(),
        if (propertyId != null && propertyId.isNotEmpty)
          'propertyId': propertyId,
        if (matchId != null && matchId.isNotEmpty) 'matchId': matchId,
        if (metadata != null && metadata.isNotEmpty)
          'metadata': _encodeMetadata(metadata),
      };

      await _breaker.call(
        () => RetryPolicy.none.execute(
          // Don't retry events — a duplicate event is worse than a missing one.
          () => tables.createRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: rowId,
            data: data,
          ),
        ),
      );
    } on CircuitOpenException {
      // Silently drop
    } catch (e) {
      if (kDebugMode) debugPrint('EventService: failed to log ${type.name}: $e');
    }
  }

  String _encodeMetadata(Map<String, dynamic> metadata) {
    try {
      final encoded = jsonEncode(metadata);
      // Cap at 2 KB to avoid oversized rows
      return encoded.length <= 2048 ? encoded : encoded.substring(0, 2048);
    } catch (_) {
      return '{}';
    }
  }

  static final _rng = math.Random.secure();

  static String _newSessionId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _rng.nextInt(0xFFFFFF).toRadixString(16);
    return 'sess_${ts}_$rand';
  }
}

// Singleton shared across the app.  Replace [userId] after each login.
//
// Usage:
//   AppEvents.instance.setUserId(uid);
//   AppEvents.instance.log(UserEventType.swipeRight, propertyId: prop.id);
class AppEvents {
  AppEvents._();
  static final AppEvents instance = AppEvents._();
  final _service = EventService();

  EventService get service => _service;

  void setUserId(String userId) => _service.setUserId(userId);

  void log(
    UserEventType type, {
    String? propertyId,
    String? matchId,
    Map<String, dynamic>? metadata,
  }) =>
      _service.log(
        type,
        propertyId: propertyId,
        matchId: matchId,
        metadata: metadata,
      );
}
