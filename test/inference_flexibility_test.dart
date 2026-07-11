// The "reading between the lines" nudges (Part F): the SAME goal must be reached
// from DIFFERENT phrasings. Each test builds the preference model from a phrasing
// and asserts the implied dimensions are weighted ABOVE a neutral baseline.
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final market = MarketContext.analyze([
    for (var i = 0; i < 12; i++)
      RentalProperty(
          id: 'm$i', price: 5000 + i * 300, rooms: 3, sizeM2: 70, floor: '2',
          totalFloors: '6', city: 'תל אביב', neighborhood: '', street: 'x',
          streetNumber: 1, lat: 32.07, lon: 34.78, propertyType: 'דירה',
          entryDate: '', condition: 'טוב', ownerName: 'x', agencyListing: false,
          features: const [],
          media: const [PropertyMedia(url: 'u', type: PropertyMediaType.image)]),
  ]);
  UserPreferenceModel model(String q) =>
      PreferenceModelBuilder.build(query: SmartSearch.parse(q), market: market);

  final neutral = model('דירה בתל אביב');

  // Higher-than-neutral weight on [dim] means the inference reached the ranker.
  void up(String q, String dim) {
    expect(model(q).weight(dim), greaterThan(neutral.weight(dim)),
        reason: '"$q" should raise $dim');
  }

  test('single — many phrasings → young area + transit (the canonical case)', () {
    for (final q in [
      'רווק מחפש דירה בתל אביב',
      'אני גר לבד בתל אביב',
      'single guy looking for a place in tel aviv',
    ]) {
      up(q, 'young_area');
      up(q, 'transit');
    }
  });

  test('expecting a baby → safety + schools', () {
    for (final q in ['אנחנו בהריון מחפשים דירה', 'pregnant, looking in חיפה']) {
      up(q, 'safety');
      up(q, 'schools');
    }
  });

  test('retiree / pensioner → accessibility + health', () {
    for (final q in ['פנסיונר מחפש דירה', 'זוג בפרישה', 'retired couple in חיפה']) {
      up(q, 'accessibility');
      up(q, 'health');
    }
  });

  test('car-free (varied phrasings) → transit', () {
    for (final q in ['אין לי רכב', 'בלי רכב בתל אביב', 'i have no car, need transit']) {
      up(q, 'transit');
    }
  });

  test('beach lover → coast', () {
    for (final q in ['אוהב ים בבת ים', 'קרוב לים', 'i love the beach']) {
      up(q, 'coast');
    }
  });

  test('high-tech / relocating / after-army → transit or employment', () {
    up('הייטקיסט מחפש דירה במרכז', 'young_area');
    up('עברתי בשביל עבודה חדשה', 'employment');
    up('אחרי הצבא, עבודה ראשונה', 'value');
  });

  test('childless couple/single are NOT pushed toward schools & family dims', () {
    final couple = model('זוג צעיר בתל אביב');
    final single = model('רווק בתל אביב');
    final family = model('משפחה עם ילדים בתל אביב');
    // being a couple/single ≠ wanting schools: their schools weight is far below
    // a family's AND below their own location weight.
    expect(couple.weight('schools'), lessThan(0.15));
    expect(single.weight('schools'), lessThan(0.15));
    expect(family.weight('schools'), greaterThan(0.5));
    expect(couple.weight('schools'), lessThan(couple.weight('location')));
    // a couple who signals kids DOES get schools back.
    expect(model('זוג שמתכנן ילדים').weight('schools'), greaterThan(0.4));
  });

  test('explicit ask still dominates a soft inference', () {
    // A single seeker who ALSO explicitly wants quiet must not be pushed to a
    // young/nightlife area — wantsCalm gates the lively nudges.
    final m = model('רווק דתי מחפש דירה שקטה בבני ברק');
    expect(m.weight('low_noise'), greaterThan(m.weight('nightlife')),
        reason: 'an explicit quiet ask must outweigh the single→nightlife nudge');
  });
}
