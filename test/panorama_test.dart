import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_capture_screen.dart';
import 'package:dating_app/presentation/features/panorama/panorama_experience_view.dart';
import 'package:dating_app/presentation/features/panorama/panorama_web_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PropertyPanoramaTour _twoNodeTour() => const PropertyPanoramaTour(nodes: [
      PanoramaNode(
        id: 'a',
        imageUrl: 'https://example.com/a.jpg',
        label: 'סלון',
        hotspots: [PanoramaHotspot(targetNodeId: 'b', label: 'מטבח')],
      ),
      PanoramaNode(
        id: 'b',
        imageUrl: 'https://example.com/b.jpg',
        label: 'מטבח',
        hotspots: [PanoramaHotspot(targetNodeId: 'a', longitude: 180, label: 'חזרה')],
      ),
    ]);

Widget _wrap(Widget child) => MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );

void main() {
  // ── model logic ──────────────────────────────────────────────────────────────
  group('PropertyPanoramaTour model', () {
    test('nodeById + isLocal + counts', () {
      final t = _twoNodeTour();
      expect(t.length, 2);
      expect(t.first!.id, 'a');
      expect(t.nodeById('b')!.label, 'מטבח');
      expect(t.nodeById('zzz'), isNull);
      expect(
          const PanoramaNode(id: 'x', imageUrl: '/data/p.jpg').isLocal, true);
      expect(t.nodeById('a')!.isLocal, false);
    });

    test('JSON round-trips losslessly', () {
      final t = _twoNodeTour();
      final restored = PropertyPanoramaTour.fromJsonOrNull(t.toJson());
      expect(restored, isNotNull);
      expect(restored!.length, 2);
      expect(restored.nodeById('a')!.hotspots.first.targetNodeId, 'b');
      expect(restored.nodeById('b')!.hotspots.first.longitude, 180);
    });

    test('position + haov/vaov round-trip; defaults omitted', () {
      const n = PanoramaNode(
          id: 'p', imageUrl: '/x.jpg', x: 0.3, y: 0.7, haov: 120, vaov: 90);
      final j = n.toJson();
      expect(j['x'], 0.3);
      expect(j['y'], 0.7);
      expect(j['haov'], 120);
      expect(j['vaov'], 90);
      final back = PanoramaNode.fromJson(j);
      expect(back.hasPosition, true);
      expect(back.haov, 120);
      // full-sphere defaults are not serialized
      const full = PanoramaNode(id: 'q', imageUrl: '/y.jpg');
      expect(full.toJson().containsKey('haov'), false);
      expect(full.hasPosition, false);
    });

    test('fromJsonOrNull is tolerant of junk / empties', () {
      expect(PropertyPanoramaTour.fromJsonOrNull(null), isNull);
      expect(PropertyPanoramaTour.fromJsonOrNull({'nodes': []}), isNull);
      // nodes missing an imageUrl are dropped
      expect(
        PropertyPanoramaTour.fromJsonOrNull({
          'nodes': [
            {'id': 'a', 'imageUrl': ''}
          ]
        }),
        isNull,
      );
    });
  });

  // ── Pannellum web-tour config (the Street-View viewer data) ──────────────────
  group('Pannellum tour config', () {
    PropertyPanoramaTour threeNodes() => const PropertyPanoramaTour(nodes: [
          PanoramaNode(id: 'a', imageUrl: 'https://x/a.jpg', label: 'סלון', hotspots: [
            PanoramaHotspot(targetNodeId: 'b', longitude: 0, latitude: -8, label: 'מטבח'),
          ]),
          PanoramaNode(id: 'b', imageUrl: 'https://x/b.jpg', label: 'מטבח', hotspots: [
            PanoramaHotspot(targetNodeId: 'c', longitude: 0, latitude: -8, label: 'חדר'),
            PanoramaHotspot(targetNodeId: 'a', longitude: 180, latitude: -8, label: 'חזרה'),
          ]),
          PanoramaNode(id: 'c', imageUrl: 'https://x/c.jpg', label: 'חדר', hotspots: [
            PanoramaHotspot(targetNodeId: 'b', longitude: 180, latitude: -8, label: 'חזרה'),
          ]),
        ]);

    test('builds one scene per node with the right panorama + links', () {
      final cfg = pannellumTourConfig(threeNodes(), imageUrlFor: (id) => '/img/$id');
      final scenes = cfg['scenes'] as Map<String, dynamic>;
      expect(scenes.length, 3);
      expect((cfg['default'] as Map)['firstScene'], 'a');

      final a = scenes['a'] as Map<String, dynamic>;
      expect(a['panorama'], '/img/a');
      expect(a['type'], 'equirectangular');
      expect(a['title'], 'סלון');
      final aSpots = a['hotSpots'] as List;
      expect(aSpots.length, 1);
      expect(aSpots.first['type'], 'scene');
      expect(aSpots.first['sceneId'], 'b');
      expect(aSpots.first['yaw'], 0);
      expect(aSpots.first['pitch'], -8);
    });

    test('heading continuity: arrive facing forward (away from the back-link)', () {
      final t = threeNodes();
      // entering b from a: b's back-link to a sits at 180 ⇒ arrive facing 0
      expect(pannellumArrivalYaw(t, t.nodeById('b')!, 'a'), 0);
      // entering a from b: a's link to b sits at 0 ⇒ arrive facing 180
      expect(pannellumArrivalYaw(t, t.nodeById('a')!, 'b'), 180);
    });

    test('partial panoramas declare haov/vaov; full ones omit them', () {
      final t = PropertyPanoramaTour(nodes: const [
        PanoramaNode(id: 'wide', imageUrl: 'https://x/w.jpg', haov: 120, vaov: 90),
        PanoramaNode(id: 'full', imageUrl: 'https://x/f.jpg'),
      ]);
      final scenes = pannellumTourConfig(t, imageUrlFor: (id) => '/img/$id')['scenes']
          as Map<String, dynamic>;
      expect((scenes['wide'] as Map)['haov'], 120);
      expect((scenes['wide'] as Map)['vaov'], 90);
      expect((scenes['full'] as Map).containsKey('haov'), false);
    });

    test('drops scenes + links for nodes whose image failed to load', () {
      // c's image didn't load ⇒ scene c gone AND b's link to c removed
      final cfg = pannellumTourConfig(threeNodes(),
          imageUrlFor: (id) => '/img/$id', available: {'a', 'b'});
      final scenes = cfg['scenes'] as Map<String, dynamic>;
      expect(scenes.containsKey('c'), false);
      expect(scenes.length, 2);
      final bSpots = (scenes['b'] as Map)['hotSpots'] as List;
      expect(bSpots.length, 1); // only the back-link to a survives
      expect(bSpots.first['sceneId'], 'a');
    });
  });

  // ── capture screen builds + guides ───────────────────────────────────────────
  testWidgets('capture screen builds with guidance and add buttons',
      (tester) async {
    await tester.pumpWidget(_wrap(const PanoramaCaptureScreen()));
    // Single "add point" action (opens the guide) + empty state + app-bar title.
    expect(find.text('הוסף פנורמה'), findsOneWidget);
    expect(find.textContaining('עוד לא הוספת'), findsOneWidget);
    expect(find.text('צילום סיור 360°'), findsOneWidget); // app-bar title
  });

  // ── viewer builds + node navigation state ────────────────────────────────────
  // Network images can't load in the headless test binding (they throw); we
  // drain those image exceptions and verify the *navigation logic* (title +
  // point selector) which is independent of the GL panorama render.
  testWidgets('360 experience builds and walks between points', (tester) async {
    await tester.pumpWidget(_wrap(PanoramaExperienceView(tour: _twoNodeTour())));
    await tester.pump();
    tester.takeException(); // unreachable network images throw in the test binding

    expect(find.textContaining('· סלון'), findsOneWidget);
    expect(find.text('סלון'), findsWidgets);
    expect(find.text('מטבח'), findsWidgets);

    // tap the second room → transition runs and the active node switches
    await tester.tap(find.text('מטבח').last);
    await tester.pump(); // kick off the transition
    await tester.pump(const Duration(milliseconds: 700)); // let it settle
    tester.takeException();
    expect(find.textContaining('· מטבח'), findsOneWidget);
  });

  group('PanoramaNode versions', () {
    const original = PanoramaNode(
      id: 'a',
      imageUrl: 'https://example.com/raw.jpg',
      label: 'סלון',
      haov: 200,
      vaov: 90, // a partial pano
    );

    test('legacy node synthesizes a single מקור version', () {
      expect(original.hasMultipleVersions, isFalse);
      expect(original.allVersions, hasLength(1));
      expect(original.allVersions.single.source, 'מקור');
      expect(original.allVersions.single.imageUrl, original.imageUrl);
    });

    test('addVersion is non-destructive and activates the new render', () {
      final enhanced = original.addVersion(const PanoVersion(
        imageUrl: 'https://example.com/enhanced.jpg',
        haov: 360,
        vaov: 180,
        source: 'משופר ✨',
      ));

      // Two versions now; the original is preserved as version 0.
      expect(enhanced.allVersions, hasLength(2));
      expect(enhanced.allVersions[0].imageUrl, 'https://example.com/raw.jpg');
      // Active fields mirror the new (enhanced) version so viewers update.
      expect(enhanced.activeVersion, 1);
      expect(enhanced.imageUrl, 'https://example.com/enhanced.jpg');
      expect(enhanced.haov, 360);
      expect(enhanced.vaov, 180);

      // Flip back to the original — image + FOV revert, nothing is lost.
      final reverted = enhanced.selectVersion(0);
      expect(reverted.imageUrl, 'https://example.com/raw.jpg');
      expect(reverted.haov, 200);
      expect(reverted.vaov, 90);
      expect(reverted.allVersions, hasLength(2)); // enhanced still available
    });

    test('versions survive a JSON round-trip; single-version stays lean', () {
      final enhanced = original.addVersion(const PanoVersion(
        imageUrl: 'https://example.com/enhanced.jpg',
        source: 'משופר ✨',
      ));
      final decoded = PanoramaNode.fromJson(enhanced.toJson());
      expect(decoded.allVersions, hasLength(2));
      expect(decoded.activeVersion, 1);
      expect(decoded.allVersions[1].source, 'משופר ✨');

      // A single-render node must NOT bloat the JSON with a versions array.
      expect(original.toJson().containsKey('versions'), isFalse);
    });

    test('viewer visibility: landlord hides a version from tenants', () {
      final node = original.addVersion(const PanoVersion(
        imageUrl: 'https://example.com/enhanced.jpg',
        source: 'משופר ✨',
      ));
      // Both visible by default → tenant switcher offers both.
      expect(node.viewerVersions, hasLength(2));

      // Hide the enhanced one → tenants only see 'מקור'.
      final hiddenEnhanced = node.toggleVersionHidden(1);
      expect(hiddenEnhanced.allVersions[1].hidden, isTrue);
      expect(hiddenEnhanced.viewerVersions, hasLength(1));
      expect(hiddenEnhanced.viewerVersions.single.source, 'מקור');

      // Hidden flag survives a JSON round-trip.
      final decoded = PanoramaNode.fromJson(hiddenEnhanced.toJson());
      expect(decoded.viewerVersions, hasLength(1));
    });

    test('cannot hide the last visible version', () {
      final node = original.addVersion(const PanoVersion(
        imageUrl: 'https://example.com/enhanced.jpg',
        source: 'משופר ✨',
      ));
      final oneHidden = node.toggleVersionHidden(1); // hide enhanced → 1 left
      // Attempting to hide the sole remaining visible version is refused.
      final refused = oneHidden.toggleVersionHidden(0);
      expect(identical(refused, oneHidden), isTrue);
      expect(refused.viewerVersions, isNotEmpty);
    });

    test('hiding the active version moves active to a visible one', () {
      // active = enhanced (index 1). Hide it → active should fall back to 0.
      final node = original.addVersion(const PanoVersion(
        imageUrl: 'https://example.com/enhanced.jpg',
        source: 'משופר ✨',
      ));
      expect(node.activeVersion, 1);
      final hid = node.toggleVersionHidden(1);
      expect(hid.activeVersion, 0);
      expect(hid.imageUrl, 'https://example.com/raw.jpg'); // published default reverted
    });
  });
}
