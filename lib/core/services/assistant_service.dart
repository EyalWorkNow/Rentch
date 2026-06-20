import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// One turn in a conversation with Erik.
class AssistantTurn {
  const AssistantTurn({
    required this.role,
    required this.text,
    this.mediaUrls,
    this.cards = const [],
  });

  final String role; // 'user' | 'assistant'
  final String text;
  final List<String>? mediaUrls;
  final List<AssistantCard> cards;

  factory AssistantTurn.fromJson(Map<String, dynamic> json) {
    final rawCards = json['cards'];
    return AssistantTurn(
      role: (json['role'] as String?) ?? 'assistant',
      text: (json['text'] as String?) ?? '',
      mediaUrls: json['mediaUrls'] is List
          ? (json['mediaUrls'] as List)
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
          : null,
      cards: rawCards is List
          ? rawCards
              .whereType<Map>()
              .map((e) => AssistantCard.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        if (mediaUrls != null) 'mediaUrls': mediaUrls,
        if (cards.isNotEmpty) 'cards': cards.map((c) => c.toJson()).toList(),
      };

  Map<String, dynamic> toRequestJson() => {
        'role': role,
        'text': text,
        if (mediaUrls != null) 'mediaUrls': mediaUrls,
      };
}

/// A structured UI block that can be rendered inside Erik's chat thread.
class AssistantCard {
  const AssistantCard({
    required this.type,
    required this.title,
    this.subtitle,
    this.description,
    this.data = const {},
    this.items = const [],
  });

  final String type;
  final String title;
  final String? subtitle;
  final String? description;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> items;

  factory AssistantCard.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return AssistantCard(
      type: (json['type'] as String?)?.trim().isNotEmpty == true
          ? (json['type'] as String).trim()
          : 'info',
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'מידע',
      subtitle: (json['subtitle'] as String?)?.trim(),
      description: ((json['description'] ?? json['body']) as String?)?.trim(),
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const {},
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        if (subtitle != null && subtitle!.isNotEmpty) 'subtitle': subtitle,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (data.isNotEmpty) 'data': data,
        if (items.isNotEmpty) 'items': items,
      };
}

/// Erik's reply: spoken/written text, optional quick-reply chips, and an
/// optional property draft to publish.
class AssistantReply {
  const AssistantReply({
    required this.reply,
    this.propertyDraft,
    this.suggestions = const [],
    this.cards = const [],
  });

  final String reply;
  final Map<String, dynamic>? propertyDraft;
  final List<String> suggestions;
  final List<AssistantCard> cards;
}

class AssistantException implements Exception {
  const AssistantException(this.message);
  final String message;
  @override
  String toString() => 'AssistantException: $message';
}

/// "Erik" — the voice/text personal assistant. The Gemini key lives ONLY on the
/// backend; this client just talks to `POST /assistant`. Speech-to-text and
/// text-to-speech run on-device (Hebrew) so the experience feels like a phone
/// call for an older user.
class AssistantService {
  AssistantService({Duration timeout = const Duration(seconds: 40)})
      : _timeout = timeout;

  final Duration _timeout;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  bool _speechReady = false;
  bool _ttsReady = false;

  bool get isConfigured => AppConfig.awsApiGatewayUrl.trim().isNotEmpty;
  bool get isListening => _speech.isListening;

  // ── Backend ────────────────────────────────────────────────────────────────

  /// The ONLY model call in the cost-optimised listing flow: sends the user's
  /// free-text description (+ any fields already collected) to `/assistant/extract`
  /// and gets back structured fields + the list of still-missing required fields.
  /// Degrades gracefully (returns currentFields + all-missing) when the model is
  /// unavailable, so the flow can keep going by asking for each field.
  Future<({Map<String, dynamic> fields, List<String> missing, String suggestedTitle})>
      extractPropertyFields(
    String description, {
    Map<String, dynamic> currentFields = const {},
  }) async {
    const fallbackMissing = ['price', 'rooms', 'city'];
    if (!isConfigured) {
      return (fields: currentFields, missing: fallbackMissing, suggestedTitle: '');
    }
    final client = HttpClient();
    try {
      final request =
          await client.openUrl('POST', _resolve('/assistant/extract')).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      final apiKey = AppConfig.awsApiKey.trim();
      if (apiKey.isNotEmpty) request.headers.add('x-api-key', apiKey);
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null && token.isNotEmpty) {
          request.headers.add(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      } catch (_) {}
      request.write(jsonEncode(
          {'description': description, 'currentFields': currentFields}));
      final response = await request.close().timeout(_timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (fields: currentFields, missing: fallbackMissing, suggestedTitle: '');
      }
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return (
        fields: data['fields'] is Map
            ? Map<String, dynamic>.from(data['fields'] as Map)
            : currentFields,
        missing: data['missing'] is List
            ? List<String>.from(data['missing'] as List)
            : fallbackMissing,
        suggestedTitle: (data['suggestedTitle'] ?? '').toString(),
      );
    } catch (_) {
      return (fields: currentFields, missing: fallbackMissing, suggestedTitle: '');
    } finally {
      client.close(force: true);
    }
  }

  Future<AssistantReply> chat(List<AssistantTurn> turns) async {
    if (!isConfigured) {
      throw const AssistantException('העוזר האישי אינו זמין כרגע.');
    }
    final uri = _resolve('/assistant');
    final client = HttpClient();
    try {
      final request = await client.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      final apiKey = AppConfig.awsApiKey.trim();
      if (apiKey.isNotEmpty) request.headers.add('x-api-key', apiKey);
      try {
        final user = FirebaseAuth.instance.currentUser;
        final token = await user?.getIdToken();
        if (token != null && token.isNotEmpty) {
          request.headers.add(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      } catch (_) {}
      request.write(jsonEncode({
        'messages': turns.map((t) => t.toRequestJson()).toList(),
      }));
      final response = await request.close().timeout(_timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AssistantException('צריך להתחבר כדי לדבר עם העוזר.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AssistantException(
            'העוזר אינו זמין כרגע. נסו שוב בעוד רגע.');
      }
      final decoded = jsonDecode(raw);
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      final draft = data['propertyDraft'];
      final sugg = data['suggestions'];
      final rawCards = data['cards'] ?? data['items'] ?? data['ui'];
      return AssistantReply(
        reply: (data['reply'] as String?)?.trim().isNotEmpty == true
            ? (data['reply'] as String).trim()
            : 'סליחה, לא הבנתי. אפשר לחזור על זה?',
        propertyDraft: draft is Map ? Map<String, dynamic>.from(draft) : null,
        suggestions: sugg is List
            ? sugg
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : const [],
        cards: rawCards is List
            ? rawCards
                .whereType<Map>()
                .map(
                    (e) => AssistantCard.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );
    } on TimeoutException {
      throw const AssistantException('העוזר לוקח קצת זמן. נסו שוב.');
    } finally {
      client.close(force: true);
    }
  }

  // ── Speech to text (Hebrew) ──────────────────────────────────────────────────

  Future<bool> initSpeech() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _speechReady = false;
    }
    return _speechReady;
  }

  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
  }) async {
    final ok = await initSpeech();
    if (!ok) {
      throw const AssistantException(
          'לא ניתן להפעיל את המיקרופון. בדקו שההרשאה אושרה.');
    }
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'he_IL',
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onSoundLevelChange,
    );
  }

  Future<void> stopListening() async {
    if (_speech.isListening) await _speech.stop();
  }

  // ── Text to speech — Gemini's natural voice (device TTS as fallback) ─────────

  Future<void> speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    // Cost-saving: dynamic speech uses the device's own (free + very accurate)
    // Hebrew TTS instead of the paid Gemini TTS. Fixed lines are pre-recorded
    // clips (see [playPrompt]); Gemini is reserved for validation only.
    await _speakWithDevice(clean);
  }

  /// Plays a pre-recorded prompt clip bundled in assets (instant, zero API cost
  /// and zero TTS latency) — used for Erik's fixed lines. Falls back to the
  /// device TTS via [fallbackText] if the clip can't play.
  Future<void> playPrompt(String assetName, {String? fallbackText}) async {
    try {
      await _player.stop();
      final done = Completer<void>();
      StreamSubscription<void>? sub;
      sub = _player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      await _player.play(AssetSource('audio/erik/$assetName'));
      await done.future
          .timeout(const Duration(seconds: 20), onTimeout: () {});
      await sub.cancel();
    } catch (_) {
      if (fallbackText != null) await _speakWithDevice(fallbackText);
    }
  }

  /// Fetches Erik's reply as Gemini-synthesised audio (warm, natural voice) and
  /// plays it. Returns false if unavailable so the caller falls back to the OS
  /// voice. The Gemini key stays on the backend.
  Future<bool> _speakWithGemini(String text) async {
    if (!isConfigured) return false;
    final client = HttpClient();
    try {
      final request = await client
          .openUrl('POST', _resolve('/assistant/tts'))
          .timeout(_timeout);
      request.headers.contentType = ContentType.json;
      final apiKey = AppConfig.awsApiKey.trim();
      if (apiKey.isNotEmpty) request.headers.add('x-api-key', apiKey);
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null && token.isNotEmpty) {
          request.headers.add(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      } catch (_) {}
      request.write(jsonEncode({'text': text}));
      final response = await request.close().timeout(_timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final decoded = jsonDecode(raw);
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      final b64 = data['audio'] as String?;
      if (b64 == null || b64.isEmpty) return false;
      final pcm = base64Decode(b64);
      final rate = (data['sampleRate'] as num?)?.toInt() ?? 24000;
      final wav = _pcmToWav(pcm, rate);
      await _player.stop();
      // Subscribe BEFORE play so a fast clip can't complete before we listen.
      // speak() must resolve only when playback truly finishes — the continuous
      // conversation loop relies on this to know when to resume listening.
      final done = Completer<void>();
      StreamSubscription<void>? sub;
      sub = _player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
      final approxMs = (pcm.length / (rate * 2) * 1000).round() + 2500;
      await done.future.timeout(
        Duration(milliseconds: approxMs.clamp(2000, 60000)),
        onTimeout: () {},
      );
      await sub.cancel();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _speakWithDevice(String text) async {
    if (!_ttsReady) {
      try {
        await _tts.setLanguage('he-IL');
        await _tts.setSpeechRate(0.46);
        await _tts.setPitch(1.0);
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}
      _ttsReady = true;
    }
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stopSpeaking() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Wraps raw 16-bit mono PCM in a minimal WAV header so it can be played back.
  Uint8List _pcmToWav(Uint8List pcm, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLen = pcm.length;
    final b = BytesBuilder();
    void str(String s) => b.add(s.codeUnits);
    void u32(int v) =>
        b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    str('data');
    u32(dataLen);
    b.add(pcm);
    return b.toBytes();
  }

  void dispose() {
    stopSpeaking();
    stopListening();
    _player.dispose();
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
