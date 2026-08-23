import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// Split a reply into speakable chunks on sentence enders, then glue any runt
// fragment (< 14 chars — "כן.", a lone emoji) onto its neighbour so we never pay
// a TTS round-trip to synthesise a single word. Used to stream a reply sentence-
// by-sentence for a near-instant first word.
final _sentenceEnd = RegExp(r'(?<=[.!?…׃])\s+|\n+');
List<String> splitForSpeech(String text) {
  final parts = text
      .split(_sentenceEnd)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.length <= 1) return parts.isEmpty ? [text] : parts;
  final out = <String>[];
  for (final p in parts) {
    if (out.isNotEmpty && (p.length < 14 || out.last.length < 14)) {
      out[out.length - 1] = '${out.last} $p';
    } else {
      out.add(p);
    }
  }
  return out;
}

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

/// A single listing returned by the backend `search_listings` tool. This is a
/// thin, defensive wrapper around whatever DB row shape the tool emits — the
/// only thing the client guarantees is an [id] (when present) and the raw map,
/// so the screen can render a result card and deep-link to the real property.
class AssistantListing {
  const AssistantListing({
    required this.id,
    required this.title,
    this.subtitle,
    this.price,
    this.imageUrl,
    this.data = const {},
  });

  final String id;
  final String title;
  final String? subtitle;
  final num? price;
  final String? imageUrl;
  final Map<String, dynamic> data;

  factory AssistantListing.fromJson(Map<String, dynamic> json) {
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return null;
    }

    num? pickNum(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is num) return v;
        if (v != null) {
          final parsed = num.tryParse(v.toString());
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    return AssistantListing(
      id: pick(['id', 'listingId', 'listing_id', 'propertyId', 'property_id']) ?? '',
      title: pick(['title', 'name', 'headline']) ?? 'דירה',
      subtitle: pick(['subtitle', 'address', 'city', 'neighborhood', 'neighbourhood']),
      price: pickNum(['price', 'rent', 'monthlyPrice', 'monthly_price']),
      imageUrl: pick(['imageUrl', 'image', 'imageUrls', 'thumbnail', 'photo']),
      data: json,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'title': title,
        if (subtitle != null && subtitle!.isNotEmpty) 'subtitle': subtitle,
        if (price != null) 'price': price,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      };
}

/// Erik's reply: spoken/written text, optional quick-reply chips, an optional
/// property draft to publish, structured UI cards, and (new with the backend
/// tool-loop) the real listings returned by the `search_listings` tool.
class AssistantReply {
  const AssistantReply({
    required this.reply,
    this.propertyDraft,
    this.suggestions = const [],
    this.cards = const [],
    this.listings = const [],
  });

  final String reply;
  final Map<String, dynamic>? propertyDraft;
  final List<String> suggestions;
  final List<AssistantCard> cards;

  /// Real DB results surfaced by the `search_listings` tool. Empty when the
  /// reply was plain text (backward-compatible with the pre-tool-loop backend).
  final List<AssistantListing> listings;
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

  /// OpenAI TTS voice — 'coral' (warm female) for אתי, 'onyx' (male) for עזרא.
  String ttsVoice = 'coral';

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
    final client = _http;
    try {
      final request =
          // extract-fields, NOT extract: /assistant/extract is Etti's intent
          // route — this listing-fields extractor was colliding with it.
          await client.openUrl('POST', _resolve('/assistant/extract-fields')).timeout(_timeout);
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
      final decoded = jsonDecode(raw);
      // The schema-validated extract response is plain `{fields, missing,
      // suggestedTitle}`, but tolerate a `data`-wrapped envelope too.
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      final rawMissing = data['missing'];
      return (
        fields: data['fields'] is Map
            ? Map<String, dynamic>.from(data['fields'] as Map)
            : currentFields,
        // responseSchema guarantees an array of strings, but stay fail-soft:
        // drop empty/null entries and ignore a non-list shape.
        missing: rawMissing is List
            ? rawMissing
                .map((e) => e?.toString().trim() ?? '')
                .where((s) => s.isNotEmpty)
                .toList()
            : fallbackMissing,
        suggestedTitle: (data['suggestedTitle'] ?? '').toString().trim(),
      );
    } catch (_) {
      return (fields: currentFields, missing: fallbackMissing, suggestedTitle: '');
    }
    // NB: no client.close() — _http is a shared keep-alive client (closed in dispose).
  }

  Future<AssistantReply> chat(List<AssistantTurn> turns, {String? mode}) async {
    if (!isConfigured) {
      throw const AssistantException('העוזר האישי אינו זמין כרגע.');
    }
    final uri = _resolve('/assistant');
    final client = _http;
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
        if (mode != null) 'mode': mode,
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

      // The backend tool-loop surfaces real DB rows from the `search_listings`
      // tool as a results array alongside the text. Be liberal about the field
      // name and (when nested) the inner array key, and fail soft to an empty
      // list so a plain-text reply from the old backend still works.
      final rawResults = data['results'] ??
          data['listings'] ??
          data['searchResults'] ??
          data['search_results'] ??
          data['properties'];
      List rawListings;
      if (rawResults is List) {
        rawListings = rawResults;
      } else if (rawResults is Map) {
        final inner = rawResults['results'] ??
            rawResults['listings'] ??
            rawResults['items'] ??
            rawResults['properties'];
        rawListings = inner is List ? inner : const [];
      } else {
        rawListings = const [];
      }
      final listings = rawListings
          .whereType<Map>()
          .map((e) => AssistantListing.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Surface listings through the SAME structured-card channel the chat
      // thread already renders, so a results array shows up as inline cards
      // without the screen needing new wiring. Backend-provided cards (if any)
      // are preserved and the listings card is appended.
      final cards = <AssistantCard>[
        if (rawCards is List)
          ...rawCards
              .whereType<Map>()
              .map((e) => AssistantCard.fromJson(Map<String, dynamic>.from(e))),
        if (listings.isNotEmpty)
          AssistantCard(
            type: 'listings',
            title: 'תוצאות חיפוש',
            data: {'count': listings.length},
            items: listings.map((l) => l.toJson()).toList(),
          ),
      ];

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
        cards: cards,
        listings: listings,
      );
    } on TimeoutException {
      throw const AssistantException('העוזר לוקח קצת זמן. נסו שוב.');
    }
    // NB: no client.close() — _http is a shared keep-alive client (closed in dispose).
  }

  // ── Speech to text (Hebrew) ──────────────────────────────────────────────────

  // Live status/error sink for the CURRENT listen session (set by startListening),
  // so the UI learns the moment the recogniser stops on its own (pauseFor / done /
  // error) and never gets stuck showing "listening".
  void Function(String status)? _onSpeechStatus;

  Future<bool> initSpeech() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech.initialize(
        onError: (e) => _onSpeechStatus?.call('error'),
        onStatus: (s) => _onSpeechStatus?.call(s),
      );
    } catch (_) {
      _speechReady = false;
    }
    return _speechReady;
  }

  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
    void Function(String status)? onStatus,
  }) async {
    final ok = await initSpeech();
    if (!ok) {
      throw const AssistantException(
          'לא ניתן להפעיל את המיקרופון. בדקו שההרשאה אושרה.');
    }
    _onSpeechStatus = onStatus;
    await _speech.listen(
      // Hands-free turn-taking: LISTEN more, talk less — wait ~3.5s of silence
      // before finalising so the assistant doesn't cut the user off mid-thought
      // (older landlords speak in slower, pausier sentences). listenFor caps one
      // turn.
      pauseFor: const Duration(milliseconds: 3500),
      listenFor: const Duration(seconds: 60),
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

  // ── Push-to-talk recording → Whisper STT ─────────────────────────────────────
  // Hold-to-record: capture a clip with the `record` plugin (NO native recogniser
  // → no beeps, no flicker), then send it to /assistant/transcribe (Whisper). Far
  // more accurate for Hebrew and fully deterministic (the user controls start/stop).
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _ampTimer;
  String? _recPath;

  /// Why the last startRecording failed — 'permission' (mic denied) vs a real
  /// recording error (shown to the user so a device issue is diagnosable).
  String? lastRecordError;

  Future<bool> startRecording({void Function(double level)? onLevel}) async {
    lastRecordError = null;
    // 1) Permission — request/check. Only THIS is a "need mic permission" case.
    try {
      if (!await _recorder.hasPermission()) {
        lastRecordError = 'permission';
        return false;
      }
    } catch (e) {
      lastRecordError = 'permission';
      return false;
    }
    // 2) Start recording. A failure HERE is NOT a permission problem — surface it.
    try {
      _ampTimer?.cancel();
      // Release the playback audio focus/session so the MIC can actually capture —
      // if audioplayers/TTS still holds it, the recorder yields a silent/empty clip.
      try { await _player.stop(); } catch (_) {}
      try { await _tts.stop(); } catch (_) {}
      // A stale session (previous crash / not stopped) blocks a fresh start.
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      final dir = await getTemporaryDirectory();
      // WAV (raw PCM 16-bit): no codec → never a silent/broken encode, and Whisper
      // reads it directly. Bigger than m4a but tiny for a few seconds of speech.
      _recPath = '${dir.path}/eti_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: _recPath!,
      );
      // POLL the amplitude with our OWN timer. The plugin's onAmplitudeChanged()
      // hands back a SINGLE-SUBSCRIPTION stream it creates once and reuses, so a
      // second recording's .listen() throws "Stream has already been listened to".
      if (onLevel != null) {
        _ampTimer =
            Timer.periodic(const Duration(milliseconds: 140), (_) async {
          try {
            final a = await _recorder.getAmplitude();
            onLevel(((a.current + 45) / 45).clamp(0.0, 1.0)); // dBFS → 0..1
          } catch (_) {}
        });
      }
      return true;
    } catch (e) {
      lastRecordError = 'start: $e';
      return false;
    }
  }

  /// Stop recording, transcribe via Whisper, return the text ('' if nothing / on
  /// failure). Deletes the temp clip afterwards.
  Future<String> stopRecordingAndTranscribe({String language = 'he'}) async {
    lastRecordError = null;
    _ampTimer?.cancel();
    _ampTimer = null;
    String? path;
    try {
      // ponytail: hard timeout — on iOS the `record` plugin's stop() can HANG on
      // the 2nd turn when flutter_tts (turn 1) still holds the audio session,
      // which froze the voice screen on "רגע, חושבת…". Fall back to the known path.
      path = await _recorder.stop().timeout(const Duration(seconds: 6));
    } catch (e) {
      lastRecordError = 'stop:$e';
      path = _recPath;
    }
    if (path == null) {
      lastRecordError = 'no-path';
      return '';
    }
    try {
      final f = File(path);
      if (!await f.exists()) {
        lastRecordError = 'no-file';
        return '';
      }
      final bytes = await f.readAsBytes();
      if (bytes.length < 1200) {
        // A near-empty clip means the mic didn't actually capture (session/focus).
        lastRecordError = 'empty-audio ${bytes.length}b';
        return '';
      }
      final text = await _transcribe(base64Encode(bytes), 'audio/wav', language);
      if (text.isEmpty && lastRecordError == null) {
        lastRecordError = 'transcribe-empty (${bytes.length}b)';
      }
      return text;
    } catch (e) {
      lastRecordError = 'read:$e';
      return '';
    } finally {
      try { await File(path).delete(); } catch (_) {}
    }
  }

  Future<void> cancelRecording() async {
    _ampTimer?.cancel();
    _ampTimer = null;
    try { await _recorder.stop(); } catch (_) {}
  }

  Future<String> _transcribe(String b64, String mime, String language) async {
    if (!isConfigured) return '';
    final client = _http;
    try {
      final req = await client
          .openUrl('POST', _resolve('/assistant/transcribe'))
          .timeout(_timeout);
      req.headers.contentType = ContentType.json;
      final apiKey = AppConfig.awsApiKey.trim();
      if (apiKey.isNotEmpty) req.headers.add('x-api-key', apiKey);
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null && token.isNotEmpty) {
          req.headers.add(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      } catch (_) {}
      req.write(jsonEncode({'audio': b64, 'mime': mime, 'language': language}));
      final resp = await req.close().timeout(const Duration(seconds: 25));
      final raw = await utf8.decoder.bind(resp).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        lastRecordError = 'http ${resp.statusCode}: ${raw.length > 90 ? raw.substring(0, 90) : raw}';
        return '';
      }
      final data = jsonDecode(raw);
      return (data is Map && data['text'] is String)
          ? (data['text'] as String).trim()
          : '';
    } catch (e) {
      lastRecordError = 'net:$e';
      return '';
    }
    // NB: no client.close() — _http is a shared keep-alive client (closed in dispose).
  }

  // ── Text to speech — Gemini's natural voice (device TTS as fallback) ─────────

  // Bumped every time playback should abort (new turn / barge-in). A streamed
  // speak() loop checks it between sentences and bails the moment it changes, so
  // she stops the instant the user holds the orb — never finishes a stale reply.
  int _speakGen = 0;

  Future<void> speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final gen = ++_speakGen;
    // BREAKTHROUGH: stream the reply sentence-by-sentence instead of synthesising
    // the whole paragraph before a single word plays. Time-to-first-word drops
    // from "synth the whole reply" to "synth one short sentence", and the next
    // sentence is already synthesising while the current one plays (one-ahead
    // prefetch) so there are no gaps. Erik's warm Gemini voice stays the default;
    // a per-sentence device-TTS fallback keeps her from ever going silent.
    final sentences = _splitForSpeech(clean);
    Future<({Uint8List wav, int rate})?>? next = _fetchGeminiTts(sentences.first);
    for (var i = 0; i < sentences.length; i++) {
      final clip = await next;
      if (gen != _speakGen) return; // barged in while synthesising → stop
      next = (i + 1 < sentences.length) ? _fetchGeminiTts(sentences[i + 1]) : null;
      if (clip != null) {
        await _playWav(clip.wav, clip.rate);
      } else {
        await _speakWithDevice(sentences[i]);
      }
      if (gen != _speakGen) return; // barged in during playback → stop
    }
  }

  List<String> _splitForSpeech(String text) => splitForSpeech(text);

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

  // ONE keep-alive client shared by EVERY assistant call (STT, chat, TTS,
  // extract). The backend is in us-east-1 and the user is in Israel, so a fresh
  // TLS handshake per call costs a full trans-Atlantic round-trip (~0.6–0.9s).
  // Reusing a warm connection means only the first turn pays the handshake; every
  // later call rides the open socket. idleTimeout is stretched to 90s so the
  // connection survives normal think-time between turns instead of re-dialing.
  HttpClient? _httpClient;
  HttpClient get _http =>
      _httpClient ??= (HttpClient()..idleTimeout = const Duration(seconds: 90));

  /// Synthesises one chunk of Erik's reply into Gemini audio (warm, natural
  /// voice) and returns the playable WAV + sample rate, or null if unavailable
  /// so the caller can fall back to the OS voice. The Gemini key stays on the
  /// backend.
  Future<({Uint8List wav, int rate})?> _fetchGeminiTts(String text) async {
    if (!isConfigured) return null;
    try {
      final request = await _http
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
      request.write(jsonEncode({'text': text, 'voice': ttsVoice}));
      final response = await request.close().timeout(_timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(raw);
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      final b64 = data['audio'] as String?;
      if (b64 == null || b64.isEmpty) return null;
      final pcm = base64Decode(b64);
      final rate = (data['sampleRate'] as num?)?.toInt() ?? 24000;
      return (wav: _pcmToWav(pcm, rate), rate: rate);
    } catch (_) {
      return null;
    }
  }

  /// Plays a synthesised WAV clip and resolves only when playback truly finishes
  /// — the continuous conversation loop relies on this to know when to resume.
  Future<void> _playWav(Uint8List wav, int rate) async {
    try {
      await _player.stop();
      // Subscribe BEFORE play so a fast clip can't complete before we listen.
      final done = Completer<void>();
      StreamSubscription<void>? sub;
      sub = _player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
      // A touch snappier — אתי speaks ~12% faster without sounding chipmunky.
      try {
        await _player.setPlaybackRate(1.12);
      } catch (_) {}
      final samples = (wav.length - 44).clamp(0, 1 << 30);
      final approxMs = (samples / (rate * 2) / 1.12 * 1000).round() + 2000;
      await done.future.timeout(
        Duration(milliseconds: approxMs.clamp(2000, 60000)),
        onTimeout: () {},
      );
      await sub.cancel();
    } catch (_) {/* leave the loop to fall through to the next sentence */}
  }

  Future<void> _speakWithDevice(String text) async {
    if (!_ttsReady) {
      try {
        await _tts.setLanguage('he-IL');
        await _tts.setSpeechRate(0.54); // a bit faster / snappier
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
    _speakGen++; // abort any in-flight streamed speak() loop (barge-in / new turn)
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
    try { _httpClient?.close(force: true); } catch (_) {}
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
