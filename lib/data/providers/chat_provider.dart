import 'dart:async';

import 'package:dating_app/core/services/realtime_chat_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// Per-conversation chat manager.
//
// Lifecycle:
//   1. Seed with local messages from DatingProvider (shown instantly, offline-safe).
//   2. Fetch remote messages from Appwrite → merge + de-duplicate.
//   3. Subscribe to Appwrite Realtime for incoming messages.
//   4. Reconnect is handled by RealtimeChatService with exponential backoff + jitter.
//
// Scalability: The previous implementation polled every 15 s as a fallback.
//   At 1M concurrent users that produces ~66K req/s from polling alone.
//   Polling is removed entirely; reconnect-with-backoff in RealtimeChatService
//   handles recovery without generating a request storm.
//
// Usage:
//   final chat = ChatProvider(
//     matchId: match.id,
//     senderName: tenantName,
//     seedMessages: match.messages,
//   );
//   await chat.initialize();
//   // … show chat.messages, call chat.sendMessage(text)
//   chat.dispose(); // when screen closes

class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required this.matchId,
    required this.senderName,
    this.senderId = '',
    List<ChatMessage> seedMessages = const [],
  })  : _messages = List<ChatMessage>.from(seedMessages),
        _service = RealtimeChatService();

  final String matchId;
  final String senderName;
  final String senderId;
  final RealtimeChatService _service;

  List<ChatMessage> _messages;
  bool _isLoading = false;
  bool _isSending = false;
  bool _realtimeConnected = false;
  bool _disposed = false;

  StreamSubscription<ChatMessage>? _sub;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;

  // True when Appwrite Realtime WebSocket is active.
  bool get realtimeConnected => _realtimeConnected;

  // True when Appwrite is configured (collection ID known).
  bool get isRemoteEnabled => _service.isConfigured;

  // ── Initialization ───────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (!_service.isConfigured) return;

    _isLoading = true;
    _safeNotify();

    final remote = await _service.fetchMessages(matchId, limit: 100);
    if (_disposed) return;

    // Remote is the source of truth. If Appwrite has messages, use them
    // exclusively — don't mix with local demo seed which may be stale.
    // If Appwrite is empty, keep the local seed so the screen isn't blank.
    if (remote.isNotEmpty) {
      _messages = remote;
    }
    _isLoading = false;
    _safeNotify();

    _service.subscribe(matchId);
    _sub = _service.messages.listen(
      _onRemoteMessage,
      onError: (Object e) {
        if (kDebugMode) debugPrint('ChatProvider: stream error: $e');
        if (!_disposed) {
          _realtimeConnected = false;
          _safeNotify();
        }
      },
    );
    _realtimeConnected = true;
    _safeNotify();
  }

  // ── Sending ──────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Use the SERVER row id as the optimistic bubble id up front, so the async WS
    // echo of this message (same id) de-dups by id — no fragile temp/name
    // matching, correct for rapid successive sends.
    final id = 'msg_${DateTime.now().microsecondsSinceEpoch}';
    _messages = [
      ..._messages,
      ChatMessage(
        id: id,
        sender: senderName,
        text: trimmed,
        createdAt: DateTime.now(),
      ),
    ];
    _isSending = true;
    _safeNotify();

    if (_service.isConfigured) {
      final created = await _service.sendMessage(
        matchId: matchId,
        senderId: senderId,
        senderName: senderName,
        text: trimmed,
        id: id,
      );
      if (!_disposed) {
        // Success → adopt the server row (same id, server timestamp); failure →
        // flag the bubble "not sent" (kept for retry, never lost).
        _messages = _messages
            .map((m) =>
                m.id == id ? (created ?? m.copyWith(failed: true)) : m)
            .toList();
      }
    }

    if (_disposed) return;
    _isSending = false;
    _safeNotify();
  }

  // ── Media (optimistic) ───────────────────────────────────────────────────────

  /// Adds a media message INSTANTLY with its local file path encoded, before the
  /// S3 upload finishes, so sending an image/voice note feels immediate. Returns
  /// the temp id to finalize once the upload completes. Not sent to the backend
  /// yet — the recipient must get the remote URL, never a local path.
  String addOptimisticMedia(String encodedLocal) {
    // Same-id-as-server scheme (see sendMessage) so the media message's WS echo
    // de-dups by id and can't produce a duplicate bubble.
    final tempId = 'msg_${DateTime.now().microsecondsSinceEpoch}';
    _messages = [
      ..._messages,
      ChatMessage(
        id: tempId,
        sender: senderName,
        text: encodedLocal,
        createdAt: DateTime.now(),
      ),
    ];
    _safeNotify();
    return tempId;
  }

  /// Finalizes an optimistic media message once its upload finishes. Success →
  /// pass the remote-URL-encoded text: the local bubble instantly swaps to the
  /// remote URL and the message is sent to the backend so the other side gets
  /// it. Failure → pass null: the bubble is flagged failed (kept, not lost).
  Future<void> resolveMedia(String tempId, String? encodedRemote) async {
    if (_disposed) return;
    if (encodedRemote == null) {
      _messages = _messages
          .map((m) => m.id == tempId ? m.copyWith(failed: true) : m)
          .toList();
      _safeNotify();
      return;
    }
    // Swap local path → remote URL immediately (sender keeps seeing the image).
    _messages = _messages
        .map((m) => m.id == tempId ? m.copyWith(text: encodedRemote) : m)
        .toList();
    _safeNotify();
    if (_service.isConfigured) {
      final created = await _service.sendMessage(
        matchId: matchId,
        senderId: senderId,
        senderName: senderName,
        text: encodedRemote,
        id: tempId,
      );
      if (_disposed) return;
      _messages = _messages
          .map((m) => m.id == tempId
              ? (created ?? m.copyWith(failed: true))
              : m)
          .toList();
      _safeNotify();
    }
  }

  // ── Deleting ─────────────────────────────────────────────────────────────────

  void deleteMessage(String messageId) {
    _messages.removeWhere((m) => m.id == messageId);
    _safeNotify();
  }

  /// Clears the visible conversation history (local). Used by the chat-info
  /// screen's "מחיקת היסטוריית השיחה" action.
  void clearMessages() {
    _messages = [];
    _safeNotify();
  }

  // ── Internal ─────────────────────────────────────────────────────────────────

  void _onRemoteMessage(ChatMessage msg) {
    if (_disposed) return;
    // Optimistic sends already carry the server id (see sendMessage), so a pure
    // id de-dup handles our own echoes AND at-least-once duplicates — no
    // temp/name reconciliation needed.
    if (_messages.any((m) => m.id == msg.id)) return;
    _messages = [..._messages, msg];
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
