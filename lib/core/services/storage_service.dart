import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class StorageService {
  static const _bucketId = appwriteStorageBucketId;

  Storage? _storage;

  Storage get _cloudStorage => _storage ??= Storage(client);

  Future<String> saveImageLocally(
    XFile file, {
    String folderName = 'profile_photos',
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$folderName');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final dest = '${folder.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(file.path).copy(dest);
    return dest;
  }

  Future<String?> uploadToCloud(String localPath) async {
    if (!AppConfig.canUseCloudStorage) return null;

    try {
      final fileId = ID.unique();
      final uploaded = await _cloudStorage.createFile(
        bucketId: _bucketId,
        fileId: fileId,
        file: InputFile.fromPath(path: localPath),
      );
      return '$appwritePublicEndpoint/storage/buckets/$_bucketId'
          '/files/${uploaded.$id}/view?project=$appwriteProjectId';
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Appwrite image upload failed: $error');
      }
      return null;
    }
  }

  Future<void> deleteFromCloud(String fileUrl) async {
    if (!AppConfig.canUseCloudStorage) return;

    try {
      final uri = Uri.parse(fileUrl);
      final segments = uri.pathSegments;
      final filesIdx = segments.indexOf('files');
      if (filesIdx == -1 || filesIdx + 1 >= segments.length) return;
      final fileId = segments[filesIdx + 1];
      await _cloudStorage.deleteFile(bucketId: _bucketId, fileId: fileId);
    } catch (_) {}
  }
}
