import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the CBS statistical-area layer: point-in-polygon resolves a flat's
// own block, and its block-level SES OVERRIDES the city average so two flats in
// the SAME city (תל אביב) but different blocks rank differently for "שכונה טובה".

Future<String> _diskReader(String p) => File(p).readAsString();

RentalProperty flat(String id, double lat, double lon) => RentalProperty(
      id: id, price: 8000, rooms: 3, sizeM2: 80, floor: '3', totalFloors: '20',
      city: 'תל אביב', neighborhood: '', street: 'הרצל', streetNumber: 10,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'x', agencyListing: false, features: const [],
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

int rankOf(List<ScoredProperty> l, String id) =>
    l.indexWhere((s) => s.property.id == id);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _diskReader);
  });

  test('point-in-polygon resolves the block (and null outside)', () {
    // Real CBS blocks: Shapira (south TLV) is low-SES; central TLV is high-SES —
    // the same city, two very different micro-areas. Ranges (not exact clusters)
    // so a CBS re-publish doesn't break the test.
    final shapira = GovData.instance.statAreaAt(32.0545, 34.7790);
    final central = GovData.instance.statAreaAt(32.0700, 34.7750);
    expect(shapira, isNotNull);
    expect(central, isNotNull);
    expect(shapira!.ses, lessThanOrEqualTo(4), reason: 'Shapira is a low-SES block');
    expect(central!.ses, greaterThanOrEqualTo(8), reason: 'central TLV is high-SES');
    expect(GovData.instance.statAreaAt(32.05, 34.68), isNull);   // sea, no polygon
    expect(GovData.instance.statAreaAt(double.infinity, 34.0), isNull);
  });

  test('"שכונה טובה" ranks the high-SES block above the low-SES block (same city)',
      () {
    final cat = [
      flat('poor-block', 32.0545, 34.7790), // Shapira — low-SES block
      flat('rich-block', 32.0700, 34.7750), // central TLV — high-SES block
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat,
      query: SmartSearch.parse('דירה בשכונה טובה בתל אביב עד 9000'),
      profile: null, limit: 8, seed: 7,
    );
    expect(recs.length, 2);
    expect(rankOf(recs, 'rich-block') < rankOf(recs, 'poor-block'), true,
        reason: 'the high-SES micro-block should outrank the low-SES one');
    final nb = recs.first.scorecard!.dimensions.where((d) => d.key == 'neighborhood');
    expect(nb.isNotEmpty && nb.first.weightPct > 0, true,
        reason: 'neighborhood dimension not engaged');
  });

  test('CRUSH — point-in-polygon over the real layer never throws / emits garbage',
      () {
    // pathological coords must return null, never crash
    for (final ll in const [
      [double.nan, 34.0], [32.0, double.infinity], [0.0, 0.0],
      [-90.0, 200.0], [999.0, -999.0],
    ]) {
      expect(GovData.instance.statAreaAt(ll[0], ll[1]), isNull);
    }
    // sweep a grid over the country: any resolved area has SES 0..10 and age
    // shares that are finite and sum to ~1 (0 shares only for an empty block).
    var resolved = 0;
    for (var lat = 29.5; lat <= 33.3; lat += 0.05) {
      for (var lon = 34.3; lon <= 35.9; lon += 0.05) {
        final sa = GovData.instance.statAreaAt(lat, lon);
        if (sa == null) continue;
        resolved++;
        expect(sa.ses, inInclusiveRange(0, 10));
        final s = sa.youngShare + sa.childShare + sa.seniorShare;
        expect(s.isFinite, true);
        expect(s == 0 || (s - 1.0).abs() < 0.02, true,
            reason: 'shares must be ~1 (or 0 for an empty block), got $s');
      }
    }
    expect(resolved, greaterThan(100),
        reason: 'a national grid must land inside many real blocks');
  });
}
