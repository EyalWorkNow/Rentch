import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/assistant_live_service.dart' show LiveStatus;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart' hide IosAudioCategory;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Real-time speech-to-speech with אתי / עזרא over the **OpenAI Realtime API**.
///
/// Drop-in compatible with [AssistantLiveService] (same [LiveStatus], same
/// callbacks) so the live screens can swap providers with a one-line change.
///
/// Security: the OpenAI key never reaches the client. The backend mints a
/// short-lived ephemeral token (`ek_…`) locked to the model + persona + tools via
/// `POST /assistant/realtime/session`, and returns the `wsUrl`. This client
/// connects DIRECTLY to `wss://api.openai.com/v1/realtime` with that token.
///
/// Protocol (GA Realtime, server-VAD turn-taking):
///   send  {"type":"input_audio_buffer.append","audio":<b64 pcm16 24k>}
///   recv  response.output_audio.delta (b64 pcm16 24k) / response.audio.delta
///         response.output_audio_transcript.delta / response.audio_transcript.delta
///         input_audio_buffer.speech_started  → barge-in
///         response.function_call_arguments.done → tool call
///         response.done → turn complete
class OpenAiRealtimeService {
  /// [mode] = '' / 'tenant_search' → אתי (search_listings). 'landlord' → עזרא
  /// (create_property + search_listings).
  OpenAiRealtimeService({this.mode = ''});

  final String mode;

  // OpenAI Realtime PCM is 24 kHz mono, both directions.
  static const int _sampleRate = 24000;

  final AudioRecorder _recorder = AudioRecorder();
  WebSocketChannel? _ws;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<dynamic>? _wsSub;

  bool _connected = false;
  bool _playerReady = false;
  bool _disposed = false;
  bool _greeted = false;

  // ── Callbacks (names mirror AssistantLiveService for a drop-in swap) ──────────
  void Function(LiveStatus status)? onStatus;
  void Function(String text)? onUserText; // input transcription
  void Function(String text)? onErikText; // assistant text (אתי/עזרא)
  void Function()? onTurnComplete;
  void Function()? onInterrupted;
  void Function(Map<String, dynamic> args)? onCreateProperty;
  Future<String> Function(Map<String, dynamic> args)? onSearchListings;
  void Function(String message)? onError;

  bool get isConnected => _connected;

  Future<bool> hasPermission() => _recorder.hasPermission();

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_connected) return;
    _setStatus(LiveStatus.connecting);
    try {
      if (!await _recorder.hasPermission()) {
        _fail('צריך הרשאת מיקרופון כדי לדבר.');
        return;
      }
      final session = await _fetchSession();
      final token = session?.$1;
      final wsUrl = session?.$2;
      if (token == null || token.isEmpty || wsUrl == null || wsUrl.isEmpty) {
        _fail('לא הצלחתי להתחיל שיחה חיה כרגע. נסה שוב.');
        return;
      }
      _ws = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'OpenAI-Beta': 'realtime=v1',
        },
      );
      _wsSub = _ws!.stream.listen(
        _onWsData,
        onError: (Object e) {
          if (kDebugMode) debugPrint('Realtime WS error: $e');
          _fail('החיבור לשיחה נקטע.');
        },
        onDone: _onWsDone,
        cancelOnError: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Realtime connect failed: $e');
      _fail('לא הצלחתי להתחיל שיחה חיה.');
    }
  }

  Future<void> disconnect() async {
    _connected = false;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    try {
      if (_playerReady) await FlutterPcmSound.release();
    } catch (_) {}
    _playerReady = false;
    if (!_disposed) _setStatus(LiveStatus.closed);
  }

  void dispose() {
    _disposed = true;
    unawaited(disconnect());
  }

  // ── Session (ephemeral token) ─────────────────────────────────────────────────

  /// Returns (ephemeralToken, wsUrl) or null.
  Future<(String, String)?> _fetchSession() async {
    final uri = _resolve('/assistant/realtime/session');
    final client = HttpClient();
    try {
      final req =
          await client.openUrl('POST', uri).timeout(const Duration(seconds: 15));
      req.headers.contentType = ContentType.json;
      final apiKey = AppConfig.awsApiKey.trim();
      if (apiKey.isNotEmpty) req.headers.add('x-api-key', apiKey);
      try {
        final t = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (t != null && t.isNotEmpty) {
          req.headers.add(HttpHeaders.authorizationHeader, 'Bearer $t');
        }
      } catch (_) {}
      req.write(jsonEncode(mode.isEmpty ? <String, dynamic>{} : {'mode': mode}));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final raw = await utf8.decoder.bind(resp).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (kDebugMode) debugPrint('realtime session HTTP ${resp.statusCode}: $raw');
        return null;
      }
      final decoded = jsonDecode(raw);
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      final session = data['session'];
      final token = (session is Map && session['client_secret'] is Map)
          ? (session['client_secret'] as Map)['value']?.toString()
          : null;
      final wsUrl = data['wsUrl']?.toString();
      if (token == null || wsUrl == null) return null;
      return (token, wsUrl);
    } catch (e) {
      if (kDebugMode) debugPrint('realtime session fetch failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ── Incoming events ────────────────────────────────────────────────────────────

  Future<void> _onWsData(dynamic data) async {
    Map<String, dynamic>? msg;
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) msg = decoded;
    } catch (_) {
      return;
    }
    if (msg == null) return;
    final type = msg['type']?.toString() ?? '';

    switch (type) {
      case 'session.created':
      case 'session.updated':
        if (!_connected) {
          _connected = true;
          await _startPlayer();
          await _startMic();
          _setStatus(LiveStatus.listening);
          // Open with a greeting so the assistant speaks first (server-VAD alone
          // waits for the user).
          if (!_greeted) {
            _greeted = true;
            _send({'type': 'response.create'});
          }
        }
        return;

      // User started talking → barge-in: stop the assistant immediately.
      case 'input_audio_buffer.speech_started':
        onInterrupted?.call();
        await _flushPlayer();
        return;

      // Final transcript of what the user said.
      case 'conversation.item.input_audio_transcription.completed':
        final t = msg['transcript'];
        if (t is String && t.isNotEmpty) onUserText?.call(t);
        return;

      // Assistant spoken-text deltas.
      case 'response.audio_transcript.delta':
      case 'response.output_audio_transcript.delta':
        final d = msg['delta'];
        if (d is String && d.isNotEmpty) {
          _setStatus(LiveStatus.speaking);
          onErikText?.call(d);
        }
        return;

      // Assistant audio deltas (base64 pcm16 24k).
      case 'response.audio.delta':
      case 'response.output_audio.delta':
        final d = msg['delta'];
        if (d is String) _feedAudio(d);
        return;

      case 'response.done':
        onTurnComplete?.call();
        if (_connected) _setStatus(LiveStatus.listening);
        return;

      case 'response.function_call_arguments.done':
        await _handleToolCall(msg);
        return;

      case 'error':
        final err = msg['error'];
        final m = (err is Map ? err['message'] : null)?.toString();
        if (kDebugMode) debugPrint('Realtime error: $m');
        return;
    }
  }

  Future<void> _handleToolCall(Map<String, dynamic> msg) async {
    final name = msg['name']?.toString() ?? '';
    final callId = msg['call_id']?.toString();
    Map<String, dynamic> args = {};
    try {
      final raw = msg['arguments'];
      if (raw is String && raw.isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is Map) args = Map<String, dynamic>.from(parsed);
      }
    } catch (_) {}

    String output;
    if (name == 'search_listings' && onSearchListings != null) {
      output = 'לא נמצאו התאמות כרגע.';
      try {
        output = await onSearchListings!(args);
      } catch (_) {}
    } else if (name == 'create_property') {
      onCreateProperty?.call(args);
      output = 'published — הדירה פורסמה בהצלחה ונוספה ל"הדירות שלי".';
    } else {
      output = 'ok';
    }

    // Return the tool result and ask the model to continue speaking.
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        if (callId != null) 'call_id': callId,
        'output': output,
      },
    });
    _send({'type': 'response.create'});
  }

  // ── Audio out ──────────────────────────────────────────────────────────────────

  Future<void> _startPlayer() async {
    if (_playerReady) return;
    await FlutterPcmSound.setup(
      sampleRate: _sampleRate,
      channelCount: 1,
      iosAudioCategory: IosAudioCategory.playAndRecord,
    );
    _playerReady = true;
  }

  void _feedAudio(String b64) {
    if (!_playerReady) return;
    try {
      final bytes = base64Decode(b64);
      FlutterPcmSound.feed(PcmArrayInt16(
        bytes: bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
      ));
    } catch (_) {}
  }

  Future<void> _flushPlayer() async {
    try {
      await FlutterPcmSound.release();
      _playerReady = false;
      await _startPlayer();
    } catch (_) {}
  }

  // ── Audio in ────────────────────────────────────────────────────────────────────

  Future<void> _startMic() async {
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
    ));
    _micSub = stream.listen((chunk) {
      if (!_connected || chunk.isEmpty) return;
      _send({
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk),
      });
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _onWsDone() {
    if (_connected) {
      _connected = false;
      if (!_disposed) _setStatus(LiveStatus.closed);
    }
  }

  void _fail(String message) {
    onError?.call(message);
    _setStatus(LiveStatus.error);
    unawaited(disconnect());
  }

  void _setStatus(LiveStatus s) {
    if (!_disposed) onStatus?.call(s);
  }

  Uri _resolve(String path) {
    final base = Uri.parse(AppConfig.awsApiGatewayUrl.trim());
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return base.replace(
      path: [
        base.path.replaceFirst(RegExp(r'/$'), ''),
        normalized,
      ].where((p) => p.isNotEmpty).join('/'),
    );
  }
}
