import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty prop(String id, String city, double lat, double lon, {int price = 4300, double rooms = 3, List<String> f = const ['ac']}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 75, floor: '2', totalFloors: '4',
      city: city, neighborhood: '', street: 'x', streetNumber: 1, lat: lat, lon: lon,
      propertyType: 'דירה', transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false, features: f,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 20, likes: 2, saves: 1),
      verification: PropertyVerification.cameraVideo(videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)));

// Catalogue: עין עירון stock + אור עקיבא (the leak trap).
final _cat = <RentalProperty>[
  prop('ein-1', 'עין עירון', 32.470, 34.981, price: 4200, rooms: 3),
  prop('ein-2', 'עין עירון', 32.472, 34.983, price: 4600, rooms: 3),
  prop('ein-3', 'עין עירון', 32.469, 34.980, price: 3900, rooms: 3),
  prop('ora-1', 'אור עקיבא', 32.508, 34.918, price: 4100, rooms: 3),
  prop('ora-2', 'אור עקיבא', 32.509, 34.919, price: 4400, rooms: 3),
];

// A faithful reproduction of _processVoiceUtterance's consent flow, backed by the
// REAL SmartSearch parse (gov-data) + REAL RecommendationEngine.
class _Convo {
  SearchQuery q = SearchQuery();
  bool awaiting = false, consented = false;
  List<ScoredProperty> pending = const [];

  static final _negative = RegExp(r'\s(?:לא|רגע|חכה|חכי|המתן|עצור)\s|עוד לא|not yet', caseSensitive: false);
  static final _criteria = RegExp(r'חדר|מרפסת|מעלית|ממ"?ד|חני|קומה|זול|יקר|גדול|קטן|מרוה|נגיש|כלב|קרוב|ליד|שקט|מרכז|תוסיף|בנוסף|עוד|באזור|בעיר|תקציב');
  bool _hold(String t) => _negative.hasMatch(' ${t.trim()} ') || RegExp(r'\d').hasMatch(t) || _criteria.hasMatch(t);

  SearchQuery _merge(SearchQuery a, SearchQuery b) => SearchQuery(
        city: b.city ?? a.city,
        minPrice: b.minPrice ?? a.minPrice,
        maxPrice: b.maxPrice ?? a.maxPrice,
        minRooms: b.minRooms ?? a.minRooms,
        maxRooms: b.maxRooms ?? a.maxRooms,
        propertyType: b.propertyType ?? a.propertyType,
        transactionType: b.transactionType,
        amenities: {...a.amenities, ...b.amenities},
        intents: {...a.intents, ...b.intents},
        weights: {...a.weights, ...b.weights},
        requiredFeatures: {...a.requiredFeatures, ...b.requiredFeatures},
        rawText: b.rawText,
      );

  Future<({String reply, bool showResults, List<ScoredProperty> results})> turn(String t) async {
    if (awaiting) {
      awaiting = false;
      if (!_hold(t)) {
        consented = true;
        return (reply: 'מעולה! הנה מה שמצאתי 👇', showResults: pending.isNotEmpty, results: pending);
      }
    }
    q = _merge(q, SmartSearch.parse(t));
    final recs = RecommendationEngine.recommendAsScored(candidates: _cat, query: q, limit: 12, seed: 3);
    if (recs.isNotEmpty && !consented) {
      awaiting = true;
      pending = recs;
      return (reply: 'מצאתי כמה אפשרויות. רוצה שאראה לך אותן?', showResults: false, results: const <ScoredProperty>[]);
    }
    return (reply: 'ספר לי עוד', showResults: recs.isNotEmpty, results: recs);
  }
}

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: (p) => File(p).readAsString());
  });
  tearDownAll(() => GovData.instance.resetForTest());

  // The full conversation logic through the REAL engine + gov-data. (The
  // push-to-talk SCREEN mechanics — hold→record→Whisper→onUtterance→speak — are
  // covered in ati_voice_screen_test; here we drive the same 3 transcripts.)
  test('push-to-talk conversation: עין עירון → consent → reveal, no leak', () async {
    final convo = _Convo();
    await convo.turn('היי אתי, אני מחפש דירה בעין עירון'); // turn 1
    await convo.turn('עד 5000 שקל שלושה חדרים משהו שקט'); // turn 2

    expect(convo.awaiting, true, reason: 'אתי asks before revealing');
    expect(convo.consented, false);

    final r = await convo.turn('כן תציגי לי אותן בבקשה'); // turn 3

    expect(convo.consented, true, reason: '"תציגי לי אותן" is understood as consent');
    expect(r.results.isNotEmpty, true, reason: 'apartments revealed');
    final cities = r.results.map((s) => s.property.city).toSet();
    expect(cities, {'עין עירון'}, reason: 'no cross-city leak: $cities');
  });
}
