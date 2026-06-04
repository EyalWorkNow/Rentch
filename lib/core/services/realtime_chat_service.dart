import 'dart:async';
import 'dart:math' as math;

import 'package:appwrite/appwrite.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// Shared Appwrite-backed chat service.
//
// Architecture:
//   Messages are stored in an Appwrite collection (tableId = appwriteMessagesTableId).
//   Both tenant and landlord read+write to the SAME collection, filtered by matchId.
//   This is the shared source of truth — no per-user state blob involved.
//
// Collection schema (create in Appwrite console):
//   matchId    : string  (indexed)
//   senderId   : string
//   senderName : string
//   text       : string  (max 2000 chars)
//   createdAt  : string  (ISO-8601, sortable)
//
// Scalability notes:
//   WebSocket subscriptions use exponential backoff with full jitter on reconnect.
//   Max reconnect attempts: [_maxReconnectAttempts] — prevents infinite retry loops
//   that would keep hammering Appwrite during outages.
//
//   Client-side matchId filtering is intentional: Appwrite Realtime does not
//   support attribute-level filters on collection subscriptions. Each active chat
//   screen opens one WebSocket and discards irrelevant events locally.
//   At production scale, migrate to a per-match channel model using Appwrite
//   Functions that publish to dedicated channels.
//
// To enable: ensure APPWRITE_MESSAGES_TABLE_ID is set in --dart-define, OR
//            set AppConfig.appwriteMessagesTableId default to your collection ID.

class RealtimeChatService {
  RealtimeChatService() : _collectionId = AppConfig.appwriteMessagesTableId;

  final String _collectionId;

  Realtime? _realtime;
  RealtimeSubscription? _subscription;
  final _controller = StreamController<ChatMessage>.broadcast();

  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 8;
  static const Duration _reconnectBase = Duration(milliseconds: 500);
  static const Duration _reconnectCap = Duration(minutes: 2);
  static final _rng = math.Random.secure();

  bool get isConfigured => _collectionId.isNotEmpty;
  bool get isActive => _subscription != null && !_controller.isClosed;

  // Live stream of incoming messages for the currently watched match.
  Stream<ChatMessage> get messages => _controller.stream;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  void subscribe(String matchId) {
    if (!isConfigured) {
      if (kDebugMode) {
        debugPrint(
          'RealtimeChatService: no collection configured — '
          'set APPWRITE_MESSAGES_TABLE_ID via --dart-define.',
        );
      }
      return;
    }

    _unsubscribeInternal();
    _realtime = Realtime(client);

    // Appwrite realtime channel for a collection's documents.
    // Even when the REST API uses TablesDB ("tables"/"rows" naming),
    // the realtime events are published on the standard collections path.
    final channel =
        'databases.$appwriteDatabaseId.collections.$_collectionId.documents';

    _subscription = _realtime!.subscribe([channel]);
    _subscription!.stream.listen(
      (event) => _handleEvent(event, matchId),
      onError: (Object error) {
        if (kDebugMode) debugPrint('RealtimeChatService: WS error: $error');
        _subscription = null;
        _scheduleReconnect(matchId);
      },
      onDone: () {
        if (kDebugMode) debugPrint('RealtimeChatService: WS closed');
        _subscription = null;
        // Only reconnect if the controller is still open (not disposed).
        // Closed = user navigated away; don't reconnect.
        if (!_controller.isClosed) {
          _scheduleReconnect(matchId);
        }
      },
    );

    // Reset backoff on a successful subscribe
    _reconnectAttempt = 0;
  }

  void unsubscribe() => _unsubscribeInternal();

  Future<void> dispose() async {
    _unsubscribeInternal();
    if (!_controller.isClosed) await _controller.close();
  }

  // ── Send ─────────────────────────────────────────────────────────────────────

  Future<ChatMessage?> sendMessage({
    required String matchId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    if (!isConfigured) return null;
    try {
      final now = DateTime.now().toUtc();
      final rowId = 'msg_${now.microsecondsSinceEpoch}';

      await RetryPolicy.transient.execute(() => tables.createRow(
            databaseId: appwriteDatabaseId,
            tableId: _collectionId,
            rowId: rowId,
            data: {
              'matchId': matchId,
              'senderId': senderId,
              'senderName': senderName,
              'text': text,
              'createdAt': now.toIso8601String(),
            },
          ));

      return ChatMessage(
        id: rowId,
        sender: senderName,
        text: text,
        createdAt: now,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeChatService.sendMessage error: $e');
      return null;
    }
  }

  // ── Fetch ────────────────────────────────────────────────────────────────────

  Future<List<ChatMessage>> fetchMessages(
    String matchId, {
    int limit = 100,
    String? afterId,
  }) async {
    if (!isConfigured) return const [];
    try {
      final queries = [
        Query.equal('matchId', matchId),
        Query.orderAsc('createdAt'),
        Query.limit(limit),
        if (afterId != null) Query.cursorAfter(afterId),
      ];

      final result = await RetryPolicy.transient.execute(() => tables.listRows(
            databaseId: appwriteDatabaseId,
            tableId: _collectionId,
            queries: queries,
          ));

      return result.rows
          .map((row) => _rowToMessage(row.data))
          .whereType<ChatMessage>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeChatService.fetchMessages error: $e');
      return const [];
    }
  }

  // ── Reconnect with exponential backoff + full jitter ─────────────────────────
  //
  // Full jitter: delay = random(0, min(cap, base * 2^attempt))
  // This prevents all clients reconnecting simultaneously after an outage,
  // which would re-create the thundering-herd problem the backoff is meant to solve.

  void _scheduleReconnect(String matchId) {
    if (_controller.isClosed) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      if (kDebugMode) {
        debugPrint(
          'RealtimeChatService: gave up reconnecting after '
          '$_maxReconnectAttempts attempts',
        );
      }
      return;
    }

    final capMs = _reconnectCap.inMilliseconds;
    final baseMs = _reconnectBase.inMilliseconds;
    final ceiling =
        math.min(capMs.toDouble(), baseMs * math.pow(2, _reconnectAttempt));
    final delayMs = (_rng.nextDouble() * ceiling).toInt();
    final delay = Duration(milliseconds: delayMs);

    _reconnectAttempt++;

    if (kDebugMode) {
      debugPrint(
        'RealtimeChatService: reconnect attempt $_reconnectAttempt in '
        '${delay.inMilliseconds}ms',
      );
    }

    Future.delayed(delay, () {
      if (!_controller.isClosed) subscribe(matchId);
    });
  }

  // ── Internal ─────────────────────────────────────────────────────────────────

  void _handleEvent(RealtimeMessage event, String targetMatchId) {
    final isCreate = event.events.any((e) => e.contains('.create'));
    if (!isCreate) return;

    final msgMatchId = event.payload['matchId'] as String?;
    if (msgMatchId != targetMatchId) return;

    final msg = _rowToMessage(event.payload);
    if (msg != null && !_controller.isClosed) {
      _controller.add(msg);
    }
  }

  ChatMessage? _rowToMessage(Map<String, dynamic> data) {
    try {
      final id = (data[r'$id'] ?? data['id'] ?? '').toString();
      final sender = (data['senderName'] ?? '').toString();
      final text = (data['text'] ?? '').toString();
      final raw = data['createdAt'] as String?;
      final createdAt = raw != null ? DateTime.tryParse(raw) : null;
      if (id.isEmpty || text.isEmpty || createdAt == null) return null;
      return ChatMessage(id: id, sender: sender, text: text, createdAt: createdAt);
    } catch (_) {
      return null;
    }
  }

  void _unsubscribeInternal() {
    try {
      _subscription?.close();
    } catch (_) {}
    _subscription = null;
    _realtime = null;
  }
}
