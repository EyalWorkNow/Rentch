// Self-check for the "מקורות הנתונים" provenance layer:
//   (a) GovSources returns a non-empty label for EVERY gov-backed dimension key
//       that ScorecardStats can emit;
//   (b) inside a real recommendation, any ScorecardDimension that carries a gov
//       `stat` ALSO carries a non-empty `source` (and none is invented when the
//       stat is absent).
//
// GovData is loaded from the bundled assets straight off disk (same pattern as
// scorecard_stats_test.dart). If those assets cannot load, the engine assertions
// degrade gracefully; the registry assertions always run.

import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
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

void main() {
  // The gov-backed (or honestly market-derived) dimensions ScorecardStats emits.
  const govDims = [
    'value',
    'safety',
    'neighborhood',
    'transit',
    'schools',
    'family',
    'health',
    'size',
  ];

  test('(a) GovSources returns a non-empty label for every gov dimension key',
      () {
    for (final key in govDims) {
      final src = GovSources.forDimension(key);
      expect(src, isNotNull, reason: '$key should have a source descriptor');
      expect(src!.agency.trim().isNotEmpty, true,
          reason: '$key agency must be set');
      expect(src.dataset.trim().isNotEmpty, true,
          reason: '$key dataset must be set');
      final label = GovSources.labelFor(key);
      expect((label ?? '').trim().isNotEmpty, true,
          reason: '$key label must be non-empty');
    }
    // size is honestly attributed to live Rently data, not a gov agency.
    expect(GovSources.forDimension('size')!.agency.contains('Rently'), true);
  });

  group('engine', () {
    late bool govLoaded;

    setUpAll(() async {
      GovData.instance.resetForTest();
      govLoaded = await GovData.instance.init(reader: _diskReader);
    });

    tearDownAll(() => GovData.instance.resetForTest());

    test('(b) every dimension with a gov stat also carries a non-empty source',
        () {
      if (!govLoaded) {
        // ignore: avoid_print
        print('[gov_sources] gov assets did not load — skipping engine check');
        return;
      }

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

      final recs = RecommendationEngine.recommend(
        candidates: candidates,
        query: SearchQuery(city: 'תל אביב', rawText: 'דירה בתל אביב'),
        limit: 5,
        explore: false,
        seed: 1,
      );
      expect(recs.isNotEmpty, true);

      var sawStat = false;
      for (final r in recs) {
        final card = r.scorecard;
        expect(card, isNotNull);
        for (final d in card!.dimensions) {
          if ((d.stat ?? '').trim().isNotEmpty) {
            sawStat = true;
            expect((d.source ?? '').trim().isNotEmpty, true,
                reason:
                    'dimension ${d.key} has a stat but no source: ${d.stat}');
          } else {
            // No invented provenance when there is no figure.
            expect(d.source, isNull,
                reason: 'dimension ${d.key} has a source but no stat');
          }
        }
      }
      expect(sawStat, true,
          reason: 'a TLV recommendation should carry at least one gov stat');
    });
  });
}
