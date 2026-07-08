import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Regressions for the bugs the 5-agent aggressive breaking-test surfaced.
// Groups: parsing (budget/rooms/geo), cohort signals, deal-breaker gate leaks,
// and the Infinity-coord crash.

Future<String> _diskReader(String p) => File(p).readAsString();

RentalProperty flat({
  required String id,
  required int price,
  required double rooms,
  required String city,
  double lat = 32.08,
  double lon = 34.80,
  String floor = '3',
  List<String> features = const [],
  PropertyTransactionType type = PropertyTransactionType.rent,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 80, floor: floor,
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: type, entryDate: '', condition: 'טוב',
      ownerName: 'בעלים', agencyListing: false, features: features,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

List<ScoredProperty> rank(List<RentalProperty> cat, String q) =>
    RecommendationEngine.recommendAsScored(
        candidates: cat, query: SmartSearch.parse(q), profile: null,
        limit: 8, seed: 7);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _diskReader);
  });

  group('parsing — budget', () {
    test('B1: bare sale magnitudes register (+ trip sale inference)', () {
      for (final q in ['דירה בתל אביב 2 מיליון', 'דירה בתל אביב 2500000',
        'להשקעה 800 אלף']) {
        final p = SmartSearch.parse(q);
        expect(p.maxPrice != null && p.maxPrice! >= 100000, true,
            reason: 'budget dropped for "$q" → ${p.maxPrice}');
        expect(p.transactionType, TransactionTypeFilter.sale,
            reason: 'sale not inferred for "$q"');
      }
    });
    test('rent-band bare number still works', () {
      expect(SmartSearch.parse('דירה בחיפה 5000').maxPrice, 5000);
    });
  });

  group('parsing — rooms', () {
    test('B2: "עד N חדרים" is a MAX, not a min', () {
      final p = SmartSearch.parse('דירה קטנה בתל אביב עד 3 חדרים');
      expect(p.maxRooms, 3.0);
      expect(p.minRooms, isNull);
    });
    test('"מעל/לפחות N חדרים" is a MIN', () {
      expect(SmartSearch.parse('דירה מעל 4 חדרים').minRooms, 4.0);
      expect(SmartSearch.parse('לפחות 4 חדרים').minRooms, 4.0);
    });
  });

  group('parsing — geo double-yod', () {
    test('Geo1: ktiv-male "-ייה" cities resolve', () {
      const cases = {
        'דירה בנהרייה': 'נהריה',
        'דירה בהרצלייה': 'הרצליה',
        'דירה בנתנייה': 'נתניה',
        'דירה בטברייה': 'טבריה',
      };
      cases.forEach((q, want) {
        final c = SmartSearch.parse(q).city;
        expect(c != null && c.contains(want.substring(0, 4)), true,
            reason: '"$q" → $c (want $want)');
      });
    });
  });

  group('cohort signals', () {
    test('C3: "בלי ילדים" negates children; couple not family', () {
      final s = SmartSearch.cohortSignals('זוג בלי ילדים');
      expect(s['hasChildren'], isNull);
      expect(s['household'], 'couple');
    });
    test('C4: city name בני ברק is not a religiosity signal', () {
      expect(SmartSearch.cohortSignals('משפחה חילונית בבני ברק')['religiousStream'],
          isNull);
      expect(SmartSearch.cohortSignals('דתי לאומי בבני ברק')['religiousStream'],
          'dati_leumi');
    });
    test('C5: English aliyah/olah + english-speaking', () {
      expect(SmartSearch.cohortSignals('just made aliyah')['isOleh'], 'true');
      final s = SmartSearch.cohortSignals('new olah, english speaking area');
      expect(s['isOleh'], 'true');
      expect(s['langPref'], 'en');
    });
    test('C7: building age is not the user age', () {
      expect(SmartSearch.cohortSignals('דירה בבניין בן 40 שנה')['age'], isNull);
      expect(SmartSearch.cohortSignals('אני בן 74')['age'], '74');
    });
    test('C8: מבוגר → senior, קושי בהליכה → accessibility', () {
      expect(SmartSearch.cohortSignals('אני מבוגר')['lifeStage'], 'senior');
      expect(SmartSearch.cohortSignals('יש לי קושי בהליכה')['accessibilityNeed'],
          'true');
    });
  });

  group('deal-breaker gate — no leaks', () {
    // When a required feature is UNRECORDED across the catalogue (no listing
    // carries the flag — absence ≠ banned; Israeli listings rarely record pet
    // policy), the gate degrades GRACEFULLY to the pool rather than hiding every
    // result. The real no-leak guarantee is tested by D1 + "gate still passes"
    // below (when stock WITH the feature exists, only those show).
    test('D2: unrecorded must-have (mamad/pets) degrades gracefully, no crash', () {
      final cat = [
        flat(id: 'a', price: 6000, rooms: 4, city: 'תל אביב'),
        flat(id: 'b', price: 7000, rooms: 4, city: 'תל אביב'),
      ]; // none carry a mamad/pets flag
      expect(rank(cat, 'דירת 4 חדרים בתל אביב עם ממ"ד חובה עד 9000'), isNotEmpty);
      expect(rank(cat, 'דירה בתל אביב עם כלב יש לי כלב עד 9000'), isNotEmpty);
    });
    test('D1: unsatisfiable soft key (accessible) must not void a satisfiable '
        'one (elevator) — walk-ups excluded', () {
      final cat = [
        flat(id: 'elev-a', price: 4900, rooms: 3, city: 'נתניה', lat: 32.32,
            lon: 34.85, floor: '2', features: ['elevator']),
        flat(id: 'elev-b', price: 5000, rooms: 3, city: 'נתניה', lat: 32.32,
            lon: 34.85, floor: '3', features: ['elevator']),
        flat(id: 'walk-c', price: 4200, rooms: 3, city: 'נתניה', lat: 32.33,
            lon: 34.86, floor: '4', features: []),
        flat(id: 'walk-d', price: 4300, rooms: 3, city: 'נתניה', lat: 32.33,
            lon: 34.86, floor: '5', features: []),
      ];
      final recs = rank(cat, 'דירה נגישה בנתניה חובה מעלית לכיסא גלגלים עד 5200');
      final ids = recs.map((r) => r.property.id).toSet();
      expect(recs, isNotEmpty, reason: 'elevator flats should survive');
      expect(ids.contains('walk-c') || ids.contains('walk-d'), false,
          reason: 'walk-ups leaked to a wheelchair searcher: $ids');
      expect(recs.every((r) => r.property.features.contains('elevator')), true);
    });
    test('gate still passes qualifying stock through unchanged', () {
      final cat = [
        flat(id: 'has', price: 6000, rooms: 4, city: 'תל אביב', features: ['mamad']),
        flat(id: 'not', price: 6000, rooms: 4, city: 'תל אביב'),
      ];
      final recs = rank(cat, 'דירת 4 חדרים בתל אביב עם ממ"ד חובה עד 9000');
      expect(recs.map((r) => r.property.id), ['has']);
    });
  });

  group('P1 — profile must-haves influence ranking', () {
    // net-a is the only fully-accessible flat; net-b has an elevator only; net-c
    // neither. A wheelchair profile (deal-breakers = accessibility + elevator)
    // must surface net-a — and must CHANGE the order vs no profile.
    List<RentalProperty> cat() => [
          flat(id: 'net-a', price: 5000, rooms: 3, city: 'נתניה', lat: 32.32,
              lon: 34.85, floor: '2', features: ['feat_accessible', 'elevator']),
          flat(id: 'net-b', price: 4900, rooms: 3, city: 'נתניה', lat: 32.32,
              lon: 34.85, floor: '3', features: ['elevator']),
          flat(id: 'net-c', price: 4600, rooms: 3, city: 'נתניה', lat: 32.33,
              lon: 34.86, floor: '4', features: []),
        ];
    TenantProfile wheelchair() => TenantProfile(
          id: 'w', name: 'w', bio: '', photoUrls: const [], budgetMax: 5200,
          desiredRooms: 3, moveInWindow: 'מיידי', importantDetails: const [],
          dealBreakers: const ['נגישות', 'מעלית'],
        );
    List<ScoredProperty> run(TenantProfile? p) =>
        RecommendationEngine.recommendAsScored(candidates: cat(),
            query: SmartSearch.parse('דירת 3 חדרים בנתניה עד 5200'),
            profile: p, limit: 8, seed: 7);

    test('rich profile changes the order AND leads with the accessible flat', () {
      final none = run(null).map((r) => r.property.id).toList();
      final withP = run(wheelchair()).map((r) => r.property.id).toList();
      expect(withP.first, 'net-a',
          reason: 'accessible flat must lead for a wheelchair profile; got $withP');
      expect(withP != none, true,
          reason: 'profile must change ranking (was ignored). none=$none with=$withP');
    });
  });

  group('robustness', () {
    test('G1: Infinity coords do not crash the engine', () {
      final cat = [
        flat(id: 'inf', price: 6000, rooms: 3, city: 'תל אביב',
            lat: double.infinity, lon: double.infinity),
        flat(id: 'ok', price: 6000, rooms: 3, city: 'תל אביב'),
      ];
      expect(() => rank(cat, 'דירה בתל אביב עד 9000'), returnsNormally);
    });
  });
}
