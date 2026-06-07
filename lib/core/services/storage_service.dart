import 'dart:io';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart';
import 'package:dating_app/core/security/security_config.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class StorageService {

  // Returns the local path on success, throws [StorageException] on rejection.
  Future<String> saveImageLocally(
    XFile file, {
    String folderName = 'profile_photos',
  }) =>
      _saveMediaLocally(
        file,
        folderName: folderName,
        isVideo: false,
      );

  Future<String> saveVideoLocally(
    XFile file, {
    String folderName = 'property_videos',
  }) =>
      _saveMediaLocally(
        file,
        folderName: folderName,
        isVideo: true,
      );

  Future<String> _saveMediaLocally(
    XFile file, {
    required String folderName,
    required bool isVideo,
  }) async {
    if (isVideo) {
      if (!InputSanitizer.isVideoExtensionAllowed(file.path)) {
        throw StorageException(
          'File type not allowed. Use MP4, MOV, M4V, or WebM.',
        );
      }
    } else if (!InputSanitizer.isImageExtensionAllowed(file.path)) {
      throw StorageException(
        'File type not allowed. Use JPG, PNG, WebP, or HEIC.',
      );
    }

    final bytes = await file.length();
    final isAllowed = isVideo
        ? InputSanitizer.isVideoFileSizeAllowed(bytes)
        : InputSanitizer.isImageFileSizeAllowed(bytes);
    if (!isAllowed) {
      final limit = isVideo
          ? SecurityConfig.maxVideoSizeBytes
          : SecurityConfig.maxImageSizeBytes;
      final maxMb = limit ~/ (1024 * 1024);
      final mediaLabel = isVideo ? 'Video' : 'Image';
      throw StorageException('$mediaLabel must be under ${maxMb}MB.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$folderName');
    if (!folder.existsSync()) folder.createSync(recursive: true);

    final extension = file.path.split('.').last.toLowerCase();
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final dest = '${folder.path}/$fileName';

    if (!dest.startsWith(dir.path)) {
      throw StorageException('Invalid save destination.');
    }

    await File(file.path).copy(dest);
    return dest;
  }

  Future<String?> uploadToCloud(String localPath) async {
    if (!AppConfig.canUseCloudStorage) return null;

    if (!RateLimiter.instance.allowImageUpload()) {
      if (kDebugMode) debugPrint('StorageService: image upload rate limit hit');
      return null;
    }

    if (!InputSanitizer.isValidLocalMediaPathSync(localPath)) {
      if (kDebugMode) {
        debugPrint('StorageService: rejected suspicious path: $localPath');
      }
      return null;
    }

    try {
      return await aws.uploadFile(localPath, folder: 'uploads');
    } catch (error) {
      if (kDebugMode) debugPrint('StorageService: upload failed: $error');
      return null;
    }
  }

  Future<void> deleteFromCloud(String fileUrl) async {
    if (!AppConfig.canUseCloudStorage) return;
    final sanitized = InputSanitizer.sanitizeMediaUrl(fileUrl);
    if (sanitized == null) return;
    try {
      final uri = Uri.parse(sanitized);
      // Extract S3 key from the URL path (everything after the bucket hostname).
      // e.g. https://bucket.s3.region.amazonaws.com/uploads/123.jpg → uploads/123.jpg
      final key = uri.pathSegments.join('/');
      if (key.isEmpty) return;
      await aws.delete('/storage/$key');
    } catch (_) {}
  }
}

class StorageException implements Exception {
  StorageException(this.message);
  final String message;
  @override
  String toString() => 'StorageException: $message';
}
