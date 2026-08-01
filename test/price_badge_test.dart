import 'package:flutter_test/flutter_test.dart';
import 'package:dating_app/data/models/rental_models.dart';

void main() {
  group('MarketPriceBadge', () {
    test('parses from a nested priceBadge json + round-trips', () {
      final p = RentalProperty.fromJson({
        'id': 'x1',
        'priceBadge': {'medianPpm': 28500, 'deltaPct': 7.5, 'badge': 'מעל השוק'},
      });
      expect(p.priceBadge, isNotNull);
      expect(p.priceBadge!.medianPpm, 28500);
      expect(p.priceBadge!.deltaPct, 7.5);
      expect(p.priceBadge!.badge, 'מעל השוק');
      expect(p.priceBadge!.hasData, true);

      final round = RentalProperty.fromJson(p.toJson());
      expect(round.priceBadge!.medianPpm, 28500);
      expect(round.priceBadge!.badge, 'מעל השוק');
    });

    test('absent priceBadge → null, not in json', () {
      final p = RentalProperty.fromJson({'id': 'x2'});
      expect(p.priceBadge, isNull);
      expect(p.toJson().containsKey('priceBadge'), false);
    });

    test('empty/garbage priceBadge → null (no fake data)', () {
      expect(RentalProperty.fromJson({'id': 'x3', 'priceBadge': {}}).priceBadge,
          isNull);
      expect(
          RentalProperty.fromJson({'id': 'x4', 'priceBadge': 'nope'}).priceBadge,
          isNull);
      // medianPpm 0 → hasData false
      final z = MarketPriceBadge.fromJson({'medianPpm': 0});
      expect(z?.hasData ?? false, false);
    });
  });
}
