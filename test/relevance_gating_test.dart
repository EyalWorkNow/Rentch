import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// The geo "why" chips must be RELEVANT to the search: a nightlife seeker never
// gets school/family chips, and vice-versa.
RentalProperty tlvFlat(String id, double dLat) => RentalProperty(
      id: id, price: 6000, rooms: 4, sizeM2: 90, floor: '2', totalFloors: '6',
      city: 'תל אביב', neighborhood: '', street: 'דיזנגוף', streetNumber: 100,
      lat: 32.078 + dLat, lon: 34.774, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false,
      features: const [],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
    await IsraelGeoIndex.loadParks();
    await IsraelGeoIndex.loadSchools();
    await IsraelGeoIndex.loadNightlife();
  });

  final cat = [for (var i = 0; i < 6; i++) tlvFlat('p$i', i * 0.002)];

  List<String> allTags(String text) {
    final q = SmartSearch.parse(text);
    final res = RecommendationEngine.recommendAsScored(
        candidates: cat, query: q, limit: 10, seed: 7);
    return [for (final s in res) ...s.tags];
  }

  bool hasSchool(List<String> t) =>
      t.any((s) => s.contains('בית ספר') || s.contains('🏫') || s.contains('מוסדות חינוך'));

  test('nightlife search → NO school chip, YES nightlife chip', () {
    final tags = allTags('מקום עם בארים ומסעדות בתל אביב עד 7000');
    expect(hasSchool(tags), isFalse, reason: tags.join(' | '));
    expect(tags.any((t) => t.contains('🍸')), isTrue, reason: tags.join(' | '));
  });

  test('family search → YES school chip, NO nightlife chip', () {
    final tags = allTags('דירה למשפחה עם ילדים בתל אביב עד 9000');
    expect(hasSchool(tags), isTrue, reason: tags.join(' | '));
    expect(tags.any((t) => t.contains('🍸')), isFalse, reason: tags.join(' | '));
  });
}
