import 'package:dating_app/presentation/screens/compare_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bestValueIndex', () {
    test('picks the listing furthest below its local market price', () {
      // 0.05 = 5% under, 0.20 = 20% under, -0.10 = 10% over market.
      expect(bestValueIndex([0.05, 0.20, -0.10]), 1);
    });

    test('a listing above market still wins if the others are worse', () {
      expect(bestValueIndex([-0.30, -0.10, null]), 1); // -10% beats -30%
    });

    test('no winner unless ≥2 columns are comparable', () {
      expect(bestValueIndex([null, 0.20]), -1); // only one anchored → decline
      expect(bestValueIndex([null, null]), -1);
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
