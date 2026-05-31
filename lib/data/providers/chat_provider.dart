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
//   4. Poll every 15 s as a fallback when the WebSocket drops.
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
  String? _pendingTempId;

  StreamSubscription<ChatMessage>? _sub;
  Timer? _pollTimer;

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

    final remote = await _service.fetchMessages(matchId, limit: 300);
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
      onError: (_) {
        if (!_disposed) _realtimeConnected = false;
      },
    );
    _realtimeConnected = true;
    _safeNotify();

    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  // ── Sending ──────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Optimistic add so the sender sees their message instantly.
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    _pendingTempId = tempId;
    _messages = [
      ..._messages,
      ChatMessage(
        id: tempId,
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
      );
      if (!_disposed && created != null) {
        _messages = _messages.map((m) => m.id == tempId ? created : m).toList();
        _pendingTempId = null;
      }
    }

    if (_disposed) return;
    _isSending = false;
    _safeNotify();
  }

  // ── Internal ─────────────────────────────────────────────────────────────────

  void _onRemoteMessage(ChatMessage msg) {
    if (_disposed) return;
    if (_pendingTempId != null &&
        msg.sender == senderName &&
        _messages.any((m) => m.id == _pendingTempId)) {
      _messages =
          _messages.map((m) => m.id == _pendingTempId ? msg : m).toList();
      _pendingTempId = null;
      _safeNotify();
      return;
    }
    if (_messages.any((m) => m.id == msg.id)) return;
    _messages = [..._messages, msg];
    _safeNotify();
  }

  Future<void> _poll() async {
    if (_disposed || !_service.isConfigured) return;
    final fresh = await _service.fetchMessages(matchId, limit: 300);
    if (_disposed || fresh.isEmpty) return;
    // Keep in-flight optimistic messages; replace confirmed ones from server.
    final inFlight = _messages.where((m) => m.id.startsWith('temp_')).toList();
    final updated = [...fresh, ...inFlight];
    if (updated.length != _messages.length) {
      _messages = updated;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
