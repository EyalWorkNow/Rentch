import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal self-check for the per-listing eligibility config (F3) added to
// RentalProperty. Guards the two invariants the backend/UI agents rely on:
//   1. toJson -> fromJson round-trips an EligibilityConfig with mixed rules
//      (a numeric budgetMin 'must' + a List<String> occupation 'important').
//   2. fromJson on a listing map missing the `eligibility` key yields a
//      disabled empty config so old persisted listings load cleanly.
void main() {
  // A minimal listing map with the required (non-eligibility) keys populated.
  Map<String, dynamic> baseJson() => {
        'id': 'p1',
        'price': 5000,
        'rooms': 3.0,
        'sizeM2': 80,
        'city': 'Tel Aviv',
        'lat': 32.08,
        'lon': 34.78,
        'propertyType': 'apartment',
      };

  test('round-trip preserves an eligibility config with two rules', () {
    final original = RentalProperty(
      id: 'p1',
      price: 5000,
      rooms: 3,
      sizeM2: 80,
      floor: '2',
      totalFloors: '4',
      city: 'Tel Aviv',
      neighborhood: '',
      street: '',
      streetNumber: -1,
      lat: 32.08,
      lon: 34.78,
      propertyType: 'apartment',
      entryDate: '',
      condition: '',
      ownerName: 'Owner',
      agencyListing: false,
      features: const [],
      media: const [],
      eligibility: const EligibilityConfig(
        enabled: true,
        rules: [
          EligibilityRule(key: 'budgetMin', value: 12000, importance: 'must'),
          EligibilityRule(
            key: 'occupation',
            value: ['hi_tech', 'medicine'],
            importance: 'important',
          ),
        ],
      ),
    );

    final decoded = RentalProperty.fromJson(original.toJson());

    expect(decoded.eligibility.enabled, isTrue);
    expect(decoded.eligibility.rules.length, 2);

    final budget = decoded.eligibility.rules
        .firstWhere((rule) => rule.key == 'budgetMin');
    expect(budget.value, 12000);
    expect(budget.value, isA<num>());
    expect(budget.importance, 'must');

    final occupation = decoded.eligibility.rules
        .firstWhere((rule) => rule.key == 'occupation');
    expect(occupation.value, ['hi_tech', 'medicine']);
    expect(occupation.value, isA<List<String>>());
    expect(occupation.importance, 'important');
  });

  test('fromJson without the eligibility key yields a disabled empty config',
      () {
    final decoded = RentalProperty.fromJson(baseJson());

    expect(decoded.eligibility.enabled, isFalse);
    expect(decoded.eligibility.rules, isEmpty);
  });
}
