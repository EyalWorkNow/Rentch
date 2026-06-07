import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// AWS-backed chat service with REAL-TIME WebSocket delivery.
//
// Send path:    POST /messages (REST) → DynamoDB
// Receive path: DynamoDB stream → broadcaster Lambda → WebSocket push → here
//
// subscribe(matchId):
//   1. Opens a WebSocket to API Gateway with the Firebase ID token as ?token=…
//   2. Sends {"action":"subscribe","matchId":…} so the server routes this
//      match's messages to this connection.
//   3. Emits each incoming message to [messages].
//
// If the WebSocket can't connect (offline, endpoint unset), it falls back to
// 3-second HTTP polling so chat still works, just not instantly.

class RealtimeChatService {
  RealtimeChatService() : _collectionId = AppConfig.appwriteMessagesTableId;

  final String _collectionId;

  WebSocket? _ws;
  StreamSubscription? _wsSub;
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
  bool get isActive =>
      (_ws != null || _pollTimer != null) && !_controller.isClosed;

  Stream<ChatMessage> get messages => _controller.stream;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  void subscribe(String matchId) {
    if (!isConfigured) {
      if (kDebugMode) debugPrint('RealtimeChatService: messages table not set.');
      return;
    }
    _teardownTransport();
    _watchedMatchId = matchId;
    _lastSeenId = null;
    _reconnectAttempt = 0;

    if (AppConfig.hasWebSocket) {
      unawaited(_connectWebSocket(matchId));
    } else {
      _startPolling();
    }
  }

  void unsubscribe() => _teardownTransport();

  Future<void> dispose() async {
    _teardownTransport();
    if (!_controller.isClosed) await _controller.close();
  }

  // ── WebSocket (real-time) ──────────────────────────────────────────────────

  Future<void> _connectWebSocket(String matchId) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) debugPrint('RealtimeChatService: no Firebase token → polling');
        _startPolling();
        return;
      }

      final url = '${AppConfig.awsWebSocketUrl}?token=${Uri.encodeComponent(token)}';
      final ws = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 10));
      if (_watchedMatchId != matchId || _controller.isClosed) {
        // Subscription changed/closed while connecting.
        await ws.close();
        return;
      }

      _ws = ws;
      _reconnectAttempt = 0;
      ws.add(jsonEncode({'action': 'subscribe', 'matchId': matchId}));
      if (kDebugMode) debugPrint('RealtimeChatService: WS connected for $matchId');

      _wsSub = ws.listen(
        (data) => _onWsData(data, matchId),
        onError: (Object e) {
          if (kDebugMode) debugPrint('RealtimeChatService: WS error $e');
          _scheduleReconnect(matchId);
        },
        onDone: () {
          if (kDebugMode) debugPrint('RealtimeChatService: WS closed');
          if (!_controller.isClosed && _watchedMatchId == matchId) {
            _scheduleReconnect(matchId);
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeChatService: WS connect failed ($e) → polling');
      _startPolling(); // graceful fallback
    }
  }

  void _onWsData(dynamic data, String matchId) {
    try {
      final decoded = jsonDecode(data is String ? data : utf8.decode(data));
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      if ((map['matchId'] ?? '') != matchId) return;
      final msg = _rowToMessage(map);
      if (msg != null && !_controller.isClosed) {
        _lastSeenId = msg.id;
        _controller.add(msg);
      }
    } catch (_) {/* ignore malformed frames */}
  }

  // ── Polling fallback ───────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

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
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeChatService._poll error: $e');
    }
  }

  // ── Send (REST) ────────────────────────────────────────────────────────────

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
      return ChatMessage(id: rowId, sender: senderName, text: text, createdAt: now);
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeChatService.sendMessage error: $e');
      return null;
    }
  }

  // ── Fetch history (REST) ───────────────────────────────────────────────────

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

  // ── Reconnect with exponential backoff + full jitter ───────────────────────

  void _scheduleReconnect(String matchId) {
    _ws = null;
    _wsSub?.cancel();
    _wsSub = null;
    if (_controller.isClosed || _watchedMatchId != matchId) return;

    if (_reconnectAttempt >= _maxReconnectAttempts) {
      if (kDebugMode) {
        debugPrint('RealtimeChatService: max reconnects → polling fallback');
      }
      _startPolling();
      return;
    }

    final capMs = _reconnectCap.inMilliseconds;
    final baseMs = _reconnectBase.inMilliseconds;
    final ceiling =
        math.min(capMs.toDouble(), baseMs * math.pow(2, _reconnectAttempt));
    final delay = Duration(milliseconds: (_rng.nextDouble() * ceiling).toInt());
    _reconnectAttempt++;

    Future.delayed(delay, () {
      if (!_controller.isClosed && _watchedMatchId == matchId) {
        unawaited(_connectWebSocket(matchId));
      }
    });
  }

  // ── Internal ───────────────────────────────────────────────────────────────

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

  void _teardownTransport() {
    _wsSub?.cancel();
    _wsSub = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _watchedMatchId = null;
  }
}
