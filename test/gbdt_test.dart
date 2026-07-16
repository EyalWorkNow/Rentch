import 'dart:math';

import 'package:dating_app/core/search/engine/gbdt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GbdtModel', () {
    test('learns a separable signal: positives score well above negatives', () {
      final rng = Random(42);
      final x = <List<double>>[];
      final y = <double>[];
      // label = 1 when feats[1] > 0.5, else 0, with 10% label noise. feats[0] is
      // a constant bias column; feats[2..] are pure noise the model must ignore.
      for (var i = 0; i < 400; i++) {
        final f1 = rng.nextDouble();
        var label = f1 > 0.5 ? 1.0 : 0.0;
        if (rng.nextDouble() < 0.10) label = 1.0 - label;
        x.add([1.0, f1, rng.nextDouble(), rng.nextDouble()]);
        y.add(label);
      }

      final model = GbdtModel();
      model.train(x, y);
      expect(model.isTrained, isTrue);

      // Held-out evaluation on fresh draws.
      final holdout = Random(7);
      var posSum = 0.0, negSum = 0.0;
      var posN = 0, negN = 0;
      for (var i = 0; i < 200; i++) {
        final f1 = holdout.nextDouble();
        final p = model
            .predict([1.0, f1, holdout.nextDouble(), holdout.nextDouble()]);
        expect(p, inInclusiveRange(0.0, 1.0));
        if (f1 > 0.5) {
          posSum += p;
          posN++;
        } else {
          negSum += p;
          negN++;
        }
      }
      final posMean = posSum / posN;
      final negMean = negSum / negN;
      // A clear, unambiguous margin (well beyond noise).
      expect(posMean - negMean, greaterThan(0.3));
    });

    test('toJson -> fromJson preserves predictions exactly', () {
      final rng = Random(1);
      final x = <List<double>>[];
      final y = <double>[];
      for (var i = 0; i < 300; i++) {
        final f1 = rng.nextDouble();
        x.add([1.0, f1, rng.nextDouble()]);
        y.add(f1 > 0.5 ? 1.0 : 0.0);
      }
      final model = GbdtModel()..train(x, y);
      final restored = GbdtModel.fromJson(model.toJson());

      for (var i = 0; i < 25; i++) {
        final v = [1.0, rng.nextDouble(), rng.nextDouble()];
        expect(restored.predict(v), closeTo(model.predict(v), 1e-9));
      }
    });
  });
}
