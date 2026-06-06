import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/secure_storage_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// Niantic Spatial / Scaniverse Portal API client.
//
// Auth flow (token NEVER hardcoded in source):
//   1. First run: pass SPATIAL_API_KEY via --dart-define at build time.
//   2. Service writes it to iOS Keychain / Android EncryptedPrefs on init().
//   3. Subsequent runs: reads from secure storage — no dart-define needed.
//   4. Rotation: call updateToken() with a fresh JWT.
//
// API base: https://portal-backend-api.nianticpatial.com
// Scopes needed: scaniverse-portal, vps
class ScaniverseService {
  static const String _portalBase =
      'https://portal-backend-api.nianticpatial.com';
  static const Duration _timeout = Duration(seconds: 20);
  static const String _storageKey = 'spatial_api_key';

  final SecureStorageService _secure;
  String? _cachedToken;
  static ScaniverseService? _instance;

  ScaniverseService({SecureStorageService? secureStorage})
      : _secure = secureStorage ?? SecureStorageService();

  static ScaniverseService get instance {
    _instance ??= ScaniverseService();
    return _instance!;
  }

  // Call once at app startup.
  // If SPATIAL_API_KEY dart-define is set, it seeds/overwrites the Keychain.
  Future<void> initialize() async {
    const envToken = AppConfig.spatialApiKey;
    if (envToken.isNotEmpty) {
      await _secure.writeString(_storageKey, envToken);
      _cachedToken = envToken;
      if (kDebugMode) {
        debugPrint('ScaniverseService: token seeded from dart-define → Keychain');
      }
    } else {
      _cachedToken = await _secure.readString(_storageKey);
      if (kDebugMode) {
        debugPrint(
          'ScaniverseService: token ${_cachedToken != null ? "loaded from Keychain" : "NOT configured"}',
        );
      }
    }
  }

  Future<void> updateToken(String token) async {
    _cachedToken = token.trim();
    await _secure.writeString(_storageKey, token.trim());
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _secure.delete(_storageKey);
  }

  bool get isConfigured => (_cachedToken ?? '').trim().isNotEmpty;

  // List scans for the authenticated service account.
  Future<List<ScaniverseScan>> listScans({int limit = 20}) async {
    final response = await _get('/api/v1/scans', params: {'limit': '$limit'});

    // Handle multiple Niantic API response shapes
    final raw = response['items'] ??
        response['scans'] ??
        response['data'] ??
        response['results'] ??
        [];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => ScaniverseScan.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  // Get a specific scan by ID.
  Future<ScaniverseScan> getScan(String scanId) async {
    final response = await _get('/api/v1/scans/$scanId');
    final data = response['data'] ?? response['scan'] ?? response;
    if (data is! Map) throw ScaniverseException('Unexpected scan response.');
    return ScaniverseScan.fromJson(Map<String, dynamic>.from(data));
  }

  // Convert a ScaniverseScan to a PropertyVirtualTour.
  PropertyVirtualTour tourFromScan(ScaniverseScan scan) {
    final now = DateTime.now().toUtc();
    final status = switch (scan.status.toLowerCase()) {
      'complete' || 'completed' || 'ready' => PropertyTourStatus.ready,
      'failed' || 'error' => PropertyTourStatus.failed,
      'queued' || 'created' || 'pending' => PropertyTourStatus.queued,
      _ => PropertyTourStatus.processing,
    };
    return PropertyVirtualTour(
      id: scan.id,
      provider: 'scaniverse',
      status: status,
      viewerUrl: scan.viewerUrl,
      downloadUrl: scan.downloadUrl ?? '',
      previewImageUrl: scan.thumbnailUrl ?? '',
      format: 'scaniverse',
      processingProgress: scan.progressPct,
      qualityScore: scan.qualityScore,
      createdAt: scan.createdAt ?? now,
      updatedAt: scan.updatedAt ?? now,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? params,
  }) async {
    final token = _cachedToken?.trim() ?? '';
    if (token.isEmpty) {
      throw const ScaniverseException(
        'Spatial API key not configured. Pass SPATIAL_API_KEY via dart-define.',
      );
    }

    var uri = Uri.parse('$_portalBase$path');
    if (params != null && params.isNotEmpty) {
      uri = uri.replace(queryParameters: params);
    }

    final client = HttpClient();
    try {
      final request = await client.openUrl('GET', uri).timeout(_timeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set('Accept', 'application/json');

      final response = await request.close().timeout(_timeout);
      final body =
          await utf8.decoder.bind(response).join().timeout(_timeout);

      if (kDebugMode) {
        debugPrint(
          'ScaniverseService GET $path → HTTP ${response.statusCode}',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ScaniverseException(
          'Spatial API key is invalid or expired. Generate a new Developer Token in the Niantic Portal.',
        );
      }
      if (response.statusCode == 404) {
        throw ScaniverseException('Resource not found: $path');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ScaniverseException(
          'Spatial API error ${response.statusCode}: $body',
        );
      }

      if (body.trim().isEmpty) return const {};
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      // Bare list response
      if (decoded is List) return {'items': decoded};
      return const {};
    } on TimeoutException {
      throw const ScaniverseException(
        'Spatial API request timed out. Check your connection.',
      );
    } on ScaniverseException {
      rethrow;
    } catch (e) {
      throw ScaniverseException('Spatial API unexpected error: $e');
    } finally {
      client.close(force: true);
    }
  }
}

class ScaniverseScan {
  const ScaniverseScan({
    required this.id,
    required this.title,
    required this.viewerUrl,
    required this.status,
    this.thumbnailUrl,
    this.downloadUrl,
    this.progressPct,
    this.qualityScore,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String viewerUrl;
  final String status;
  final String? thumbnailUrl;
  final String? downloadUrl;
  final int? progressPct;
  final double? qualityScore;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isReady =>
      status == 'complete' || status == 'completed' || status == 'ready';
  bool get isProcessing =>
      status == 'processing' ||
      status == 'training' ||
      status == 'queued' ||
      status == 'created';

  factory ScaniverseScan.fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString() ??
        j['scanId']?.toString() ??
        j['sceneId']?.toString() ??
        '';
    // Construct viewer URL: prefer explicit field, fall back to canonical Scaniverse URL
    final viewerUrl = j['viewerUrl']?.toString() ??
        j['viewer_url']?.toString() ??
        j['url']?.toString() ??
        (id.isNotEmpty ? 'https://scaniverse.com/scan/$id' : '');

    return ScaniverseScan(
      id: id,
      title: j['title']?.toString() ??
          j['name']?.toString() ??
          j['displayName']?.toString() ??
          'Scan $id',
      viewerUrl: viewerUrl,
      status: j['status']?.toString() ?? 'processing',
      thumbnailUrl: j['thumbnailUrl']?.toString() ??
          j['thumbnail_url']?.toString() ??
          j['previewImageUrl']?.toString() ??
          j['preview_url']?.toString(),
      downloadUrl: j['downloadUrl']?.toString() ??
          j['download_url']?.toString() ??
          j['glbUrl']?.toString(),
      progressPct: _parseInt(
        j['progressPct'] ?? j['processing_pct'] ?? j['progress'],
      ),
      qualityScore: _parseDouble(j['qualityScore'] ?? j['ssim']),
      createdAt: _parseDate(j['createdAt'] ?? j['created_at']),
      updatedAt: _parseDate(j['updatedAt'] ?? j['updated_at']),
    );
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _parseDouble(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _parseDate(Object? v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}

class ScaniverseException implements Exception {
  const ScaniverseException(this.message);
  final String message;

  @override
  String toString() => 'ScaniverseException: $message';
}
