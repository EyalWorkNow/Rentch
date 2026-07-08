import 'package:dating_app/presentation/screens/compare_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bestValueIndex', () {
    test('picks the cheapest ₪/m² when features/match tie', () {
      final i = bestValueIndex(
        ppm: [100, 50, 80],
        featureFrac: [0, 0, 0],
        match: [0, 0, 0],
      );
      expect(i, 1); // 50 ₪/m² is the best value
    });

    test('no winner unless ≥2 columns have a real ₪/m²', () {
      expect(
        bestValueIndex(ppm: [null, 50], featureFrac: [0, 0], match: [0, 0]),
        -1, // only one column has data → arbitrary, so decline
      );
    });

    test('features + match can outweigh a slightly worse ₪/m²', () {
      final i = bestValueIndex(
        ppm: [100, 98], // col1 barely cheaper (ppmScore ~0.02 vs 0)
        featureFrac: [1.0, 0.0], // col0 has all premium features
        match: [1.0, 0.0],
      );
      expect(i, 0);
    });
  });

  group('numericWinners', () {
    test('min-is-best highlights the single cheapest', () {
      expect(numericWinners([7000, 5000, 6000], minIsBest: true), {1});
    });

    test('epsilon ties light up together', () {
      expect(numericWinners([90.0, 90.2, 120.0], minIsBest: true), {0, 1});
    });

    test('all-equal → nobody wins', () {
      expect(numericWinners([5000, 5000], minIsBest: true), isEmpty);
    });

    test('nulls are ignored, max-is-best works', () {
      expect(numericWinners([null, 80.0, 95.0], minIsBest: false), {2});
    });
  });
}
