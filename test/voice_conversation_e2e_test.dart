import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/features/search/ati_voice_screen.dart';
import 'package:dating_app/presentation/widgets/ati_voice_property_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/data/providers/dating_provider.dart';

// ── Fake STT (feeds transcripts as if spoken) ──────────────────────────────
class FakeAssistant extends AssistantService {
  void Function(String, bool)? _onResult;
  int startCount = 0;
  @override
  Future<void> startListening({
    required void Function(String, bool) onResult,
    void Function(double)? onSoundLevelChange,
    void Function(String)? onStatus,
  }) async {
    startCount++;
    _onResult = onResult;
  }
  @override
  Future<void> stopListening() async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stopSpeaking() async {}
  void say(String t) => _onResult?.call(t, true); // final result
}

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

  testWidgets('REAL voice conversation: עין עירון → consent → apartments SHOW (no leak)', (tester) async {
    final svc = FakeAssistant();
    final convo = _Convo();
    await tester.pumpWidget(ChangeNotifierProvider<DatingProvider>.value(
      value: DatingProvider(),
      child: MaterialApp(home: AtiVoiceScreen(service: svc, onUtterance: convo.turn)),
    ));
    await tester.pump();

    // Turn 1 — the user's real opening line.
    svc.say('היי אתי, אני מחפש דירה בעין עירון');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    // Turn 2 — budget + rooms + quiet.
    svc.say('עד 5000 שקל שלושה חדרים משהו שקט');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    // At this point אתי should be ASKING consent, NOT showing cards yet.
    expect(find.byType(AtiVoicePropertyCard), findsNothing,
        reason: 'apartments must not appear before consent');
    expect(convo.awaiting, true);

    // Turn 3 — the exact reply that used to fail.
    svc.say('כן תציגי לי אותן בבקשה');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    // THE FIX: apartments must now actually render in the carousel.
    expect(find.byType(AtiVoicePropertyCard), findsWidgets,
        reason: 'after "תציגי לי אותן" the apartments MUST show');

    // And every shown apartment is in עין עירון — no אור עקיבא leak.
    final cities = convo.pending.map((s) => s.property.city).toSet();
    expect(cities, {'עין עירון'}, reason: 'no cross-city leak: $cities');
    expect(convo.pending.isNotEmpty, true);
  });
}
