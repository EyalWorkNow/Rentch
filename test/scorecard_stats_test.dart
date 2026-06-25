// Self-check for ScorecardStats.statLabels — proves that:
//   (a) for a property in a known gov city (תל אביב), the value/safety/
//       neighborhood/transit/size labels carry REAL numbers traced to gov data;
//   (b) for a property with NO gov match and NO coordinates, the gov-backed keys
//       are OMITTED (never faked) — only market-derived keys (size) may remain.
//
// GovData is loaded from the real bundled assets straight off disk (same pattern
// as govdata_test.dart). If those assets cannot load, the gov-backed assertions
// are skipped but the omission logic is still exercised via the no-gov property.

import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/scorecard_stats.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

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

final _hasDigit = RegExp(r'\d');

void main() {
  late bool govLoaded;

  setUpAll(() async {
    GovData.instance.resetForTest();
    govLoaded = await GovData.instance.init(reader: _diskReader);
  });

  tearDownAll(() => GovData.instance.resetForTest());

  test('(a) Tel Aviv property → value/safety/neighborhood carry real numbers',
      () {
    if (!govLoaded) {
      // ignore: avoid_print
      print('[scorecard_stats] gov assets did not load — skipping gov asserts');
      return;
    }

    // A small but realistic Tel Aviv market so MarketContext percentiles exist.
    final candidates = [
      prop(
          id: 'subject',
          city: 'תל אביב',
          lat: 32.0775,
          lon: 34.7874,
          price: 7200,
          sizeM2: 92),
      for (var i = 0; i < 8; i++)
        prop(
            id: 'f$i',
            city: 'תל אביב',
            lat: 32.07 + i * 0.003,
            lon: 34.78 + i * 0.003,
            price: 6200 + i * 250,
            sizeM2: 60 + i * 6),
    ];
    final market = MarketContext.analyze(candidates);
    final labels = ScorecardStats.statLabels(candidates.first, market);

    // ignore: avoid_print
    print('[scorecard_stats] תל אביב labels: $labels');

    for (final key in ['value', 'safety', 'neighborhood', 'transit', 'size']) {
      expect(labels.containsKey(key), true, reason: '$key should be present');
      expect(_hasDigit.hasMatch(labels[key]!), true,
          reason: '$key must contain a real number: ${labels[key]}');
    }

    // Trace each number to its source.
    expect(labels['value']!.contains('₪'), true);
    expect(labels['neighborhood'], 'אשכול חברתי-כלכלי 8/10'); // CBS cluster 8
    // safety relabel: honest reported-crime percentile, NOT the misleading
    // "אחוזון בטיחות 1" framing that read as totally-unsafe for Tel Aviv.
    expect(labels['safety']!.contains('פשיעה מדווחת לנפש'), true);
    expect(labels['safety']!.contains('אחוזון בטיחות'), false);
    expect(labels['transit']!.contains('ק״מ מהרכבת'), true);
    expect(labels['size']!.contains('92 מ״ר'), true);

    // New gov-backed livability dimensions now surface as explained stats.
    // Tel Aviv has indexed schools (coords), demographics, and health facilities.
    expect(labels.containsKey('schools'), true,
        reason: 'schools label should be present for a coord-bearing TLV unit');
    expect(labels['schools']!.contains('מוסדות חינוך'), true);

    expect(labels.containsKey('family'), true,
        reason: 'family/demographics label should be present for TLV');
    expect(labels['family']!.contains('% ילדים'), true);
    expect(_hasDigit.hasMatch(labels['family']!), true);

    expect(labels.containsKey('health'), true,
        reason: 'health access label should be present for TLV');
    expect(labels['health']!.contains('שירותי בריאות'), true);
  });

  test('(b) no gov match + no coords → gov-backed keys are OMITTED, not faked',
      () {
    // Unknown locality + zero coordinates: no gov anchor, no crime, no SES,
    // no rail distance. Only the live-market size label may survive.
    final candidates = [
      prop(id: 'x0', city: 'עיירה דמיונית', lat: 0, lon: 0, sizeM2: 80),
      for (var i = 0; i < 6; i++)
        prop(
            id: 'fx$i',
            city: 'עיירה דמיונית',
            lat: 0,
            lon: 0,
            price: 4000 + i * 100,
            sizeM2: 50 + i * 5),
    ];
    final market = MarketContext.analyze(candidates);
    final labels = ScorecardStats.statLabels(candidates.first, market);

    // ignore: avoid_print
    print('[scorecard_stats] no-gov labels: $labels');

    // Gov-backed dimensions must be absent (no fabricated numbers).
    expect(labels.containsKey('safety'), false);
    expect(labels.containsKey('neighborhood'), false);
    expect(labels.containsKey('transit'), false);
    // New gov livability dimensions must also be OMITTED (not faked) when the
    // locality/coords have no gov coverage.
    expect(labels.containsKey('schools'), false);
    expect(labels.containsKey('family'), false);
    expect(labels.containsKey('health'), false);
    // value: no gov ₪/m² anchor; ₪/m² alone with no comparison ⇒ a bare ratio
    // is still real (derived from price/size), so the engine may emit just the
    // unit ₪/m². It must NEVER claim a comparison-to-median figure.
    if (labels.containsKey('value')) {
      expect(labels['value']!.contains('לחציון האזור'), false);
      expect(labels['value']!.contains('הוגן'), false);
    }
    // size is market-derived (not gov) and remains valid.
    expect(labels.containsKey('size'), true);
    expect(_hasDigit.hasMatch(labels['size']!), true);
  });
}
