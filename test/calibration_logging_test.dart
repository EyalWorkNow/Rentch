// Calibration telemetry: the ranker's prediction must be captured alongside the
// outcome so the hand-tuned scores can be fit to real behaviour. These guard the
// one piece of real logic (top-dimension trimming for a bounded payload) and that
// the engine path produces the prediction fields the logger reads.

import 'package:dating_app/core/services/event_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('topDims keeps the N biggest contributors, by magnitude, rounded', () {
    final dims = {
      'budget': 0.30,
      'location': -0.42, // strongest by magnitude (negative)
      'value': 0.05,
      'transit': 0.18,
      'safety': 0.121234,
      'noise': 0.01,
    };
    final top = EventService.topDims(dims, 3);
    expect(top.length, 3);
    expect(top.keys, containsAll(['location', 'budget', 'transit']));
    expect(top.containsKey('noise'), false, reason: 'smallest dropped');
    // rounded to 3 dp
    expect(top['location'], -0.42);
  });

  test('topDims handles fewer dims than requested and empty input', () {
    expect(EventService.topDims({'a': 0.5}, 5), {'a': 0.5});
    expect(EventService.topDims(const {}, 5), isEmpty);
  });

  test('topDims payload stays small (well under the 2 KB metadata cap)', () {
    final many = {for (var i = 0; i < 40; i++) 'dim_$i': i / 40};
    final top = EventService.topDims(many, 5);
    expect(top.length, 5);
    expect(top.toString().length, lessThan(300));
  });

  test('CRUSH — non-finite contributions are dropped (jsonEncode-safe)', () {
    final dims = {
      'ok': 0.4,
      'nan': double.nan,
      'inf': double.infinity,
      'ninf': double.negativeInfinity,
      'ok2': 0.2,
    };
    final top = EventService.topDims(dims, 5);
    expect(top.values.every((v) => v.isFinite), true);
    expect(top.keys, containsAll(['ok', 'ok2']));
    expect(top.containsKey('nan'), false);
    // must be JSON-encodable (NaN would throw and void the whole row)
    expect(() => top.forEach((_, v) => v.toStringAsFixed(3)), returnsNormally);
  });
}
