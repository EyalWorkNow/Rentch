import 'dart:async';
import 'dart:io';

import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/scan3d_job.dart';
import 'package:flutter/foundation.dart';

// ════════════════════════════════════════════════════════════════════════════
// KIRI 3D SERVICE — high-quality apartment scan (textured mesh GLB + 3D splat)
// ════════════════════════════════════════════════════════════════════════════
//
// Drives a full reconstruction job through OUR AWS backend proxy. The backend
// owns the KIRI Engine API key and never exposes it to the client; this service
// only ever talks to our API Gateway (via [AwsApiClient]), exactly like the
// panorama-stitch job flow in aws_client.dart.
//
// Lifecycle (backend contract):
//   1. createJob(propertyId, captureType, frameCount)
//        POST /scan3d → {jobId, uploadUrls:[presigned PUT urls]}
//   2. uploadCapture(uploadUrl, file)            (one per capture file)
//        PUT <presigned url>  (raw bytes, no auth header)
//   3. start(jobId)
//        POST /scan3d/{jobId}/start → {ok:true}
//   4. poll(jobId) / result(jobId)
//        GET  /scan3d/{jobId} → {status, meshGlbUrl?, splatUrl?, error?}
//
// On ready the job carries:
//   • meshGlbUrl — textured mesh (.glb)
//   • splatUrl   — 3D Gaussian-splat (.ply)
//
// Mirrors AwsApiClient / LumaSplatService conventions: typed results, a
// dedicated [Kiri3dException], per-request timeouts, and size-based upload
// timeouts so large video sweeps on slow cellular don't fail prematurely.
// ════════════════════════════════════════════════════════════════════════════

/// How the apartment was captured.
enum Scan3dCaptureType {
  photos,
  video;

  String get wire => this == Scan3dCaptureType.video ? 'video' : 'photos';
}

/// Result of creating a job: the job id plus one presigned PUT URL per capture
/// file the client must upload.
@immutable
class Scan3dJobCreation {
  const Scan3dJobCreation({required this.jobId, required this.uploadUrls});

  final String jobId;
  final List<String> uploadUrls;
}

/// Client for the backend 3D-scan proxy. Stateless singleton, mirroring
/// [AwsApiClient.instance].
class Kiri3dService {
  Kiri3dService._({AwsApiClient? api}) : _api = api ?? AwsApiClient.instance;

  static final Kiri3dService instance = Kiri3dService._();

  /// Test seam: inject a custom [AwsApiClient].
  @visibleForTesting
  factory Kiri3dService.withClient(AwsApiClient api) =>
      Kiri3dService._(api: api);

  final AwsApiClient _api;

  bool get isConfigured => _api.isConfigured;

  /// Reconstruction is minutes-scale (KIRI photo/3DGS jobs typically finish in
  /// a few minutes to ~30 min depending on input size), so the poll budget is
  /// generous.
  static const Duration _pollBudget = Duration(minutes: 45);
  static const Duration _pollInterval = Duration(seconds: 15);

  // ── 1. Create a job ─────────────────────────────────────────────────────────

  /// Creates a scan job and returns the [jobId] plus a presigned PUT URL per
  /// capture file. Throws [Kiri3dException] on any failure.
  Future<Scan3dJobCreation> createJob({
    required String propertyId,
    required Scan3dCaptureType captureType,
    required int frameCount,
  }) async {
    _ensureConfigured();
    if (propertyId.trim().isEmpty) {
      throw const Kiri3dException('propertyId is required');
    }
    if (frameCount <= 0) {
      throw const Kiri3dException('frameCount must be greater than zero');
    }

    final Map<String, dynamic> res;
    try {
      res = await _api.post('/scan3d', {
        'propertyId': propertyId,
        'captureType': captureType.wire,
        'frameCount': frameCount,
      });
    } on AwsApiException catch (e) {
      throw Kiri3dException('Failed to create scan job: ${e.message}',
          statusCode: e.statusCode);
    }

    final data = _data(res);
    final jobId = (data['jobId'] ?? data['id'])?.toString();
    final urls = (data['uploadUrls'] as List?)
        ?.map((u) => u?.toString() ?? '')
        .where((u) => u.isNotEmpty)
        .toList();

    if (jobId == null || jobId.isEmpty) {
      throw const Kiri3dException('Backend did not return a jobId');
    }
    if (urls == null || urls.isEmpty) {
      throw const Kiri3dException('Backend did not return any upload URLs');
    }
    return Scan3dJobCreation(jobId: jobId, uploadUrls: urls);
  }

  // ── 2. Upload a capture file to its presigned URL ───────────────────────────

  /// Streams [file] to its presigned [uploadUrl] (no auth header on the
  /// presigned PUT). Streams from disk so large video sweeps don't OOM, with a
  /// size-based timeout. Returns true on success.
  Future<bool> uploadCapture(String uploadUrl, File file) async {
    if (uploadUrl.trim().isEmpty) return false;
    if (!file.existsSync()) return false;
    final size = await file.length();
    // ponytail: 3 attempts — one mobile-network hiccup shouldn't fail the scan
    // (this was the silent killer: a dropped PUT → false → generic UI error).
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (await _putOnce(uploadUrl, file, size)) return true;
      if (attempt < 3) await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
    return false;
  }

  Future<bool> _putOnce(String uploadUrl, File file, int size) async {
    final client = HttpClient();
    try {
      final req = await client
          .openUrl('PUT', Uri.parse(uploadUrl))
          .timeout(const Duration(seconds: 30));
      req.headers.set(HttpHeaders.contentTypeHeader, _mimeFor(file.path));
      req.contentLength = size;
      await req.addStream(file.openRead()).timeout(_uploadTimeoutFor(size));
      final resp = await req.close().timeout(const Duration(seconds: 120));
      await resp.drain<void>();
      return resp.statusCode < 300;
    } catch (e) {
      if (kDebugMode) debugPrint('Kiri3dService.uploadCapture: $e');
      return false;
    } finally {
      client.close();
    }
  }

  // ── 3. Start reconstruction once all captures are uploaded ──────────────────

  /// Kicks off the (async) reconstruction. Returns true when the backend
  /// acknowledges with `{ok:true}`. Throws [Kiri3dException] on a server error.
  Future<bool> start(String jobId) async {
    _ensureConfigured();
    if (jobId.trim().isEmpty) {
      throw const Kiri3dException('jobId is required to start a scan');
    }
    final Map<String, dynamic> res;
    try {
      res = await _api.post('/scan3d/$jobId/start', const {});
    } on AwsApiException catch (e) {
      throw Kiri3dException('Failed to start scan job: ${e.message}',
          statusCode: e.statusCode);
    }
    final data = _data(res);
    return data['ok'] == true || res['ok'] == true;
  }

  // ── 4. Single status read ───────────────────────────────────────────────────

  /// Reads the current job state once.
  Future<Scan3dJob> result(String jobId) async {
    _ensureConfigured();
    if (jobId.trim().isEmpty) {
      throw const Kiri3dException('jobId is required');
    }
    final Map<String, dynamic> res;
    try {
      res = await _api.get('/scan3d/$jobId');
    } on AwsApiException catch (e) {
      throw Kiri3dException('Failed to read scan job: ${e.message}',
          statusCode: e.statusCode);
    }
    return Scan3dJob.fromJson(res).copyWith(jobId: jobId);
  }

  // ── Convenience: poll to a terminal state ───────────────────────────────────

  /// Polls [jobId] every [_pollInterval] until the job is ready/failed or the
  /// [_pollBudget] elapses. Emits each intermediate [Scan3dJob] so the UI can
  /// show progress; closes after a terminal state. On timeout it emits a
  /// synthetic failed job and closes (never hangs).
  Stream<Scan3dJob> poll(String jobId) async* {
    final deadline = DateTime.now().add(_pollBudget);
    while (DateTime.now().isBefore(deadline)) {
      Scan3dJob job;
      try {
        job = await result(jobId);
      } on Kiri3dException catch (e) {
        // Surface the error as a failed job rather than tearing down the stream
        // on a transient read.
        if (kDebugMode) debugPrint('Kiri3dService.poll read error: $e');
        await Future<void>.delayed(_pollInterval);
        continue;
      }
      yield job;
      if (job.isTerminal) return;
      await Future<void>.delayed(_pollInterval);
    }
    yield Scan3dJob(
      jobId: jobId,
      status: Scan3dStatus.failed,
      error: 'Scan timed out after ${_pollBudget.inMinutes} minutes',
    );
  }

  // ── End-to-end helper ───────────────────────────────────────────────────────

  /// One-shot: create → upload every file in [files] → start → poll to terminal.
  /// [onUpdate] receives each polled state. Returns the final [Scan3dJob]
  /// (ready or failed). Throws [Kiri3dException] before reconstruction begins
  /// (job creation, upload, or start failure).
  Future<Scan3dJob> runScan({
    required String propertyId,
    required Scan3dCaptureType captureType,
    required List<File> files,
    void Function(Scan3dJob job)? onUpdate,
  }) async {
    if (files.isEmpty) {
      throw const Kiri3dException('No capture files to upload');
    }
    final created = await createJob(
      propertyId: propertyId,
      captureType: captureType,
      frameCount: files.length,
    );

    final count = files.length < created.uploadUrls.length
        ? files.length
        : created.uploadUrls.length;
    for (var i = 0; i < count; i++) {
      final ok = await uploadCapture(created.uploadUrls[i], files[i]);
      if (!ok) {
        throw Kiri3dException(
            'Failed to upload capture ${i + 1} of $count');
      }
    }

    final started = await start(created.jobId);
    if (!started) {
      throw const Kiri3dException('Backend did not acknowledge scan start');
    }

    Scan3dJob last = Scan3dJob(
      jobId: created.jobId,
      status: Scan3dStatus.processing,
    );
    await for (final job in poll(created.jobId)) {
      last = job;
      onUpdate?.call(job);
      if (job.isTerminal) break;
    }
    return last;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const Kiri3dException('3D scan backend is not configured');
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> res) {
    final raw = res['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return res;
  }

  // ~1 s per 50 KB, clamped 3–20 min — same shape as AwsApiClient.
  Duration _uploadTimeoutFor(int bytes) =>
      Duration(seconds: (bytes / 50000).ceil().clamp(180, 1200));

  static String _mimeFor(String path) {
    final ext = path.split('?').first.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'mp4' => 'video/mp4',
      _ => 'application/octet-stream',
    };
  }
}

// ─── Exception ──────────────────────────────────────────────────────────────

class Kiri3dException implements Exception {
  const Kiri3dException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'Kiri3dException($statusCode): $message';
}
