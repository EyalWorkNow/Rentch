import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/config/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─── AWS API Gateway HTTP Client ──────────────────────────────────────────────
//
// All requests include:
//   Authorization: Bearer {Firebase ID token}
//   x-api-key:     {AppConfig.awsApiKey}
//   Content-Type:  application/json
//
// API Gateway verifies the Firebase JWT via a Lambda authorizer.
// Lambda functions handle the DynamoDB/S3 business logic.
//
// Endpoint config: --dart-define=AWS_API_URL=https://xxx.execute-api.eu-central-1.amazonaws.com/prod
//                  --dart-define=AWS_API_KEY=xxxxx

class AwsApiClient {
  AwsApiClient._();
  static final AwsApiClient instance = AwsApiClient._();

  final _http = http.Client();

  bool get isConfigured => AppConfig.awsApiGatewayUrl.trim().isNotEmpty;

  // ── Core HTTP methods ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query: query);
    final headers = await _headers();
    final response = await _http.get(uri, headers: headers).timeout(_timeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _uri(path);
    final headers = await _headers();
    final response = await _http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _uri(path);
    final headers = await _headers();
    final response = await _http
        .put(uri, headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
    return _decode(response);
  }

  Future<void> delete(String path) async {
    final uri = _uri(path);
    final headers = await _headers();
    final response =
        await _http.delete(uri, headers: headers).timeout(_timeout);
    if (response.statusCode >= 400) {
      throw AwsApiException(
        'DELETE $path returned ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  // ── S3 file upload via presigned URL ─────────────────────────────────────

  /// Requests a presigned PUT URL from Lambda, uploads the file directly
  /// to S3, and returns the public HTTPS URL.
  Future<String?> uploadFile(
    String localPath, {
    String? contentType,
    String folder = 'uploads',
    String? fileName,
  }) async {
    if (!isConfigured || !AppConfig.canUseCloudStorage) return null;
    try {
      final file = File(localPath);
      if (!file.existsSync()) return null;

      final ext = localPath.split('.').last.toLowerCase();
      final normalizedName = _sanitizeFileName(fileName);
      final suffix = normalizedName == null || normalizedName.isEmpty
          ? '${DateTime.now().microsecondsSinceEpoch}.$ext'
          : '${DateTime.now().microsecondsSinceEpoch}_$normalizedName';
      final key = '$folder/$suffix';
      final mime = contentType ?? _mimeFor(ext);

      // 1. Get presigned URL from Lambda
      final presignResult = await post('/storage/presign', {
        'key': key,
        'contentType': mime,
      });
      final uploadUrl = presignResult['uploadUrl'] as String?;
      final publicUrl = presignResult['publicUrl'] as String?;
      if (uploadUrl == null || publicUrl == null) return null;

      // 2. STREAM the file straight to S3 (presigned URL needs no auth headers).
      //    Streaming via dart:io avoids loading large videos fully into memory
      //    (the old readAsBytes + flat 60s PUT failed/OOM'd on big clips), and a
      //    size-based timeout prevents premature failure on slow cellular.
      final fileSize = await file.length();
      final httpClient = HttpClient();
      try {
        final request = await httpClient
            .openUrl('PUT', Uri.parse(uploadUrl))
            .timeout(const Duration(seconds: 30));
        request.headers.set(HttpHeaders.contentTypeHeader, mime);
        request.contentLength = fileSize;
        await request
            .addStream(file.openRead())
            .timeout(_uploadTimeoutFor(fileSize));
        final s3Response =
            await request.close().timeout(const Duration(seconds: 90));
        await s3Response.drain<void>();
        if (s3Response.statusCode >= 300) return null;
        return publicUrl;
      } finally {
        httpClient.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AwsApiClient.uploadFile error: $e');
      return null;
    }
  }

  // Upload timeout: ~1 s per 50 KB, clamped to 3–20 min, so large videos on slow
  // connections don't fail prematurely.
  Duration _uploadTimeoutFor(int bytes) =>
      Duration(seconds: (bytes / 50000).ceil().clamp(180, 1200));

  // ── Panorama stitch jobs (server-side OpenCV) ─────────────────────────────

  /// Create a stitch job; returns the jobId + one presigned PUT URL per frame.
  ///
  /// [poses] is optional and, when given, must be PARALLEL to the frames
  /// (poses[i] ↔ frame f{i}, same order/length): a top-level `poses` JSON array
  /// of `{yaw, pitch, hfov, vfov}` in degrees, which the server uses for
  /// deterministic pose-assisted stitching. Omitted/empty → backward-compatible.
  Future<({String jobId, List<String> uploadUrls})?> createPanoramaJob({
    required String propertyId,
    required int frameCount,
    List<Map<String, double>>? poses,
  }) async {
    if (!isConfigured) return null;
    final res = await post('/panorama', {
      'propertyId': propertyId,
      'frameCount': frameCount,
      if (poses != null && poses.isNotEmpty) 'poses': poses,
    });
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId'] as String?;
    final urls = (data?['uploadUrls'] as List?)?.cast<String>();
    if (jobId == null || urls == null || urls.isEmpty) return null;
    return (jobId: jobId, uploadUrls: urls);
  }

  /// PUT one captured frame straight to its presigned S3 URL. Returns success.
  Future<bool> uploadToPresignedUrl(String uploadUrl, String localPath,
      {String contentType = 'image/jpeg'}) async {
    try {
      final file = File(localPath);
      if (!file.existsSync()) return false;
      final size = await file.length();
      final httpClient = HttpClient();
      try {
        final req = await httpClient
            .openUrl('PUT', Uri.parse(uploadUrl))
            .timeout(const Duration(seconds: 30));
        req.headers.set(HttpHeaders.contentTypeHeader, contentType);
        req.contentLength = size;
        await req.addStream(file.openRead()).timeout(_uploadTimeoutFor(size));
        final resp = await req.close().timeout(const Duration(seconds: 60));
        await resp.drain<void>();
        return resp.statusCode < 300;
      } finally {
        httpClient.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('uploadToPresignedUrl error: $e');
      return false;
    }
  }

  /// Create a VIDEO-mode panorama job: the user recorded a short clip while
  /// turning once, and the SERVER extracts sharp keyframes and stitches them via
  /// the supplied [poseTimeline]. Returns the jobId + ONE presigned PUT URL for
  /// the (transcoded mp4) video.
  ///
  /// [poseTimeline] is a list of `{tMs, yaw, pitch}` samples (tMs = ms since the
  /// recording started; yaw in DEGREES 0..360; pitch in DEGREES), monotonic in
  /// tMs. Reuses [startPanoramaStitch]/[getPanorama] for stitch + poll.
  Future<({String jobId, String videoUploadUrl})?> createPanoramaVideoJob({
    required String propertyId,
    required double hfov,
    required double vfov,
    required List<Map<String, double>> poseTimeline,
  }) async {
    if (!isConfigured) return null;
    final res = await post('/panorama', {
      'propertyId': propertyId,
      'captureMode': 'video',
      'hfov': hfov,
      'vfov': vfov,
      'poseTimeline': poseTimeline,
    });
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId'] as String?;
    final url = data?['videoUploadUrl'] as String?;
    if (jobId == null || url == null || url.isEmpty) return null;
    return (jobId: jobId, videoUploadUrl: url);
  }

  /// Create an ARRANGED panorama job: the user imported several NATIVE phone
  /// panoramas and placed each one on a 360° track (where it starts + how wide
  /// it is + which vertical band it covers). The SERVER stitches them into one
  /// equirectangular panorama. Returns the jobId + ONE presigned PUT URL per
  /// pano, in the SAME order as [panos] (uploadUrls[i] ↔ panos[i]).
  ///
  /// [panos] is a list of `{startDeg, widthDeg, row}` where `startDeg` (0..360)
  /// is where the pano begins on the rotation, `widthDeg` (>0..360) is its
  /// angular width, and `row` ∈ 'horizontal'|'top'|'bottom' is the vertical band.
  /// Reuses [uploadToPresignedUrl] for upload + [startPanoramaStitch]/[getPanorama]
  /// for stitch + poll.
  Future<({String jobId, List<String> uploadUrls})?> createArrangedPanoramaJob({
    required String propertyId,
    required List<Map<String, dynamic>> panos,
  }) async {
    if (!isConfigured || panos.isEmpty) return null;
    final res = await post('/panorama', {
      'propertyId': propertyId,
      'captureMode': 'arranged',
      'panos': panos,
    });
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId'] as String?;
    final urls = (data?['uploadUrls'] as List?)?.cast<String>();
    if (jobId == null || urls == null || urls.length < panos.length) return null;
    return (jobId: jobId, uploadUrls: urls);
  }

  /// PUT the transcoded mp4 bytes straight to the presigned video URL with
  /// `Content-Type: video/mp4`. Returns success. Thin alias over
  /// [uploadToPresignedUrl] so the contract reads clearly at the call site.
  Future<bool> uploadVideoToPresigned(String uploadUrl, String localPath) =>
      uploadToPresignedUrl(uploadUrl, localPath, contentType: 'video/mp4');

  /// Kick off the (async) stitch once all frames are uploaded.
  Future<void> startPanoramaStitch(String jobId) =>
      post('/panorama/$jobId/stitch', const {});

  /// Poll job status. status ∈ pending|processing|ready|failed.
  Future<({String status, String imageUrl, double haov, double vaov, String error})?>
      getPanorama(String jobId) async {
    final res = await get('/panorama/$jobId');
    final data = res['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    return (
      status: (data['status'] as String?) ?? 'pending',
      imageUrl: (data['imageUrl'] as String?) ?? '',
      haov: (data['haov'] as num?)?.toDouble() ?? 360,
      vaov: (data['vaov'] as num?)?.toDouble() ?? 60,
      error: (data['error'] as String?) ?? '',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static const Duration _timeout = Duration(seconds: 20);

  Uri _uri(String path, {Map<String, String>? query}) {
    final base =
        AppConfig.awsApiGatewayUrl.trimRight().replaceFirst(RegExp(r'/$'), '');
    final normalized = path.startsWith('/') ? path : '/$path';
    var uri = Uri.parse('$base$normalized');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    return uri;
  }

  Future<Map<String, String>> _headers() async {
    final apiKey = AppConfig.awsApiKey;
    final Map<String, String> h = {
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: 'application/json',
      if (apiKey.isNotEmpty) 'x-api-key': apiKey,
    };

    // Attach Firebase ID token for the Lambda authorizer
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        if (token != null && token.isNotEmpty) {
          h[HttpHeaders.authorizationHeader] = 'Bearer $token';
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AwsApiClient: could not get Firebase token: $e');
      }
    }

    return h;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 404) return const {};
    if (response.statusCode >= 400) {
      throw AwsApiException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    if (response.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'items': decoded is List ? decoded : []};
    } catch (_) {
      return const {};
    }
  }

  static String _mimeFor(String ext) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'glb' => 'model/gltf-binary',
      'gltf' => 'model/gltf+json',
      'obj' => 'text/plain',
      'mtl' => 'text/plain',
      'bin' => 'application/octet-stream',
      'usdz' => 'model/vnd.usdz+zip',
      'spz' => 'application/octet-stream',
      'ply' => 'application/octet-stream',
      'sog' => 'application/octet-stream',
      'html' => 'text/html; charset=utf-8',
      _ => 'application/octet-stream',
    };
  }

  static String? _sanitizeFileName(String? fileName) {
    final raw = fileName?.trim();
    if (raw == null || raw.isEmpty) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? null : cleaned;
  }

  void dispose() => _http.close();
}

// ─── Exception ────────────────────────────────────────────────────────────────

class AwsApiException implements Exception {
  const AwsApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'AwsApiException($statusCode): $message';
}
