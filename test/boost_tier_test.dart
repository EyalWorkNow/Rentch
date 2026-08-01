import 'package:flutter_test/flutter_test.dart';
import 'package:dating_app/data/models/rental_models.dart';

void main() {
  group('boostTier round-trip + getters', () {
    test('fromJson parses tier + toJson writes it', () {
      final until =
          DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
      final p = RentalProperty.fromJson({
        'id': 'p1',
        'boostedUntil': until,
        'boostTier': 'ultra',
      });
      expect(p.boostTier, PropertyBoostTier.ultra);
      expect(p.isBoosted, true);
      expect(p.isUltraBoosted, true);
      expect(p.toJson()['boostTier'], 'ultra');
    });

    test('regular boost is not ultra', () {
      final until =
          DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
      final p = RentalProperty.fromJson(
          {'id': 'p2', 'boostedUntil': until, 'boostTier': 'regular'});
      expect(p.boostTier, PropertyBoostTier.regular);
      expect(p.isBoosted, true);
      expect(p.isUltraBoosted, false);
    });

    test('no boost → none, and an expired boost is not active', () {
      final none = RentalProperty.fromJson({'id': 'p3'});
      expect(none.boostTier, PropertyBoostTier.none);
      expect(none.isBoosted, false);
      expect(none.toJson().containsKey('boostTier'), false);

      final past = DateTime.now()
          .subtract(const Duration(days: 1))
          .toUtc()
          .toIso8601String();
      final expired = RentalProperty.fromJson(
          {'id': 'p4', 'boostedUntil': past, 'boostTier': 'ultra'});
      expect(expired.isBoosted, false);
      expect(expired.isUltraBoosted, false, reason: 'expired ultra is inactive');
    });

    test('copyWith carries tier', () {
      final base = RentalProperty.fromJson({'id': 'p5'});
      final boosted = base.copyWith(
        boostedUntil: DateTime.now().add(const Duration(days: 7)),
        boostTier: PropertyBoostTier.ultra,
      );
      expect(boosted.isUltraBoosted, true);
    });
  });
}
