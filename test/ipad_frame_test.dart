import 'package:dating_app/core/widgets/ipad_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the iPad phone-frame adapter does NOT break touch input — taps inside
// the centered phone-width column must reach the underlying widgets (this is the
// exact failure mode that would block App Review on iPad: an unresponsive UI).
void main() {
  // Renders [child] under an iPad-sized MediaQuery (shortestSide > 600 → frame
  // active) wrapped in the real IpadFrame.
  Widget harness({required Size size, required Widget child}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: IpadFrame(child: child),
      ),
    );
  }

  testWidgets('iPad: a tap inside the centered column reaches the button',
      (tester) async {
    tester.view.physicalSize = const Size(1640, 2360); // iPad Air 11" @2x
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var taps = 0;
    await tester.pumpWidget(harness(
      size: const Size(820, 1180), // iPad portrait, shortestSide 820 > 600
      child: Center(
        child: ElevatedButton(
          key: const Key('cta'),
          onPressed: () => taps++,
          child: const Text('Login'),
        ),
      ),
    ));

    // Frame must be active (column clamped to 480, centered → dark margins).
    expect(find.byType(ColoredBox), findsWidgets);

    await tester.tap(find.byKey(const Key('cta')));
    await tester.pump();
    expect(taps, 1, reason: 'centered button tap must register through the frame');
  });

  testWidgets('iPad: an OFF-CENTER button (like the login tab) still registers',
      (tester) async {
    tester.view.physicalSize = const Size(1640, 2360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var taps = 0;
    await tester.pumpWidget(harness(
      size: const Size(820, 1180),
      // Button pinned to the right edge of the (clamped 480) column — the case
      // that visually appears off-center on the iPad screen.
      child: Align(
        alignment: Alignment.bottomRight,
        child: SizedBox(
          width: 140,
          child: ElevatedButton(
            key: const Key('tab'),
            onPressed: () => taps++,
            child: const Text('התחברות'),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('tab')));
    await tester.pump();
    expect(taps, 1,
        reason: 'off-center button tap must register (this is the sim failure mode)');
  });

  testWidgets('phone: frame is a no-op (no clamping column added)',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(harness(
      size: const Size(390, 844), // iPhone, shortestSide 390 ≤ 600
      child: Center(
        child: ElevatedButton(
          key: const Key('cta'),
          onPressed: () => taps++,
          child: const Text('Login'),
        ),
      ),
    ));

    // On a phone the frame returns the child unchanged — no dark backdrop.
    expect(find.byType(ColoredBox), findsNothing);
    await tester.tap(find.byKey(const Key('cta')));
    await tester.pump();
    expect(taps, 1);
  });
}
