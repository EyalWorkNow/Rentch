import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:dating_app/core/config/app_config.dart';
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
//   matchId    : string  (index)
//   senderId   : string
//   senderName : string
//   text       : string  (max 2000 chars)
//   createdAt  : string  (ISO-8601, sortable)
//
// Collection permissions:
//   Read  : Users  (any authenticated user — enforce match membership in Functions)
//   Write : Users
//
// Realtime channel: databases.{dbId}.collections.{collectionId}.documents
//
// To enable: ensure APPWRITE_MESSAGES_TABLE_ID is set in --dart-define, OR
//            set AppConfig.appwriteMessagesTableId default to your collection ID.

class RealtimeChatService {
  RealtimeChatService() : _collectionId = AppConfig.appwriteMessagesTableId;

  final String _collectionId;

  Realtime? _realtime;
  RealtimeSubscription? _subscription;
  final _controller = StreamController<ChatMessage>.broadcast();

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
        if (kDebugMode) debugPrint('RealtimeChatService error: $error');
        _subscription = null;
        // Auto-reconnect after 3 s
        Future.delayed(const Duration(seconds: 3), () {
          if (!_controller.isClosed) subscribe(matchId);
        });
      },
      onDone: () {
        if (kDebugMode) debugPrint('RealtimeChatService: WS closed');
        _subscription = null;
      },
    );
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

      await tables.createRow(
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
      );

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
    int limit = 200,
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

      final result = await tables.listRows(
        databaseId: appwriteDatabaseId,
        tableId: _collectionId,
        queries: queries,
      );

      return result.rows
          .map((row) => _rowToMessage(row.data))
          .whereType<ChatMessage>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeChatService.fetchMessages error: $e');
      return const [];
    }
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
