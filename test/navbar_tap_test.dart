import 'package:dating_app/core/widgets/ipad_frame.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Reproduces the home-screen bottom-nav tab switching (ScaleBounce tabs inside
// the iPad frame) to prove a tab tap actually changes the page. This is the
// exact interaction the user reports as dead on iPad.
class _NavHarness extends StatefulWidget {
  const _NavHarness();
  @override
  State<_NavHarness> createState() => _NavHarnessState();
}

class _NavHarnessState extends State<_NavHarness> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          Center(child: Text('PAGE 0')),
          Center(child: Text('PAGE 1')),
          Center(child: Text('PAGE 2')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(bottom: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return ScaleBounce(
              key: Key('nav_tab_$index'),
              onTap: () => setState(() => _index = index),
              scaleDownTo: 0.90,
              child: Container(
                width: 70,
                height: 70,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1A1A1A),
                ),
                child: const Icon(Icons.circle, color: Colors.white),
              ),
            );
          }),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('iPad frame: tapping a bottom-nav tab switches the page',
      (tester) async {
    tester.view.physicalSize = const Size(1640, 2360); // iPad
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(820, 1180)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: IpadFrame(
            child: const MaterialApp(home: _NavHarness()),
          ),
        ),
      ),
    );

    expect(find.text('PAGE 0'), findsOneWidget);

    // Tap tab 1 — must switch to PAGE 1.
    await tester.tap(find.byKey(const Key('nav_tab_1')));
    await tester.pumpAndSettle();
    expect(find.text('PAGE 1'), findsOneWidget,
        reason: 'tab 1 tap must switch the page');

    // Tap tab 2.
    await tester.tap(find.byKey(const Key('nav_tab_2')));
    await tester.pumpAndSettle();
    expect(find.text('PAGE 2'), findsOneWidget,
        reason: 'tab 2 tap must switch the page');
  });

  testWidgets('ScaleBounce fires onTap immediately, not gated on the animation',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ScaleBounce(
            onTap: () => tapped = true,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ScaleBounce));
    await tester.pump(); // a single frame — do NOT settle the press animation
    expect(tapped, isTrue,
        reason: 'onTap must fire on tap-up, not after the reverse animation '
            '(the old code awaited the animation and could swallow the tap)');
  });

  testWidgets('overlapping taps both register (reverse animation interrupted)',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ScaleBounce(
            key: const Key('b'),
            onTap: () => taps++,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    ));

    // First tap: hold long enough for the press (forward) animation to run, then
    // release — this starts the ~180ms reverse animation.
    final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('b'))));
    await tester.pump(const Duration(milliseconds: 120)); // forward completes
    await g.up(); // begins reverse
    await tester.pump(const Duration(milliseconds: 40)); // reverse mid-flight

    // Second tap DURING the first tap's reverse animation. Its forward() cancels
    // the running reverse (TickerCanceled). The OLD code awaited that reverse
    // before calling onTap, so the FIRST tap's onTap was silently swallowed.
    await tester.tap(find.byKey(const Key('b')));
    await tester.pumpAndSettle();

    expect(taps, 2,
        reason: 'both taps must register even when the press animations overlap '
            '(the swallowed-tap bug that made the UI feel dead)');
  });
}
