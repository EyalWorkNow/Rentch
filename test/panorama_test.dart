import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_capture_screen.dart';
import 'package:dating_app/presentation/features/panorama/panorama_experience_view.dart';
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
