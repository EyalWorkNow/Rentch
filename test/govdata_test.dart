import 'dart:io';

import 'package:dating_app/core/govdata/geo_intelligence.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/govdata/market_intelligence.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Reads the real bundled assets straight off disk (no Flutter asset binding).
Future<String> _diskReader(String path) => File(path).readAsString();

RentalProperty prop({
  required String id,
  required String city,
  required double lat,
  required double lon,
  int price = 6000,
  double rooms = 3,
  int sizeM2 = 75,
}) {
  return RentalProperty(
    id: id,
    price: price,
    rooms: rooms,
    sizeM2: sizeM2,
    floor: '2',
    totalFloors: '5',
    city: city,
    neighborhood: '',
    street: 'הרצל',
    streetNumber: 10,
    lat: lat,
    lon: lon,
    propertyType: 'דירה',
    entryDate: '',
    condition: 'טוב',
    ownerName: 'בעלים',
    agencyListing: false,
    features: const [],
    media: const [
      PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image),
    ],
  );
}

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    final ok = await GovData.instance.init(reader: _diskReader);
    expect(ok, true, reason: 'gov assets should load from disk');
  });

  tearDownAll(() => GovData.instance.resetForTest());

  test('loads the real ingested datasets', () {
    expect(GovData.instance.loaded, true);
    expect(GovData.instance.localities.length, greaterThan(800));
  });

  test('Tel Aviv resolves with real centroid + socioeconomic cluster', () {
    final ta = GovData.instance.localityByName('תל אביב');
    expect(ta, isNotNull);
    // centroid derived from ~1100 transit stops sits in central TA
    expect((ta!.lat - 32.07).abs() < 0.1, true);
    expect((ta.lon - 34.78).abs() < 0.1, true);
    expect(ta.ses, 8); // CBS cluster
    expect(GovData.instance.socioeconomic('תל אביב'), 8);
    expect(GovData.instance.socioeconomic('בני ברק'), 2);
  });

  test('transit density + nearest rail reflect real stops', () {
    // central Tel Aviv
    final density = GovData.instance.transitDensityScore(32.0775, 34.7874);
    expect(density > 0.3, true);
    final railKm = GovData.instance.nearestRailKm(32.0775, 34.7874);
    expect(railKm, isNotNull);
    expect(railKm! < 3.0, true); // a rail station within a few km
  });

  test('market prior available for major cities', () {
    final ta = GovData.instance.rentPerSqm('תל אביב');
    expect(ta, isNotNull);
    expect(ta! > 60, true); // ₪/m²/month seed for TLV
    expect(GovData.instance.rentPerSqm('באר שבע')! < ta, true);
  });

  test('GeoIntelligence centrality ranks TLV above the periphery', () {
    final tlv = GeoIntelligence.centrality(32.0775, 34.7874, 'תל אביב');
    final periphery = GeoIntelligence.centrality(31.0689, 35.0269, 'דימונה');
    expect(tlv > periphery, true);
  });

  test('MarketIntelligence flags an underpriced TLV unit via gov anchor', () {
    // TLV seed ≈ ₪88/m²; 80 m² ⇒ fair ≈ ₪7040. Priced at 5000 ⇒ underpriced.
    final residual = MarketIntelligence.govValueResidual(
      price: 5000,
      liveFair: null,
      city: 'תל אביב',
      sizeM2: 80,
      marketSize: 3,
    );
    expect(residual > 0.2, true);
  });

  test('crime → safety score is real, ranged and discriminative', () {
    final counts = GovData.instance.crimeCounts('תל אביב');
    expect(counts, isNotNull);
    expect(counts![0] > 1000, true); // total recorded offences
    final tlv = GovData.instance.safetyScore('תל אביב');
    final jlm = GovData.instance.safetyScore('ירושלים');
    expect(tlv, isNotNull);
    expect(jlm, isNotNull);
    expect(tlv! >= 0 && tlv <= 1, true);
    expect(tlv != jlm, true); // per-capita rates differ → discriminative
  });

  test('demographics resolve with sane shares', () {
    final d = GovData.instance.demographics('תל אביב');
    expect(d, isNotNull);
    expect(d!['pop']! > 300000, true);
    final sum = d['youngShare']! + d['childShare']! + d['seniorShare']!;
    expect((sum - 1.0).abs() < 0.06, true); // shares ≈ 1
  });

  test('school density + health + air-quality signals work', () {
    // central Tel Aviv has many education institutions
    expect(GovData.instance.schoolDensityScore(32.0775, 34.7874) > 0.2, true);
    expect(GovData.instance.healthAccessScore('תל אביב') > 0, true);
    final airKm = GovData.instance.nearestAirStationKm(32.0775, 34.7874);
    expect(airKm, isNotNull);
    expect(airKm! < 25, true);
  });

  test('cross-dataset name join is robust (police vs registry spelling)', () {
    // police spells it "תל אביב יפו"; registry "תל אביב - יפו"; user "תל אביב"
    expect(GovData.instance.crimeCounts('תל אביב'), isNotNull);
    expect(GovData.instance.crimeCounts('תל אביב יפו'), isNotNull);
    expect(GovData.instance.crimeCounts('תל אביב - יפו'), isNotNull);
  });

  test('engine end-to-end uses gov data (neighbourhood quality flows through)',
      () {
    // Two otherwise-identical listings; only the locality (and thus its real
    // socioeconomic cluster + centrality) differs. With no budget/amenity
    // signal, the higher-SES area should not rank below the lower one.
    final candidates = [
      prop(id: 'tlv', city: 'תל אביב', lat: 32.0775, lon: 34.7874),
      prop(id: 'bash', city: 'באר שבע', lat: 31.2529, lon: 34.7888),
      // filler so the market context has data
      for (var i = 0; i < 8; i++)
        prop(
            id: 'f$i',
            city: 'תל אביב',
            lat: 32.07 + i * 0.003,
            lon: 34.78 + i * 0.003,
            price: 6200 + i * 120),
    ];
    // NO city in the query — otherwise the city gate correctly drops the
    // wrong-city Beer Sheva flat entirely (it wouldn't appear at all), which
    // defeats the point. With both eligible, gov quality alone must decide.
    final q = SmartSearch.parse('דירת 3 חדרים');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 10,
      explore: false,
    );
    final tlvRank = recs.indexWhere((r) => r.property.id == 'tlv');
    final bashRank = recs.indexWhere((r) => r.property.id == 'bash');
    expect(tlvRank >= 0, true);
    expect(bashRank >= 0, true); // both present → a pure gov-quality comparison
    // Tel Aviv (higher SES + centrality) ranks above Beer Sheva on gov data alone.
    expect(tlvRank < bashRank, true);
  });
}
