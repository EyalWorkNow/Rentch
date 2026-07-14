import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/models/scanned_room.dart';
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

  test('PropertyModel3d round-trips the per-room list and viewableRooms', () {
    const model = PropertyModel3d(
      rooms: [
        ScannedRoom(name: 'סלון', splatUrl: 'https://example.com/salon.splat'),
        ScannedRoom(name: 'מטבח', meshGlbUrl: 'https://example.com/kitchen.glb'),
        // A RoomPlan-only capture with no viewable asset — must be excluded from
        // viewableRooms so the room-switcher never offers a blank room.
        ScannedRoom(name: 'חדר שינה', usdzPath: '/tmp/bed.usdz', source: 'roomplan'),
      ],
    );

    final decoded = PropertyModel3d.fromJson(model.toJson());

    expect(decoded.rooms, hasLength(3));
    expect(decoded.rooms.map((r) => r.name),
        containsAllInOrder(['סלון', 'מטבח', 'חדר שינה']));
    expect(decoded.rooms[0].splatUrl, 'https://example.com/salon.splat');
    expect(decoded.rooms[1].meshGlbUrl, 'https://example.com/kitchen.glb');
    expect(decoded.viewableRooms, hasLength(2)); // usdz-only room dropped
    expect(decoded.hasAnyAsset, isTrue);
  });
}
