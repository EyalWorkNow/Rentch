import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
// LUMA AI — WALKABLE 3D-SCAN RECONSTRUCTION SERVICE  (Phase 2 MVP)
// ════════════════════════════════════════════════════════════════════════════
//
// Submits a walk-through capture (a slow video sweep of the apartment) to the
// Luma AI reconstruction API, polls the job to completion, and returns the
// resulting 3D-Gaussian-Splat asset URL. The splat is then rendered by
// `PanoramaSplatView` in a WebView.
//
// WHY LUMA (per RENTLY_SPATIAL_ARCHITECTURE.md §3 / §7): it is the only managed
// reconstruction option with a clean "you own the output, commercial-resale-OK"
// posture. We deliver `.spz` (Niantic, Apache-2.0) and render with an MIT splat
// viewer — never graphdeco-inria 3DGS or Naver Dust3r/Mast3r (non-commercial,
// voids the data-resale business).
//
// ── API KEY / CONFIG ─────────────────────────────────────────────────────────
// Read from a --dart-define, never hard-coded:
//   --dart-define=LUMA_API_KEY=luma-xxxxxxxx
// In production the key should NOT ship in the client at all — proxy through the
// AWS Lambda backend (same Firebase-JWT-gated API Gateway as AwsApiClient) so the
// secret stays server-side. This client-direct path is the MVP/dev shortcut.
// See [LumaSplatService.isConfigured] and the TODO on [_apiKey].
//
// Mirrors AwsApiClient conventions: typed request/response models, an
// [LumaApiException], per-request timeouts, and graceful null/throw on failure.
// ════════════════════════════════════════════════════════════════════════════

/// Lifecycle of a Luma reconstruction job.
enum LumaJobState {
  /// Submitted, queued, or actively reconstructing.
  processing,

  /// Finished — [LumaCapture.splatUrl] is populated.
  completed,

  /// Reconstruction failed (bad capture, server error, …).
  failed,

  /// State string the client did not recognise.
  unknown;

  static LumaJobState fromApi(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'complete':
      case 'completed':
        return LumaJobState.completed;
      case 'failed':
      case 'error':
        return LumaJobState.failed;
      case 'queued':
      case 'dispatched':
      case 'processing':
      case 'uploading':
      case 'new':
        return LumaJobState.processing;
      default:
        return LumaJobState.unknown;
    }
  }
}

/// Typed view of a Luma capture/job as returned by the API.
@immutable
class LumaCapture {
  const LumaCapture({
    required this.id,
    required this.state,
    this.splatUrl,
    this.previewUrl,
    this.errorMessage,
    this.uploadUrl,
    this.raw = const {},
  });

  /// Luma capture id (slug) used for status polling.
  final String id;

  final LumaJobState state;

  /// The reconstructed splat asset (`.spz` / `.ply`) once [state] is completed.
  final String? splatUrl;

  /// An optional preview/thumbnail (image or short video) of the scene.
  final String? previewUrl;

  /// Human-readable failure reason when [state] is failed.
  final String? errorMessage;

  /// Presigned URL the capture media must be PUT to (returned at creation).
  final String? uploadUrl;

  /// The raw decoded JSON, for fields not modelled above.
  final Map<String, dynamic> raw;

  bool get isCompleted => state == LumaJobState.completed;
  bool get isFailed => state == LumaJobState.failed;
  bool get isTerminal => isCompleted || isFailed;

  factory LumaCapture.fromJson(Map<String, dynamic> j) {
    // Luma's response nests the deliverables under `assets`. We prefer an `.spz`
    // (smaller, keeps spherical harmonics) and fall back to `.ply`, then to any
    // generic gaussian-splat field the API exposes.
    final assets = (j['assets'] as Map?)?.cast<String, dynamic>() ?? const {};
    final splat = _firstNonEmpty([
      assets['spz'],
      assets['gaussian_splat'],
      assets['ply'],
      j['spz'],
      j['gaussianSplatUrl'],
    ]);
    final preview = _firstNonEmpty([
      assets['thumb'],
      assets['image'],
      assets['video'],
      j['thumbUrl'],
    ]);
    return LumaCapture(
      id: (j['id'] ?? j['slug'] ?? j['capture'] ?? '').toString(),
      state: LumaJobState.fromApi((j['status'] ?? j['state'])?.toString()),
      splatUrl: splat,
      previewUrl: preview,
      errorMessage: (j['error'] ?? j['errorMessage'] ?? j['message'])?.toString(),
      uploadUrl: _firstNonEmpty([j['uploadUrl'], j['upload_url'], j['signedUrl']]),
      raw: j,
    );
  }

  LumaCapture copyWith({LumaJobState? state, String? splatUrl}) => LumaCapture(
        id: id,
        state: state ?? this.state,
        splatUrl: splatUrl ?? this.splatUrl,
        previewUrl: previewUrl,
        errorMessage: errorMessage,
        uploadUrl: uploadUrl,
        raw: raw,
      );

  static String? _firstNonEmpty(List<Object?> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }
}

/// Service for the Luma reconstruction pipeline: create → upload → trigger →
/// poll → splat URL. Stateless singleton, mirroring [AwsApiClient.instance].
class LumaSplatService {
  LumaSplatService._();
  static final LumaSplatService instance = LumaSplatService._();

  final _http = http.Client();

  // Luma Genie / reconstruction REST API. Override the host with
  //   --dart-define=LUMA_API_URL=https://api.lumalabs.ai/dream-machine/v1
  static const String _baseUrl = String.fromEnvironment(
    'LUMA_API_URL',
    defaultValue: 'https://api.lumalabs.ai/dream-machine/v1',
  );

  // TODO(security): do NOT ship this key in a production client build. Move the
  // Luma calls behind the AWS Lambda proxy (AppConfig.scan3dProxyUrl) so the
  // secret lives server-side, exactly like the panorama-stitch jobs. For the MVP
  // this reads a build-time --dart-define so nothing is hard-coded in source.
  static const String _apiKey = String.fromEnvironment(
    'LUMA_API_KEY',
    // Fall back to the existing generic spatial key if a Luma-specific one
    // wasn't provided, so dev builds that already set SPATIAL_API_KEY work.
    defaultValue: '',
  );

  static String get _resolvedKey =>
      _apiKey.trim().isNotEmpty ? _apiKey.trim() : AppConfig.spatialApiKey.trim();

  /// True when a Luma (or fallback spatial) API key is available.
  bool get isConfigured => _resolvedKey.isNotEmpty;

  static const Duration _timeout = Duration(seconds: 30);

  /// How long to keep polling before giving up. Reconstruction is minutes-scale
  /// (Luma quotes ~30 min for full scenes), so this is generous.
  static const Duration _pollBudget = Duration(minutes: 40);
  static const Duration _pollInterval = Duration(seconds: 15);

  Map<String, String> get _headers => {
        HttpHeaders.authorizationHeader: 'Bearer $_resolvedKey',
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      };

  // ── 1. Create a capture (reserves an id + an upload URL) ───────────────────

  /// Creates a reconstruction job and returns the capture (with [uploadUrl]).
  Future<LumaCapture> createCapture({String? title}) async {
    _ensureConfigured();
    final res = await _http
        .post(
          Uri.parse('$_baseUrl/capture'),
          headers: _headers,
          body: jsonEncode({
            if (title != null && title.isNotEmpty) 'title': title,
          }),
        )
        .timeout(_timeout);
    final json = _decode(res, 'createCapture');
    final capture = LumaCapture.fromJson(json);
    if (capture.id.isEmpty) {
      throw const LumaApiException('Luma did not return a capture id');
    }
    return capture;
  }

  // ── 2. Upload the captured video to the presigned URL ──────────────────────

  /// Streams [videoPath] to the capture's presigned [uploadUrl] (no auth header
  /// on the presigned PUT). Returns true on success. Streams from disk so large
  /// clips don't OOM (same approach as AwsApiClient.uploadToPresignedUrl).
  Future<bool> uploadCaptureVideo(String uploadUrl, String videoPath) async {
    final file = File(videoPath);
    if (!file.existsSync()) return false;
    final size = await file.length();
    final client = HttpClient();
    try {
      final req = await client
          .openUrl('PUT', Uri.parse(uploadUrl))
          .timeout(const Duration(seconds: 30));
      req.headers.set(HttpHeaders.contentTypeHeader, _mimeForVideo(videoPath));
      req.contentLength = size;
      await req.addStream(file.openRead()).timeout(_uploadTimeoutFor(size));
      final resp = await req.close().timeout(const Duration(seconds: 120));
      await resp.drain<void>();
      return resp.statusCode < 300;
    } catch (e) {
      if (kDebugMode) debugPrint('LumaSplatService.uploadCaptureVideo: $e');
      return false;
    } finally {
      client.close();
    }
  }

  // ── 3. Trigger reconstruction once the media is uploaded ───────────────────

  Future<void> triggerReconstruction(String captureId) async {
    _ensureConfigured();
    final res = await _http
        .post(
          Uri.parse('$_baseUrl/capture/$captureId'),
          headers: _headers,
          body: jsonEncode(const {'generation_type': 'gaussian_splat'}),
        )
        .timeout(_timeout);
    _decode(res, 'triggerReconstruction');
  }

  // ── 4. Poll one status read ────────────────────────────────────────────────

  Future<LumaCapture> getCapture(String captureId) async {
    _ensureConfigured();
    final res = await _http
        .get(Uri.parse('$_baseUrl/capture/$captureId'), headers: _headers)
        .timeout(_timeout);
    return LumaCapture.fromJson(_decode(res, 'getCapture'));
  }

  // ── Convenience: poll until terminal, surfacing progress ───────────────────

  /// Polls [captureId] every [_pollInterval] until completed/failed or the
  /// [_pollBudget] elapses. [onUpdate] receives each intermediate state so the
  /// UI can show progress. Throws [LumaApiException] on failure/timeout.
  Future<LumaCapture> pollUntilDone(
    String captureId, {
    void Function(LumaCapture capture)? onUpdate,
  }) async {
    final deadline = DateTime.now().add(_pollBudget);
    while (DateTime.now().isBefore(deadline)) {
      final capture = await getCapture(captureId);
      onUpdate?.call(capture);
      if (capture.isCompleted) {
        if (capture.splatUrl == null || capture.splatUrl!.isEmpty) {
          throw const LumaApiException(
              'Luma reported complete but returned no splat asset');
        }
        return capture;
      }
      if (capture.isFailed) {
        throw LumaApiException(
          capture.errorMessage?.isNotEmpty == true
              ? capture.errorMessage!
              : 'Luma reconstruction failed',
        );
      }
      await Future<void>.delayed(_pollInterval);
    }
    throw const LumaApiException('Luma reconstruction timed out');
  }

  // ── End-to-end: capture video → splat URL ──────────────────────────────────

  /// One-shot helper: create → upload [videoPath] → trigger → poll → splat URL.
  /// Returns the splat asset URL, or throws [LumaApiException] on any failure.
  Future<String> reconstructFromVideo(
    String videoPath, {
    String? title,
    void Function(LumaCapture capture)? onUpdate,
  }) async {
    final created = await createCapture(title: title);
    final uploadUrl = created.uploadUrl;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const LumaApiException('Luma did not return an upload URL');
    }
    final ok = await uploadCaptureVideo(uploadUrl, videoPath);
    if (!ok) throw const LumaApiException('Capture video upload failed');
    await triggerReconstruction(created.id);
    final done = await pollUntilDone(created.id, onUpdate: onUpdate);
    return done.splatUrl!;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const LumaApiException(
          'Luma API key is not configured (set --dart-define=LUMA_API_KEY=...)');
    }
  }

  Map<String, dynamic> _decode(http.Response res, String op) {
    if (res.statusCode >= 400) {
      throw LumaApiException(
        'Luma $op failed: HTTP ${res.statusCode} ${res.body}',
        statusCode: res.statusCode,
      );
    }
    if (res.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'data': decoded};
    } catch (_) {
      throw LumaApiException('Luma $op returned non-JSON body', op: op);
    }
  }

  // ~1 s per 50 KB, clamped 3–20 min — same shape as AwsApiClient.
  Duration _uploadTimeoutFor(int bytes) =>
      Duration(seconds: (bytes / 50000).ceil().clamp(180, 1200));

  static String _mimeForVideo(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      _ => 'video/mp4',
    };
  }

  void dispose() => _http.close();
}

// ─── Exception ────────────────────────────────────────────────────────────────

class LumaApiException implements Exception {
  const LumaApiException(this.message, {this.statusCode, this.op});
  final String message;
  final int? statusCode;
  final String? op;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'LumaApiException($statusCode): $message';
}
