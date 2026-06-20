import 'package:dating_app/core/matching/match_engine.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _engine = MatchEngine();

PropertySignals _prop({int price = 6000, double rooms = 3, String city = 'תל אביב'}) =>
    PropertySignals(price: price, rooms: rooms, sizeM2: 70, city: city,
        verified: true, photoCount: 4);

void main() {
  group('one-sided (landlord unknown)', () {
    test('mutual score equals the property-fit when there is no landlord', () {
      final out = _engine.evaluate(
        tenant: const TenantSignals(budgetMax: 7000, desiredRooms: 3),
        landlord: LandlordSignals.unknown,
        property: _prop(),
        propertyFitScore: 82,
      );
      expect(out.score, 82);
      expect(out.tier, MatchTier.excellent);
      expect(out.tenantFitScore, -1);
      expect(out.hasTwoSidedSignal, isFalse);
    });
  });

  group('explainability', () {
    test('affordable + same city + right rooms surface positive reasons', () {
      final out = _engine.evaluate(
        tenant: const TenantSignals(
            budgetMax: 7000, desiredRooms: 3, searchCity: 'תל אביב'),
        landlord: LandlordSignals.unknown,
        property: _prop(price: 6000, rooms: 3, city: 'תל אביב'),
        propertyFitScore: 70,
      );
      final labels = out.reasons.map((r) => r.label).toList();
      expect(labels, contains('מתאים לתקציב שלך'));
      expect(out.reasons.any((r) => r.kind == MatchReasonKind.location), isTrue);
      expect(labels, contains('מספר החדרים מתאים לך'));
      expect(out.headlineReason, isNotNull);
    });

    test('over-budget produces a concern, not a positive', () {
      final out = _engine.evaluate(
        tenant: const TenantSignals(budgetMax: 5000, desiredRooms: 3),
        landlord: LandlordSignals.unknown,
        property: _prop(price: 6500),
        propertyFitScore: 50,
      );
      expect(out.concerns.any((r) => r.kind == MatchReasonKind.budget), isTrue);
    });
  });

  group('two-sided fit', () {
    test('shared prefs + affordable tenant lift the mutual score above one-sided',
        () {
      const tenant = TenantSignals(
        budgetMax: 9000,
        desiredRooms: 3,
        tags: ['לא מעסן/ת', 'מתאים לחיות מחמד', 'חייב/ת חניה'],
      );
      // Use exact catalog labels for matchKeys.
      const tenant2 = TenantSignals(
        budgetMax: 9000,
        desiredRooms: 3,
        tags: ['לא מעשן/ת', 'מתאים לחיות מחמד', 'חייב/ת חניה'],
      );
      const landlord = LandlordSignals(
        tags: ['מעדיף שוכרים לא מעשנים', 'מאפשר בעלי חיים', 'יש חניה'],
      );
      final out = _engine.evaluate(
        tenant: tenant2,
        landlord: landlord,
        property: _prop(price: 6000),
        propertyFitScore: 70,
      );
      expect(out.hasTwoSidedSignal, isTrue);
      expect(out.tenantFitScore, greaterThan(70));
      // Three shared lifestyle keys should appear as positives.
      expect(out.reasons.where((r) => r.kind == MatchReasonKind.lifestyle).length,
          3);
      expect(out.reasons.any((r) => r.kind == MatchReasonKind.mutualInterest),
          isTrue);
      // sanity: tenant is irrelevant placeholder
      expect(tenant.budgetMax, 9000);
    });
  });

  group('deal-breaker hard gates', () {
    test("landlord requires income proof the tenant lacks → excluded + conflict",
        () {
      const landlord = LandlordSignals(
        tags: ['דורש אישור הכנסה'],
        dealBreakers: ['דורש אישור הכנסה'], // income_proof required
      );
      final out = _engine.evaluate(
        tenant: const TenantSignals(budgetMax: 9000, desiredRooms: 3),
        landlord: landlord,
        property: _prop(price: 6000),
        propertyFitScore: 90,
      );
      expect(out.excluded, isTrue);
      expect(out.dealBreakerConflicts, isNotEmpty);
      expect(out.score, lessThan(90)); // penalised
    });

    test('tenant deal-breaker met by landlord → no conflict', () {
      const tenant = TenantSignals(
        budgetMax: 9000,
        desiredRooms: 3,
        tags: ['חייב/ת חניה'],
        dealBreakers: ['חייב/ת חניה'], // parking required
      );
      const landlord = LandlordSignals(tags: ['יש חניה']); // offers parking
      final out = _engine.evaluate(
        tenant: tenant,
        landlord: landlord,
        property: _prop(),
        propertyFitScore: 70,
      );
      expect(out.excluded, isFalse);
      expect(out.dealBreakerConflicts, isEmpty);
    });

    test('tenant deal-breaker NOT met by landlord → excluded', () {
      const tenant = TenantSignals(
        budgetMax: 9000,
        desiredRooms: 3,
        tags: ['חייב/ת חניה'],
        dealBreakers: ['חייב/ת חניה'],
      );
      const landlord = LandlordSignals(tags: ['מעלית']); // no parking offered
      final out = _engine.evaluate(
        tenant: tenant,
        landlord: landlord,
        property: _prop(),
        propertyFitScore: 80,
      );
      expect(out.excluded, isTrue);
      expect(out.score, lessThan(80));
    });
  });

  group('tiers', () {
    test('score maps to the right tier band', () {
      expect(MatchTierX.fromScore(95), MatchTier.perfect);
      expect(MatchTierX.fromScore(80), MatchTier.excellent);
      expect(MatchTierX.fromScore(60), MatchTier.good);
      expect(MatchTierX.fromScore(40), MatchTier.fair);
      expect(MatchTierX.fromScore(10), MatchTier.weak);
    });
  });
}
