import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/data/models/rental_models.dart';

class Property3dScanService {
  Property3dScanService({
    String? backendUrl,
    String? provider,
    String? preset,
    String? outputFormat,
    Duration timeout = const Duration(seconds: 45),
  })  : _backendUrl = backendUrl ?? AppConfig.scan3dProxyUrl,
        _provider = provider ?? AppConfig.scan3dProvider,
        _preset = preset ?? AppConfig.scan3dDefaultPreset,
        _outputFormat = outputFormat ?? AppConfig.scan3dOutputFormat,
        _timeout = timeout;

  final String _backendUrl;
  final String _provider;
  final String _preset;
  final String _outputFormat;
  final Duration _timeout;

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

    final fileSize = await file.length();
    final contentType = _contentTypeForPath(sanitizedPath);
    final createPayload = {
      'propertyId': propertyId,
      'title': title.trim().isEmpty ? 'Rentch apartment scan' : title.trim(),
      'contentType': contentType,
      'fileSize': fileSize,
      'provider': _provider,
      'preset': _preset,
      'output': {
        'formats': [_outputFormat],
      },
    };

    final created = await _jsonRequest(
      'POST',
      _resolve('/scans'),
      body: createPayload,
    );
    final createdData = _data(created);
    final scanId = _stringValue(
      createdData,
      const ['scanId', 'sceneId', 'id'],
    );
    final uploadUrl = _stringValue(createdData, const ['uploadUrl']);
    if (scanId.isEmpty || uploadUrl.isEmpty) {
      throw const Property3dScanException(
        '3D scan backend did not return scanId/uploadUrl.',
      );
    }

    await _uploadToPresignedUrl(
      Uri.parse(uploadUrl),
      file,
      contentType: contentType,
    );

    await _jsonRequest('POST', _resolve('/scans/$scanId/process'));

    final status = await _jsonRequest('GET', _resolve('/scans/$scanId'));
    return _tourFromPayload(
      status,
      fallbackScanId: scanId,
      sourceVideoUrl: sanitizedPath,
      sizeBytes: fileSize,
    );
  }

  Future<PropertyVirtualTour> refresh(PropertyVirtualTour tour) async {
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
      final request = await client.openUrl(method, uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(_timeout);
      final responseBody =
          await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Property3dScanException(
          '3D scan backend returned ${response.statusCode}: $responseBody',
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
    final client = HttpClient();
    try {
      final request = await client.openUrl('PUT', uploadUrl).timeout(_timeout);
      request.headers.contentType = ContentType.parse(contentType);
      request.headers.set(HttpHeaders.contentLengthHeader, await file.length());
      await request.addStream(file.openRead()).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      final responseBody =
          await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Property3dScanException(
          '3D scan upload returned ${response.statusCode}: $responseBody',
        );
      }
    } on TimeoutException {
      throw const Property3dScanException('3D scan upload timed out.');
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
      'queued' || 'created' || 'pending' => PropertyTourStatus.queued,
      'failed' || 'error' => PropertyTourStatus.failed,
      _ => PropertyTourStatus.processing,
    };
  }

  String _contentTypeForPath(String path) {
    final ext = path.split('?').first.split('.').last.toLowerCase();
    return switch (ext) {
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'webm' => 'video/webm',
      _ => 'video/mp4',
    };
  }
}

class Property3dScanException implements Exception {
  const Property3dScanException(this.message);
  final String message;

  @override
  String toString() => 'Property3dScanException: $message';
}
