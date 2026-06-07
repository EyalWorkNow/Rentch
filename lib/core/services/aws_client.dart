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

      // 2. PUT directly to S3 (no auth headers needed for presigned URL)
      final bytes = await file.readAsBytes();
      final s3Response = await _http
          .put(
            Uri.parse(uploadUrl),
            headers: {'Content-Type': mime},
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));

      if (s3Response.statusCode >= 300) return null;
      return publicUrl;
    } catch (e) {
      if (kDebugMode) debugPrint('AwsApiClient.uploadFile error: $e');
      return null;
    }
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
