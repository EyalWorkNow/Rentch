import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal self-check for the audience-targeting fields (F1/F2) added to
// RentalProperty. Guards the two invariants the backend/UI agents rely on:
//   1. toJson -> fromJson round-trips all four audience fields.
//   2. fromJson on a listing map missing every audience key yields the defaults
//      (empty list / null / empty list / false) so old persisted listings load.
void main() {
  // A minimal listing map with the required (non-audience) keys populated.
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

  test('round-trip preserves the four audience fields', () {
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
      audienceCohorts: const ['family', 'oleh'],
      audienceNote: 'Ideal for a quiet family',
      audienceSuggested: const [
        AudienceSuggestion(
          cohort: 'young_professional',
          confidence: 0.82,
          reason: 'near light rail',
        ),
      ],
      exclusiveToAudience: true,
    );

    final decoded = RentalProperty.fromJson(original.toJson());

    expect(decoded.audienceCohorts, ['family', 'oleh']);
    expect(decoded.audienceNote, 'Ideal for a quiet family');
    expect(decoded.audienceSuggested.length, 1);
    expect(decoded.audienceSuggested.first.cohort, 'young_professional');
    expect(decoded.audienceSuggested.first.confidence, 0.82);
    expect(decoded.audienceSuggested.first.reason, 'near light rail');
    expect(decoded.exclusiveToAudience, isTrue);
  });

  test('fromJson without any audience keys yields defaults', () {
    final decoded = RentalProperty.fromJson(baseJson());

    expect(decoded.audienceCohorts, isEmpty);
    expect(decoded.audienceNote, isNull);
    expect(decoded.audienceSuggested, isEmpty);
    expect(decoded.exclusiveToAudience, isFalse);
  });
}
