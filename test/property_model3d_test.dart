import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PropertyModel3d preserves extended asset manifest fields', () {
    final model = PropertyModel3d(
      viewerUrl: 'https://example.com/viewer.html',
      glbUrl: 'https://example.com/model.glb',
      objUrl: 'https://example.com/model.obj',
      mtlUrl: 'https://example.com/model.mtl',
      usdzUrl: 'https://example.com/model.usdz',
      spzUrl: 'https://example.com/model.spz',
      plyUrl: 'https://example.com/model.ply',
      textureFolder: 'https://example.com/textures/',
      assets: const [
        PropertyModelAsset(
          kind: 'glb',
          url: 'https://example.com/model.glb',
          fileName: 'model.glb',
          contentType: 'model/gltf-binary',
          sizeBytes: 42,
        ),
      ],
    );

    final decoded = PropertyModel3d.fromJson(model.toJson());

    expect(decoded.viewerUrl, model.viewerUrl);
    expect(decoded.glbUrl, model.glbUrl);
    expect(decoded.objUrl, model.objUrl);
    expect(decoded.mtlUrl, model.mtlUrl);
    expect(decoded.usdzUrl, model.usdzUrl);
    expect(decoded.spzUrl, model.spzUrl);
    expect(decoded.plyUrl, model.plyUrl);
    expect(decoded.textureFolder, model.textureFolder);
    expect(decoded.assets, hasLength(1));
    expect(decoded.assets.first.kind, 'glb');
    expect(decoded.assets.first.fileName, 'model.glb');
    expect(decoded.hasAnyAsset, isTrue);
  });
}
