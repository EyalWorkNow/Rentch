import 'dart:async';
import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// Shared AWS-backed chat service.
//
// Messages are stored in DynamoDB via the API Gateway (tableId = appwriteMessagesTableId).
// Both tenant and landlord read+write to the SAME table, filtered by matchId.
//
// Real-time: WebSocket subscriptions are not available with the AWS HTTP client.
// Instead, subscribe() starts a polling timer that emits new messages to the stream.
// Poll interval: 3 seconds while active.

class RealtimeChatService {
  RealtimeChatService() : _collectionId = AppConfig.appwriteMessagesTableId;

  final String _collectionId;

  Timer? _pollTimer;
  String? _watchedMatchId;
  String? _lastSeenId;
  final _controller = StreamController<ChatMessage>.broadcast();

  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 8;
  static const Duration _reconnectBase = Duration(milliseconds: 500);
  static const Duration _reconnectCap = Duration(minutes: 2);
  static const Duration _pollInterval = Duration(seconds: 3);
  static final _rng = math.Random.secure();

  bool get isConfigured => _collectionId.isNotEmpty;
  bool get isActive => _pollTimer != null && !_controller.isClosed;

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

    _stopPoll();
    _watchedMatchId = matchId;
    _lastSeenId = null;
    _reconnectAttempt = 0;

    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void unsubscribe() => _stopPoll();

  Future<void> dispose() async {
    _stopPoll();
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
      final queries = <String>[
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

  // ── Polling ──────────────────────────────────────────────────────────────────

  Future<void> _poll() async {
    final matchId = _watchedMatchId;
    if (matchId == null || _controller.isClosed) return;
    try {
      final msgs = await fetchMessages(matchId, afterId: _lastSeenId);
      for (final msg in msgs) {
        if (!_controller.isClosed) {
          _controller.add(msg);
          _lastSeenId = msg.id;
        }
      }
      _reconnectAttempt = 0;
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeChatService._poll error: $e');
      _scheduleReconnect(matchId);
    }
  }

  // ── Reconnect with exponential backoff + full jitter ─────────────────────────

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

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _watchedMatchId = null;
  }
}
