import 'package:dating_app/presentation/features/panorama/panorama_sphere_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The sphere capture screen must build and render its guided UI even with NO
// camera/sensors (the simulator + test case) — it falls back to demo/drag mode
// instead of crashing. This guards the blank/crash regression class.
void main() {
  testWidgets('sphere capture renders demo mode with no camera/sensors',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: PanoramaSphereCaptureScreen(),
      ),
    ));
    // Let availableCameras() reject → demo mode, and a couple of ticker frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // 22 targets: 8 horizon + 6 up + 6 down + zenith + nadir.
    expect(find.text('צולמו 0 מתוך 22'), findsOneWidget);
    // Demo backdrop (no camera) is shown.
    expect(find.textContaining('מצב הדגמה'), findsOneWidget);
  });
}
