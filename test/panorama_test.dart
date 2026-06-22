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
    // the two capture actions + empty state (plain Text widgets)
    expect(find.text('צלם 360°'), findsOneWidget);
    expect(find.text('מהגלריה'), findsOneWidget);
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
}
