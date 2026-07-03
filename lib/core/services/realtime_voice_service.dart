import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dating_app/core/services/aws_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';

/// Live GPT voice ("אתי") over the OpenAI Realtime API.
///
/// Flow: fetch an EPHEMERAL session from our backend (`/assistant/realtime/session`
/// — the raw OpenAI key never reaches the device), open a WebSocket to OpenAI's
/// realtime endpoint with that token, stream mic PCM16 up, play the model's PCM16
/// audio down, and surface transcripts + the `search_listings` tool-call so the UI
/// can run a real search and show cards mid-conversation.
///
/// Untested end-to-end until the backend is deployed with a funded OPENAI_API_KEY
/// (see aws/lambda/router createRealtimeSession + the OpenAiApiKey CFN param).
enum RealtimeState { idle, connecting, listening, thinking, speaking, error }

class RealtimeVoiceService {
  RealtimeVoiceService({AwsApiClient? api}) : _api = api ?? AwsApiClient.instance;
  final AwsApiClient _api;

  static const int _sampleRate = 24000; // OpenAI realtime PCM16 mono @ 24kHz

  final _recorder = AudioRecorder();
  IOWebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  StreamSubscription<Uint8List>? _micSub;
  bool _pcmReady = false;
  bool _closed = false;

  // ── Public event streams the UI listens to ────────────────────────────────
  final _state = StreamController<RealtimeState>.broadcast();
  final _userTranscript = StreamController<String>.broadcast();
  final _assistantTranscript = StreamController<String>.broadcast();
  // Emits the arguments of a `search_listings` tool-call; the UI runs the real
  // search and calls [sendToolResult] with a short summary for אתי to voice.
  final _toolCall =
      StreamController<({String callId, Map<String, dynamic> args})>.broadcast();

  Stream<RealtimeState> get state => _state.stream;
  Stream<String> get userTranscript => _userTranscript.stream;
  Stream<String> get assistantTranscript => _assistantTranscript.stream;
  Stream<({String callId, Map<String, dynamic> args})> get toolCall =>
      _toolCall.stream;

  /// Starts the live session. Returns false if it couldn't connect (no backend,
  /// no key, no mic permission) — the caller should fall back to the classic
  /// turn-based voice flow.
  Future<bool> start() async {
    _emit(RealtimeState.connecting);
    try {
      if (!await _recorder.hasPermission()) {
        _emit(RealtimeState.error);
        return false;
      }
      final session = await _api.startRealtimeVoiceSession();
      final secret = (session['session']?['client_secret']?['value']) as String?;
      final wsUrl = session['wsUrl'] as String?;
      if (secret == null || wsUrl == null) {
        _emit(RealtimeState.error);
        return false;
      }

      _ws = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {
          'Authorization': 'Bearer $secret',
          'OpenAI-Beta': 'realtime=v1',
        },
      );
      _wsSub = _ws!.stream.listen(_onServerEvent,
          onError: (_) => _emit(RealtimeState.error), onDone: dispose);

      await _initPlayback();
      await _startMic();
      _emit(RealtimeState.listening);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('RealtimeVoiceService.start: $e');
      _emit(RealtimeState.error);
      return false;
    }
  }

  Future<void> _initPlayback() async {
    await FlutterPcmSound.setup(sampleRate: _sampleRate, channelCount: 1);
    FlutterPcmSound.start();
    _pcmReady = true;
  }

  Future<void> _startMic() async {
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    ));
    _micSub = stream.listen((bytes) {
      if (_closed || _ws == null) return;
      // Stream mic PCM16 up; server_vad on the backend detects turn ends.
      _send({
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(bytes),
      });
    });
  }

  void _onServerEvent(dynamic raw) {
    Map<String, dynamic> e;
    try {
      e = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (e['type']) {
      case 'input_audio_buffer.speech_started':
        _emit(RealtimeState.listening);
      case 'input_audio_buffer.speech_stopped':
        _emit(RealtimeState.thinking);
      case 'conversation.item.input_audio_transcription.completed':
        final t = e['transcript'] as String?;
        if (t != null && t.trim().isNotEmpty) _userTranscript.add(t.trim());
      case 'response.audio_transcript.delta':
        final d = e['delta'] as String?;
        if (d != null) _assistantTranscript.add(d);
      case 'response.audio.delta':
        _emit(RealtimeState.speaking);
        final b64 = e['delta'] as String?;
        if (b64 != null && _pcmReady) {
          final pcm = base64Decode(b64);
          FlutterPcmSound.feed(
              PcmArrayInt16(bytes: pcm.buffer.asByteData(pcm.offsetInBytes)));
        }
      case 'response.function_call_arguments.done':
        final name = e['name'] as String?;
        final callId = e['call_id'] as String?;
        if (name == 'search_listings' && callId != null) {
          Map<String, dynamic> args = const {};
          try {
            args = jsonDecode((e['arguments'] as String?) ?? '{}')
                as Map<String, dynamic>;
          } catch (_) {}
          _toolCall.add((callId: callId, args: args));
        }
      case 'response.done':
        _emit(RealtimeState.listening);
      case 'error':
        if (kDebugMode) debugPrint('Realtime error: ${e['error']}');
    }
  }

  /// After the UI runs the real search for a tool-call, feed a short natural-
  /// language summary back so אתי can voice it and keep the conversation going.
  void sendToolResult(String callId, String summary) {
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': summary,
      },
    });
    _send({'type': 'response.create'});
  }

  void _send(Map<String, dynamic> event) {
    try {
      _ws?.sink.add(jsonEncode(event));
    } catch (_) {/* socket closing */}
  }

  void _emit(RealtimeState s) {
    if (!_closed && !_state.isClosed) _state.add(s);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _micSub?.cancel();
    await _recorder.stop();
    await _wsSub?.cancel();
    await _ws?.sink.close();
    if (_pcmReady) {
      try {
        await FlutterPcmSound.release();
      } catch (_) {}
    }
    await _state.close();
    await _userTranscript.close();
    await _assistantTranscript.close();
    await _toolCall.close();
  }
}
