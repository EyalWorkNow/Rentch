import 'dart:io';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';
RentalProperty f(String id, String city, double lat, double lon) => RentalProperty(
  id: id, price: 4500, rooms: 3, sizeM2: 75, floor: '2', totalFloors: '5', city: city,
  neighborhood: '', street: 'x', streetNumber: 1, lat: lat, lon: lon, propertyType: 'דירה',
  transactionType: PropertyTransactionType.rent, entryDate: '', condition: 'טוב', ownerName: 'o',
  agencyListing: false, features: const ['ac'],
  media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
  marketSignals: const PropertyMarketSignals(views: 10, likes: 1, saves: 0),
  verification: PropertyVerification.cameraVideo(videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)));
void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: (p) => File(p).readAsString());
  });
  tearDownAll(() => GovData.instance.resetForTest());
  test('עין עירון does NOT leak אור עקיבא', () {
    final cands = [
      f('or-akiva-1','אור עקיבא',32.5081,34.9186),
      f('or-akiva-2','אור עקיבא',32.508,34.918),
      f('or-akiva-3','אור עקיבא',32.509,34.919),
      f('caesarea','קיסריה',32.50,34.90),
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cands, query: SmartSearch.parse('דירה בעין עירון עד 5000'), limit: 8, seed: 3);
    print('DBG עין עירון (0 stock) -> ${recs.map((r)=>r.property.city).toList()}');
    expect(recs.any((r)=>r.property.city.contains('אור עקיבא')), isFalse,
      reason: 'must NOT show אור עקיבא for עין עירון');
  });
  test('עין עירון with own stock shows only itself', () {
    final cands = [
      f('ein-1','עין עירון',32.4703,34.9814),
      f('or-akiva-1','אור עקיבא',32.5081,34.9186),
      f('or-akiva-2','אור עקיבא',32.508,34.918),
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cands, query: SmartSearch.parse('דירה בעין עירון עד 5000'), limit: 8, seed: 3);
    print('DBG עין עירון (1 stock) -> ${recs.map((r)=>r.property.city).toList()}');
    expect(recs.every((r)=>r.property.city.contains('עין עירון')), isTrue);
  });
}
