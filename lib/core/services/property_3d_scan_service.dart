import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/services/teleport_3d_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Property3dScanService {
  Property3dScanService({
    String? backendUrl,
    String? provider,
    String? outputFormat,
    Duration apiTimeout = const Duration(seconds: 45),
  })  : _backendUrl = backendUrl ?? AppConfig.scan3dProxyUrl,
        _provider = provider ?? AppConfig.scan3dProvider,
        _outputFormat = outputFormat ?? AppConfig.scan3dOutputFormat,
        _apiTimeout = apiTimeout;

  final String _backendUrl;
  final String _provider;
  final String _outputFormat;
  final Teleport3dService _teleport = Teleport3dService();
  // Timeout for lightweight API calls (create/process/status).
  final Duration _apiTimeout;

  // Upload timeout: 1 second per 50 KB, minimum 3 minutes, maximum 20 minutes.
  // Handles large videos on slow cellular without premature failure.
  Duration _uploadTimeoutFor(int fileSizeBytes) {
    final seconds = (fileSizeBytes / 50000).ceil();
    return Duration(
      seconds: seconds.clamp(180, 1200),
    );
  }

  bool get isConfigured =>
      AppConfig.enable3dScanning && _backendUrl.trim().isNotEmpty;

  PropertyVirtualTour localCapture({
    required String propertyId,
    required String localVideoPath,
    int? sizeBytes,
  }) {
    final now = DateTime.now().toUtc();
    return PropertyVirtualTour(
      id: 'tour_${propertyId}_${now.microsecondsSinceEpoch}',
      provider: _provider,
      status: PropertyTourStatus.captured,
      sourceVideoUrl: localVideoPath,
      format: _outputFormat,
      sizeBytes: sizeBytes,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<PropertyVirtualTour> submitScanVideo({
    required String propertyId,
    required String title,
    required String localVideoPath,
  }) async {
    if (!isConfigured) {
      throw const Property3dScanException(
        '3D scan backend is not configured.',
      );
    }

    final sanitizedPath = InputSanitizer.sanitizeMediaUrl(localVideoPath);
    if (sanitizedPath == null ||
        !InputSanitizer.isVideoExtensionAllowed(sanitizedPath)) {
      throw const Property3dScanException('Invalid scan video path.');
    }

    final file = File(sanitizedPath);
    if (!file.existsSync()) {
      throw const Property3dScanException('Scan video file was not found.');
    }

    // Build the real interactive 3D walkthrough with Varjo Teleport (chunked
    // upload straight to S3, then asynchronous Gaussian-splat processing).
    try {
      return await _teleport.createCaptureFromVideo(
        propertyId: propertyId,
        name: title.trim().isEmpty ? 'Rently apartment' : title.trim(),
        localVideoPath: sanitizedPath,
      );
    } on TeleportException catch (e) {
      throw Property3dScanException(e.message);
    }
  }

  /// Virtual staging ("הדמיה"): upload an apartment photo, run Luma uni-1
  /// image_edit to furnish/stage it, and return a tour whose previewImageUrl
  /// holds the staged image. Reuses the same /scans backend pipeline.
  Future<PropertyVirtualTour> submitStagingImage({
    required String propertyId,
    required String localImagePath,
    required String style,
  }) async {
    if (!isConfigured) {
      throw const Property3dScanException(
        'Staging backend is not configured.',
      );
    }

    final sanitizedPath = InputSanitizer.sanitizeMediaUrl(localImagePath);
    if (sanitizedPath == null) {
      throw const Property3dScanException('Invalid staging image path.');
    }

    final file = File(sanitizedPath);
    if (!file.existsSync()) {
      throw const Property3dScanException('Staging image file was not found.');
    }

    final fileSize = await file.length();
    final contentType = _imageContentTypeForPath(sanitizedPath);
    final createPayload = {
      'propertyId': propertyId,
      'contentType': contentType,
      'style': style,
      'fileSize': fileSize,
    };

    final created = await _jsonRequest(
      'POST',
      _resolve('/scans'),
      body: createPayload,
    );
    final createdData = _data(created);
    final scanId = _stringValue(createdData, const ['scanId', 'id']);
    final uploadUrl = _stringValue(createdData, const ['uploadUrl']);
    if (scanId.isEmpty || uploadUrl.isEmpty) {
      throw const Property3dScanException(
        'Staging backend did not return scanId/uploadUrl.',
      );
    }

    await _uploadToPresignedUrl(
      Uri.parse(uploadUrl),
      file,
      contentType: contentType,
    );

    final processResult = await _jsonRequest('POST', _resolve('/scans/$scanId/process'));

    final status = processResult.isNotEmpty
        ? processResult
        : await _jsonRequest('GET', _resolve('/scans/$scanId'));
    return _tourFromPayload(
      status,
      fallbackScanId: scanId,
      sourceVideoUrl: sanitizedPath,
      sizeBytes: fileSize,
    );
  }

  Future<PropertyVirtualTour> refresh(PropertyVirtualTour tour) async {
    // Teleport captures poll a different backend route.
    if (tour.provider == Teleport3dService.provider) {
      try {
        return await _teleport.refresh(tour);
      } on TeleportException {
        return tour;
      }
    }
    if (!isConfigured || tour.id.trim().isEmpty) return tour;
    final status = await _jsonRequest('GET', _resolve('/scans/${tour.id}'));
    return _tourFromPayload(
      status,
      fallbackScanId: tour.id,
      sourceVideoUrl: tour.sourceVideoUrl,
      sizeBytes: tour.sizeBytes,
    );
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri).timeout(_apiTimeout);
      request.headers.contentType = ContentType.json;
      final apiKey = AppConfig.awsApiKey.trim();
      if (apiKey.isNotEmpty) {
        request.headers.add('x-api-key', apiKey);
      }
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          if (token != null && token.isNotEmpty) {
            request.headers
                .add(HttpHeaders.authorizationHeader, 'Bearer $token');
          }
        }
      } catch (_) {}
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(_apiTimeout);
      final responseBody =
          await utf8.decoder.bind(response).join().timeout(_apiTimeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const Property3dScanException(
          'יש להתחבר לחשבון כדי להשתמש בתכונת הסריקה. אנא התחבר ונסה שוב.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Property3dScanException(
          'שגיאה בשרת הסריקה (${response.statusCode}). אנא נסה שוב מאוחר יותר.',
        );
      }
      if (responseBody.trim().isEmpty) return const {};
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const Property3dScanException('Unexpected 3D scan response shape.');
    } on TimeoutException {
      throw const Property3dScanException('3D scan backend timed out.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _uploadToPresignedUrl(
    Uri uploadUrl,
    File file, {
    required String contentType,
  }) async {
    final fileSize = await file.length();
    final uploadTimeout = _uploadTimeoutFor(fileSize);
    final client = HttpClient();
    try {
      final request =
          await client.openUrl('PUT', uploadUrl).timeout(_apiTimeout);
      request.headers.contentType = ContentType.parse(contentType);
      request.headers.set(HttpHeaders.contentLengthHeader, fileSize);
      // Stream upload uses the size-based timeout — large videos on slow
      // connections need minutes, not seconds.
      await request.addStream(file.openRead()).timeout(uploadTimeout);
      final response = await request.close().timeout(_apiTimeout);
      final responseBody =
          await utf8.decoder.bind(response).join().timeout(_apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Property3dScanException(
          '3D scan upload returned ${response.statusCode}: $responseBody',
        );
      }
    } on TimeoutException {
      throw Property3dScanException(
        'העלאת הוידאו נכשלה — הקובץ גדול מדי לחיבור הנוכחי. '
        'נסה שוב ב-WiFi או קצר את הסרטון.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Uri _resolve(String path) {
    final base = Uri.parse(_backendUrl.trim());
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return base.replace(
      path: [
        base.path.replaceFirst(RegExp(r'/$'), ''),
        normalizedPath,
      ].where((part) => part.isNotEmpty).join('/'),
    );
  }

  PropertyVirtualTour _tourFromPayload(
    Map<String, dynamic> payload, {
    required String fallbackScanId,
    required String sourceVideoUrl,
    required int? sizeBytes,
  }) {
    final data = _data(payload);
    final id = _stringValue(data, const ['id', 'scanId', 'sceneId']);
    final status = _statusFromProvider(data['status']);
    final now = DateTime.now().toUtc();
    final viewerUrl = _stringValue(data, const ['viewerUrl', 'viewer_url']);
    final downloadUrl =
        _stringValue(data, const ['downloadUrl', 'download_url']);
    final previewImageUrl = _stringValue(
      data,
      const ['previewImageUrl', 'preview_image_url', 'thumbnailUrl'],
    );

    return PropertyVirtualTour(
      id: id.isEmpty ? fallbackScanId : id,
      provider: _provider,
      status: status,
      sourceVideoUrl: sourceVideoUrl,
      viewerUrl: viewerUrl,
      downloadUrl: downloadUrl,
      previewImageUrl: previewImageUrl,
      format: _stringValue(data, const ['format']).isEmpty
          ? _outputFormat
          : _stringValue(data, const ['format']),
      processingStage:
          _stringValue(data, const ['processingStage', 'processing_stage']),
      processingProgress: _intValue(
        data,
        const ['processingProgress', 'processing_pct'],
      ),
      qualityScore: _doubleValue(data, const ['ssim', 'ssim_holdout']),
      sizeBytes: sizeBytes,
      errorMessage:
          _stringValue(data, const ['processingError', 'processing_error']),
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> payload) {
    final raw = payload['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return payload;
  }

  String _stringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  int? _intValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  double? _doubleValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is double) return value;
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  PropertyTourStatus _statusFromProvider(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'complete' || 'completed' || 'ready' => PropertyTourStatus.ready,
      'training' || 'processing' || 'running' => PropertyTourStatus.processing,
      'queued' || 'created' || 'pending' || 'draft' => PropertyTourStatus.queued,
      'failed' || 'error' => PropertyTourStatus.failed,
      _ => PropertyTourStatus.failed,
    };
  }

  String _imageContentTypeForPath(String path) {
    final ext = path.split('?').first.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }
}

class Property3dScanException implements Exception {
  const Property3dScanException(this.message);
  final String message;

  @override
  String toString() => 'Property3dScanException: $message';
}
