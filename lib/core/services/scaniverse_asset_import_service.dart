import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/core/services/scaniverse_service.dart';
import 'package:dating_app/data/models/rental_models.dart';

class ScaniverseAssetImportService {
  Future<ScaniverseImportedTour> importExportedModel({
    required String propertyId,
    required String title,
  }) async {
    final exportedAssets =
        await ScaniverseService.instance.pickExportedAssets();
    if (exportedAssets.isEmpty) {
      throw const ScaniverseAssetImportException('לא נבחרו קבצי 3D.');
    }

    if (!aws.isConfigured) {
      throw const ScaniverseAssetImportException(
        'AWS API לא מוגדר, אי אפשר להעלות מודל תלת־ממדי.',
      );
    }

    final uploadedAssets = <PropertyModelAsset>[];
    for (final asset in exportedAssets) {
      final publicUrl = await aws.uploadFile(
        asset.localPath,
        contentType: asset.contentType,
        folder: '3d-assets/$propertyId',
        fileName: asset.fileName,
      );
      if (publicUrl == null || publicUrl.trim().isEmpty) {
        throw ScaniverseAssetImportException(
          'העלאת הקובץ ${asset.fileName} נכשלה.',
        );
      }
      uploadedAssets.add(
        PropertyModelAsset(
          kind: asset.kind,
          url: publicUrl,
          fileName: asset.fileName,
          contentType: asset.contentType,
          sizeBytes: asset.sizeBytes,
        ),
      );
    }

    final response = await aws.post('/3d/viewers', {
      'propertyId': propertyId,
      'title': title,
      'assets': uploadedAssets.map((item) => item.toJson()).toList(),
    });
    final data = _data(response);
    final model3d = PropertyModel3d.fromJson(
      Map<String, dynamic>.from(
        data['model3d'] as Map? ??
            {
              'viewerUrl': data['viewerUrl'],
              'assets': uploadedAssets.map((item) => item.toJson()).toList(),
            },
      ),
    );
    final now = DateTime.now().toUtc();
    final format = data['format']?.toString() ?? _primaryFormat(uploadedAssets);
    final downloadUrl =
        data['downloadUrl']?.toString() ?? _primaryDownloadUrl(model3d);

    return ScaniverseImportedTour(
      tour: PropertyVirtualTour(
        id: data['scanId']?.toString() ?? 'import_$propertyId',
        provider: 'scaniverse-import',
        status: PropertyTourStatus.ready,
        viewerUrl: data['viewerUrl']?.toString() ?? model3d.viewerUrl,
        downloadUrl: downloadUrl,
        previewImageUrl: data['previewImageUrl']?.toString() ?? '',
        format: format,
        processingStage: 'ready',
        processingProgress: 100,
        sizeBytes: uploadedAssets.fold<int>(
          0,
          (sum, item) => sum + (item.sizeBytes ?? 0),
        ),
        createdAt: now,
        updatedAt: now,
      ),
      model3d: model3d.copyWith(
        assets: uploadedAssets,
        scanDate: model3d.scanDate ?? now,
      ),
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> payload) {
    final raw = payload['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return payload;
  }

  String _primaryFormat(List<PropertyModelAsset> assets) {
    for (final asset in assets) {
      if (asset.kind == 'glb' || asset.kind == 'usdz' || asset.kind == 'obj') {
        return asset.kind;
      }
    }
    return assets.isEmpty ? '' : assets.first.kind;
  }

  String _primaryDownloadUrl(PropertyModel3d model3d) {
    if (model3d.glbUrl.trim().isNotEmpty) return model3d.glbUrl;
    if (model3d.usdzUrl.trim().isNotEmpty) return model3d.usdzUrl;
    if (model3d.objUrl.trim().isNotEmpty) return model3d.objUrl;
    if (model3d.spzUrl.trim().isNotEmpty) return model3d.spzUrl;
    if (model3d.plyUrl.trim().isNotEmpty) return model3d.plyUrl;
    return '';
  }
}

class ScaniverseImportedTour {
  const ScaniverseImportedTour({
    required this.tour,
    required this.model3d,
  });

  final PropertyVirtualTour tour;
  final PropertyModel3d model3d;
}

class ScaniverseAssetImportException implements Exception {
  const ScaniverseAssetImportException(this.message);

  final String message;

  @override
  String toString() => 'ScaniverseAssetImportException: $message';
}
