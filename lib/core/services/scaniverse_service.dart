import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/secure_storage_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Niantic Spatial / Scaniverse SDK bridge.
//
// Architecture:
//   Flutter (Dart) ──MethodChannel──▶ Swift (ScaniversePlugin.swift)
//                                     └──▶ NSDK (nianticspatial SPM package)
//                                           └──▶ CArdk.xcframework (C++ binary)
//
// Sites API hierarchy:
//   NSDKSession → NSDKSitesSession
//     requestSelfOrganizationInfo()      → OrganizationInfo
//     requestSitesForOrganization(orgId) → [SiteInfo]
//     requestAssetsForSite(siteId)       → [AssetInfo] (mesh / splat)
//
// Token flow: dart-define SPATIAL_API_KEY → Keychain on first launch.
// Subsequent launches read from Keychain (no dart-define needed).

class ScaniverseService {
  static const MethodChannel _channel = MethodChannel('com.rently.scaniverse');
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

  /// Call once at app startup.
  /// Seeds SPATIAL_API_KEY dart-define into Keychain on first run.
  Future<void> initialize() async {
    const envToken = AppConfig.spatialApiKey;
    if (envToken.isNotEmpty) {
      await _secure.writeString(_storageKey, envToken);
      _cachedToken = envToken;
      if (kDebugMode) {
        debugPrint(
            'ScaniverseService: token seeded from dart-define → Keychain');
      }
    } else {
      _cachedToken = await _secure.readString(_storageKey);
      if (kDebugMode) {
        debugPrint(
          'ScaniverseService: token '
          '${_cachedToken != null ? "loaded from Keychain" : "NOT configured"}',
        );
      }
    }

    // Verify the native channel is reachable
    if (kDebugMode) {
      try {
        final pong = await _channel.invokeMethod<Map>('ping');
        debugPrint('ScaniverseService: channel ping → $pong');
      } catch (e) {
        debugPrint('ScaniverseService: channel ping failed — $e');
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

  Future<List<ScaniverseExportedAsset>> pickExportedAssets() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('pick3dAssets');
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map((item) =>
              ScaniverseExportedAsset.fromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on PlatformException catch (e) {
      throw ScaniverseException('Asset picker error ${e.code}: ${e.message}');
    } catch (e) {
      throw ScaniverseException('Asset picker failed: $e');
    }
  }

  /// List 3D scans (Assets of type splat/mesh) from the authenticated account.
  /// Calls the native NSDK Sites API via MethodChannel.
  Future<List<ScaniverseScan>> listScans({int limit = 30}) async {
    final token = _cachedToken?.trim() ?? '';
    if (token.isEmpty) {
      throw const ScaniverseException(
        'Spatial API key not configured. Pass SPATIAL_API_KEY via dart-define.',
      );
    }

    try {
      final result =
          await _channel.invokeMethod<Map>('listScans', {'token': token});
      if (result == null) return const [];

      final sdkReady = result['sdkReady'] as bool? ?? true;
      if (!sdkReady) {
        // SDK stub — NSDK package not yet added in Xcode
        if (kDebugMode) debugPrint('ScaniverseService: ${result["hint"]}');
        return const [];
      }

      final raw = result['scans'] as List? ?? [];
      return raw
          .whereType<Map>()
          .map((m) => ScaniverseScan.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } on PlatformException catch (e) {
      throw ScaniverseException('NSDK error ${e.code}: ${e.message}');
    } catch (e) {
      throw ScaniverseException('Channel error: $e');
    }
  }

  /// Convert a ScaniverseScan to a PropertyVirtualTour for use in the app.
  PropertyVirtualTour tourFromScan(ScaniverseScan scan) {
    final now = DateTime.now().toUtc();
    final status = switch (scan.status.toLowerCase()) {
      'complete' || 'ready' => PropertyTourStatus.ready,
      'failed' => PropertyTourStatus.failed,
      'pending' => PropertyTourStatus.queued,
      _ => PropertyTourStatus.processing,
    };
    return PropertyVirtualTour(
      id: scan.id,
      provider: 'scaniverse',
      status: status,
      viewerUrl: scan.viewerUrl,
      downloadUrl: '',
      previewImageUrl: scan.thumbnailUrl ?? '',
      format: scan.assetType,
      createdAt: now,
      updatedAt: now,
    );
  }
}

// ─── Data model returned from native plugin ───────────────────────────────────

class ScaniverseScan {
  const ScaniverseScan({
    required this.id,
    required this.title,
    required this.viewerUrl,
    required this.status,
    required this.assetType,
    this.siteId = '',
    this.siteName = '',
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String viewerUrl;
  final String status;
  final String assetType; // 'splat' | 'mesh'
  final String siteId;
  final String siteName;
  final String? thumbnailUrl;

  bool get isReady => status == 'complete' || status == 'ready';
  bool get isProcessing =>
      status == 'processing' || status == 'pending' || status == 'running';

  factory ScaniverseScan.fromMap(Map<String, dynamic> m) {
    return ScaniverseScan(
      id: m['id']?.toString() ?? '',
      title: m['title']?.toString() ?? m['siteName']?.toString() ?? 'Scan',
      viewerUrl: m['viewerUrl']?.toString() ?? '',
      status: m['status']?.toString() ?? 'processing',
      assetType: m['assetType']?.toString() ?? 'splat',
      siteId: m['siteId']?.toString() ?? '',
      siteName: m['siteName']?.toString() ?? '',
      thumbnailUrl: m['thumbnailUrl']?.toString(),
    );
  }
}

class ScaniverseExportedAsset {
  const ScaniverseExportedAsset({
    required this.localPath,
    required this.fileName,
    required this.kind,
    required this.contentType,
    this.sizeBytes,
  });

  final String localPath;
  final String fileName;
  final String kind;
  final String contentType;
  final int? sizeBytes;

  factory ScaniverseExportedAsset.fromMap(Map<String, dynamic> m) {
    return ScaniverseExportedAsset(
      localPath: m['path']?.toString() ?? '',
      fileName: m['fileName']?.toString() ?? '',
      kind: m['kind']?.toString() ?? '',
      contentType: m['contentType']?.toString() ?? 'application/octet-stream',
      sizeBytes: m['sizeBytes'] is num ? (m['sizeBytes'] as num).round() : null,
    );
  }
}

class ScaniverseException implements Exception {
  const ScaniverseException(this.message);
  final String message;

  @override
  String toString() => 'ScaniverseException: $message';
}
