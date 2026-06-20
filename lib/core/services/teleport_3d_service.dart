import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TeleportException implements Exception {
  const TeleportException(this.message);
  final String message;
  @override
  String toString() => 'TeleportException: $message';
}

/// Builds an interactive Gaussian-splat **3D walkthrough** of an apartment with
/// Varjo Teleport. The Teleport credentials live only on our backend; this
/// client talks to `/teleport/*` for the orchestration and uploads the video
/// chunks straight to the presigned S3 URLs the backend hands back.
///
/// Flow: create capture → for each part get a presigned URL + PUT the chunk
/// (collecting S3 ETags) → finalize → the capture processes (~1h) → poll until
/// `state == READY`, then `viewerUrl` is the embeddable 3D tour.
class Teleport3dService {
  Teleport3dService({AwsApiClient? api}) : _api = api ?? AwsApiClient.instance;

  final AwsApiClient _api;
  final http.Client _s3 = http.Client();

  static const String provider = 'teleport';

  bool get isConfigured => _api.isConfigured;

  /// Uploads [localVideoPath] (an mp4 of the apartment) and returns a tour in
  /// the processing state. [onProgress] reports upload progress in 0..1.
  Future<PropertyVirtualTour> createCaptureFromVideo({
    required String propertyId,
    required String name,
    required String localVideoPath,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(localVideoPath);
    if (!file.existsSync()) {
      throw const TeleportException('קובץ הווידאו לא נמצא.');
    }
    final size = await file.length();
    if (size <= 0) throw const TeleportException('קובץ הווידאו ריק.');

    try {
      // 1. Create the capture (declares the total size).
      final created = await _api.post('/teleport/captures', {
        'name': name.trim().isEmpty ? 'Rently apartment' : name.trim(),
        'bytesize': size,
      });
      final eid = (created['eid'] ?? '').toString();
      if (eid.isEmpty) {
        throw const TeleportException('לא הצלחתי להתחיל יצירת סיור 3D.');
      }
      final numParts = (created['numParts'] as num?)?.toInt() ?? 1;
      final chunkSize =
          (created['chunkSize'] as num?)?.toInt() ?? (10 * 1024 * 1024);

      // 2-3. Upload each part to its presigned S3 URL, collecting ETags.
      final parts = <Map<String, dynamic>>[];
      final raf = await file.open();
      try {
        for (var part = 1; part <= numParts; part++) {
          final offset = (part - 1) * chunkSize;
          final len = math.min(chunkSize, size - offset);
          if (len <= 0) break;
          await raf.setPosition(offset);
          final bytes = await raf.read(len);

          final urlResp = await _api.post(
            '/teleport/captures/$eid/upload-url/$part',
            {'bytesize': size},
          );
          final uploadUrl = (urlResp['uploadUrl'] ?? '').toString();
          if (uploadUrl.isEmpty) {
            throw const TeleportException('לא התקבלה כתובת העלאה.');
          }
          final etag = await _putPart(uploadUrl, bytes);
          parts.add({'number': part, 'etag': etag});
          onProgress?.call(part / numParts);
        }
      } finally {
        await raf.close();
      }

      // 4. Finalize → starts processing.
      final fin = await _api.post('/teleport/captures/$eid/finalize', {
        'parts': parts,
      });

      final now = DateTime.now().toUtc();
      return PropertyVirtualTour(
        id: eid, // Teleport capture id — used to poll later.
        provider: provider,
        status: _mapState((fin['state'] ?? 'PROCESSING').toString()),
        sourceVideoUrl: localVideoPath,
        viewerUrl: (fin['viewerUrl'] ?? '').toString(),
        processingStage: (fin['stateDescription'] ?? '').toString(),
        format: 'gaussian-splat',
        sizeBytes: size,
        createdAt: now,
        updatedAt: now,
      );
    } on TeleportException {
      rethrow;
    } on AwsApiException catch (e) {
      if (kDebugMode) debugPrint('Teleport createCapture AwsApiException: $e');
      if (e.statusCode == 401 || e.statusCode == 403) {
        throw const TeleportException(
            'צריך להתחבר לחשבון כדי ליצור סיור תלת-ממדי. התחבר ונסה שוב.');
      }
      throw const TeleportException(
          'השרת לא זמין כרגע ליצירת הסיור. נסה שוב בעוד רגע.');
    } on TimeoutException {
      throw const TeleportException(
          'ההעלאה לקחה יותר מדי זמן. בדוק את החיבור לאינטרנט ונסה שוב.');
    } catch (e) {
      if (kDebugMode) debugPrint('Teleport createCapture failed: $e');
      throw const TeleportException('יצירת הסיור התלת-ממדי נכשלה. נסה שוב.');
    }
  }

  /// Polls the capture's current state and returns an updated tour.
  Future<PropertyVirtualTour> refresh(PropertyVirtualTour tour) async {
    if (tour.id.isEmpty) return tour;
    final r = await _api.get('/teleport/captures/${tour.id}');
    if (r.isEmpty) return tour;
    final state = (r['state'] ?? '').toString();
    return tour.copyWith(
      status: _mapState(state),
      viewerUrl: (r['viewerUrl'] ?? tour.viewerUrl).toString(),
      previewImageUrl: (r['previewUrl'] ?? tour.previewImageUrl).toString(),
      processingStage: (r['stateDescription'] ?? tour.processingStage).toString(),
      errorMessage: (r['errorReason'] ?? '').toString(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// PUTs one chunk to the presigned S3 URL and returns its (unquoted) ETag,
  /// which Teleport needs to finalize the multipart upload.
  Future<String> _putPart(String uploadUrl, Uint8List bytes) async {
    final resp = await _s3
        .put(Uri.parse(uploadUrl), body: bytes)
        .timeout(const Duration(minutes: 10));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('Teleport S3 PUT failed: ${resp.statusCode} ${resp.body}');
      }
      throw const TeleportException('העלאת הווידאו נכשלה. נסה שוב.');
    }
    final raw = resp.headers['etag'] ?? resp.headers['ETag'] ?? '';
    final etag = raw.replaceAll('"', '').trim();
    if (etag.isEmpty) {
      throw const TeleportException('שרת האחסון לא החזיר אישור העלאה.');
    }
    return etag;
  }

  PropertyTourStatus _mapState(String state) {
    switch (state.toUpperCase()) {
      case 'READY':
      case 'DONE':
      case 'COMPLETE':
      case 'COMPLETED':
        return PropertyTourStatus.ready;
      case 'PROCESSING':
        return PropertyTourStatus.processing;
      case 'CREATED':
      case 'QUEUED':
      case 'UPLOADED':
        return PropertyTourStatus.queued;
      case 'ERROR':
      case 'FAILED':
        return PropertyTourStatus.failed;
      default:
        return PropertyTourStatus.processing;
    }
  }

  void dispose() => _s3.close();
}
