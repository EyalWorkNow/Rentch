import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// The user's exact bug: "דירה בהרצליה באיזור עם ברים ומסעדות" showed a distance-
// from-school chip and NO bars/restaurants tag. Two root causes, both locked here:
//   1) the 🍸 nightlife tag was gated on a Tel-Aviv-calibrated density threshold,
//      so a real nightlife strip OUTSIDE Tel Aviv (Herzliya ≈ 0.2) never fired it;
//   2) the "why" leaked stat-carrying-but-irrelevant axes (schools, sea) that the
//      seeker never asked about.

RentalProperty hz(String id, double rooms, int price, double lat, double lon) =>
    RentalProperty(
      id: id, price: price, rooms: rooms,
      sizeM2: (55 + rooms * 12).toInt(), floor: '2', totalFloors: '6',
      city: 'הרצליה', neighborhood: '', street: 'סוקולוב', streetNumber: 10,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false, features: const [],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try { await GovData.instance.init(); } catch (_) {}
    await IsraelGeoIndex.loadParks();
    await IsraelGeoIndex.loadSchools();
    await IsraelGeoIndex.loadNightlife();
  });

  // Herzliya stock on its real nightlife cluster (~32.162, 34.84).
  final cat = [
    hz('a', 3.0, 6000, 32.1621, 34.8410),
    hz('b', 3.0, 6500, 32.1641, 34.8420),
    hz('c', 4.0, 7000, 32.1597, 34.8400),
    hz('d', 2.0, 5500, 32.1611, 34.8430),
    hz('e', 3.5, 6800, 32.1660, 34.8390),
  ];

  test('Herzliya bars/restaurants search: 🍸 shows, schools/sea do NOT', () {
    final q = SmartSearch.parse('דירה בהרצליה באיזור עם ברים ומסעדות');
    final res = RecommendationEngine.recommendAsScored(
        candidates: cat, query: q, limit: 10, seed: 7);
    expect(res, isNotEmpty);

    // 1) the bars/restaurants tag must appear (was missing outside Tel Aviv).
    final allTags = [for (final s in res) ...s.tags];
    expect(allTags.any((t) => t.contains('🍸')), isTrue,
        reason: 'nightlife tag missing — got: ${allTags.join(" | ")}');

    // 2) no irrelevant geo axes for a pure nightlife seeker.
    for (final s in res) {
      final dims = s.scorecard!.dimensions;
      expect(dims.any((d) => d.key == 'coast'), isFalse,
          reason: 'sea axis leaked into a nightlife search');
      for (final d in dims) {
        expect(d.label.contains('בית ספר'), isFalse,
            reason: 'school distance leaked: ${d.label} · ${d.stat}');
      }
      // No school/kindergarten/sea emoji chips either.
      for (final t in s.tags) {
        expect(t.contains('🏫') || t.contains('🏖️'), isFalse,
            reason: 'irrelevant geo chip leaked: $t');
      }
    }
  });
}
