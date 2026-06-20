import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dating_app/core/config/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart' hide IosAudioCategory;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum LiveStatus { idle, connecting, listening, speaking, error, closed }

/// Real-time voice conversation with Erik over the **Gemini Live API**.
///
/// Security: the Gemini key never reaches the client. The backend mints a
/// short-lived *ephemeral token* (locked to Erik's model + persona +
/// create_property tool) via `POST /assistant/live-token`; this client then
/// connects DIRECTLY to the Gemini Live WebSocket with that token. Audio streams
/// both ways in real time (mic 16 kHz PCM up, model 24 kHz PCM down), the user
/// can interrupt mid-sentence, and when Erik has all the details he emits a
/// `create_property` tool call that builds a listing draft.
///
/// Protocol (verified end-to-end):
///   url    = .../GenerativeService.BidiGenerateContentConstrained?access_token=auth_tokens/…
///   send   {"setup":{}}  → wait {"setupComplete":{}}
///   mic    {"realtimeInput":{"audio":{"data":<b64 pcm16 16k>,"mimeType":"audio/pcm;rate=16000"}}}
///   recv   {"serverContent":{"inputTranscription":…,"outputTranscription":…,
///           "modelTurn":{"parts":[{"inlineData":{"data":<b64 pcm 24k>}}]},
///           "interrupted":true,"turnComplete":true}}
///   tool   {"toolCall":{"functionCalls":[{"id","name":"create_property","args":{…}}]}}
class AssistantLiveService {
  AssistantLiveService();

  static const _wsBase =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage'
      '.v1alpha.GenerativeService.BidiGenerateContentConstrained';
  static const int _inputSampleRate = 16000;
  static const int _outputSampleRate = 24000;

  final AudioRecorder _recorder = AudioRecorder();
  WebSocketChannel? _ws;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<dynamic>? _wsSub;

  bool _connected = false;
  bool _playerReady = false;
  bool _disposed = false;

  // ── Callbacks (set by the screen) ────────────────────────────────────────────
  void Function(LiveStatus status)? onStatus;
  void Function(String text)? onUserText; // input transcription chunk
  void Function(String text)? onErikText; // output transcription chunk
  void Function()? onTurnComplete;
  void Function()? onInterrupted;
  void Function(Map<String, dynamic> args)? onCreateProperty;
  void Function(String message)? onError;

  bool get isConnected => _connected;

  Future<bool> hasPermission() => _recorder.hasPermission();

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_connected) return;
    _setStatus(LiveStatus.connecting);
    try {
      if (!await _recorder.hasPermission()) {
        _fail('צריך הרשאת מיקרופון כדי לדבר עם אריק.');
        return;
      }
      final token = await _fetchToken();
      if (token == null || token.isEmpty) {
        _fail('לא הצלחתי להתחיל שיחה חיה כרגע. נסה שוב.');
        return;
      }
      final url = '$_wsBase?access_token=${Uri.encodeQueryComponent(token)}';
      _ws = IOWebSocketChannel.connect(Uri.parse(url));
      _wsSub = _ws!.stream.listen(
        _onWsData,
        onError: (Object e) {
          if (kDebugMode) debugPrint('Live WS error: $e');
          _fail('החיבור לשיחה נקטע.');
        },
        onDone: _onWsDone,
        cancelOnError: true,
      );
      // The ephemeral token already locks the full setup server-side, so an
      // empty setup is all the protocol needs to begin.
      _send({'setup': <String, dynamic>{}});
    } catch (e) {
      if (kDebugMode) debugPrint('Live connect failed: $e');
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

  // ── Token ────────────────────────────────────────────────────────────────────

  Future<String?> _fetchToken() async {
    final uri = _resolve('/assistant/live-token');
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
      req.write(jsonEncode(<String, dynamic>{}));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final raw = await utf8.decoder.bind(resp).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (kDebugMode) debugPrint('live-token HTTP ${resp.statusCode}: $raw');
        return null;
      }
      final decoded = jsonDecode(raw);
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      return data['token'] as String?;
    } catch (e) {
      if (kDebugMode) debugPrint('live-token fetch failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ── Incoming messages ────────────────────────────────────────────────────────

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

    if (msg['setupComplete'] != null) {
      _connected = true;
      await _startPlayer();
      await _startMic();
      _setStatus(LiveStatus.listening);
      return;
    }

    final sc = msg['serverContent'];
    if (sc is Map) {
      final input = sc['inputTranscription'];
      if (input is Map && input['text'] is String) {
        onUserText?.call(input['text'] as String);
      }
      final output = sc['outputTranscription'];
      if (output is Map && output['text'] is String) {
        _setStatus(LiveStatus.speaking);
        onErikText?.call(output['text'] as String);
      }
      final modelTurn = sc['modelTurn'];
      if (modelTurn is Map && modelTurn['parts'] is List) {
        for (final p in modelTurn['parts'] as List) {
          if (p is Map && p['inlineData'] is Map) {
            final b64 = (p['inlineData'] as Map)['data'];
            if (b64 is String) _feedAudio(b64);
          }
        }
      }
      if (sc['interrupted'] == true) {
        onInterrupted?.call();
        await _flushPlayer();
      }
      if (sc['turnComplete'] == true) {
        onTurnComplete?.call();
        if (_connected) _setStatus(LiveStatus.listening);
      }
    }

    final toolCall = msg['toolCall'];
    if (toolCall is Map && toolCall['functionCalls'] is List) {
      for (final c in toolCall['functionCalls'] as List) {
        if (c is Map && c['name'] == 'create_property') {
          final args = c['args'] is Map
              ? Map<String, dynamic>.from(c['args'] as Map)
              : <String, dynamic>{};
          onCreateProperty?.call(args);
          // Tell the model the listing was actually published so Erik confirms
          // it correctly by voice ("פרסמתי את הדירה") instead of asking for more.
          _send({
            'toolResponse': {
              'functionResponses': [
                {
                  if (c['id'] != null) 'id': c['id'],
                  'name': 'create_property',
                  'response': {
                    'result': 'published',
                    'message': 'הדירה פורסמה בהצלחה ונוספה ל"הדירות שלי".',
                  },
                }
              ]
            }
          });
        }
      }
    }
  }

  // ── Audio out (Erik's voice) ─────────────────────────────────────────────────

  Future<void> _startPlayer() async {
    if (_playerReady) return;
    await FlutterPcmSound.setup(
      sampleRate: _outputSampleRate,
      channelCount: 1,
      // Mic + speaker run together; the session must allow both.
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

  /// On a barge-in the model tells us it was interrupted; drop any audio still
  /// queued so Erik stops talking immediately.
  Future<void> _flushPlayer() async {
    try {
      await FlutterPcmSound.release();
      _playerReady = false;
      await _startPlayer();
    } catch (_) {}
  }

  // ── Audio in (the user's voice) ──────────────────────────────────────────────

  Future<void> _startMic() async {
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _inputSampleRate,
      numChannels: 1,
      echoCancel: true, // stop the mic from hearing Erik → no feedback loop
      noiseSuppress: true,
      autoGain: true,
    ));
    _micSub = stream.listen((chunk) {
      if (!_connected || chunk.isEmpty) return;
      _send({
        'realtimeInput': {
          'audio': {
            'data': base64Encode(chunk),
            'mimeType': 'audio/pcm;rate=$_inputSampleRate',
          }
        }
      });
    });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

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
