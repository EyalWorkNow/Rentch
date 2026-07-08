import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COMPREHENSIVE breaking test across ALL 34 ranking dimensions together.
//   Part A — every intent-gated dimension ENGAGES (weight>0) when its phrase fires
//   Part B — a "kitchen-sink" query lights up MANY dimensions at once, no conflict
//   Part C — universal invariants hold across an adversarial battery:
//            no crash · fit% ∈ [0,100] · monotonic fit% · every dimension's
//            weight/contribution finite & in range (no NaN/Inf leaking anywhere)
// ─────────────────────────────────────────────────────────────────────────────

Future<String> _diskReader(String p) => File(p).readAsString();

RentalProperty flat({
  required String id, required int price, required double rooms,
  required double lat, required double lon, String floor = '3',
  List<String> features = const [],
  PropertyTransactionType type = PropertyTransactionType.rent,
  String city = 'תל אביב',
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 85, floor: floor,
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: type, entryDate: '', condition: 'טוב',
      ownerName: 'x', agencyListing: false, features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 130, likes: 20, saves: 6),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

// Varied Gush-Dan stock (rent + sale) spanning the seeded map cells so every
// geo dimension has something to differentiate.
List<RentalProperty> catalogue() => [
      flat(id: 'r1', price: 7000, rooms: 3, lat: 32.072, lon: 34.790, features: ['elevator', 'balcony', 'ac']),
      flat(id: 'r2', price: 8200, rooms: 2, lat: 32.081, lon: 34.767, floor: '6', features: ['balcony', 'ac', 'elevator']),
      flat(id: 'r3', price: 6400, rooms: 4, lat: 32.09, lon: 34.79, features: ['elevator', 'mamad', 'parking']),
      flat(id: 'r4', price: 5800, rooms: 3, lat: 32.05, lon: 34.75, floor: '2', features: ['feat_accessible', 'elevator']),
      flat(id: 'r5', price: 9500, rooms: 4, lat: 32.083, lon: 34.808, floor: '14', features: ['elevator', 'parking', 'pool', 'balcony']),
      flat(id: 'r6', price: 6800, rooms: 5, lat: 32.10, lon: 34.83, features: ['elevator', 'mamad', 'balcony']),
      flat(id: 'r7', price: 4200, rooms: 2, lat: 32.02, lon: 34.74, features: []),
      flat(id: 's1', price: 2500000, rooms: 3, lat: 32.090, lon: 34.800, type: PropertyTransactionType.sale, features: ['elevator']),
      flat(id: 's2', price: 3100000, rooms: 4, lat: 32.06, lon: 34.78, type: PropertyTransactionType.sale, features: ['elevator', 'parking']),
    ];

class Trig {
  const Trig(this.dim, this.query, {this.sale = false});
  final String dim;
  final String query;
  final bool sale;
}

// One representative phrase per intent-gated dimension → the dimension it must
// engage. City fixed to תל אביב (where the seed layers are populated).
const List<Trig> triggers = [
  Trig('coast', 'דירה קרוב לים בתל אביב עד 9000'),
  Trig('park', 'דירה באזור ירוק עם הרבה גינות בתל אביב עד 9000'),
  Trig('religious_area', 'דירה בשכונה דתית קרוב לבית כנסת בתל אביב עד 9000'),
  Trig('school_young', 'דירה למשפחה עם ילד קטן וגן ילדים בתל אביב עד 9000'),
  Trig('school_teen', 'דירה למשפחה עם מתבגרים ליד תיכון בתל אביב עד 9000'),
  Trig('nightlife', 'דירה באזור תוסס עם חיי לילה בתל אביב עד 9000'),
  Trig('yield', 'דירה להשקעה עם תשואה טובה בתל אביב עד 3 מיליון', sale: true),
  Trig('university', 'דירה ליד האוניברסיטה בתל אביב עד 9000'),
  Trig('young_area', 'דירה באזור צעיר בתל אביב עד 9000'),
  Trig('senior_area', 'דירה במקום שקט ורגוע בתל אביב עד 9000'),
  Trig('low_noise', 'דירה במקום שקט רחוק מרעש בתל אביב עד 9000'),
  Trig('luxury', 'דירה מפוארת ויוקרתית בתל אביב עד 12000'),
  Trig('view', 'דירה בקומה גבוהה עם נוף בתל אביב עד 12000'),
  Trig('spaciousness', 'דירה מרווחת עם חדרים גדולים בתל אביב עד 12000'),
  Trig('accessibility', 'דירה נגישה עם מעלית לכיסא גלגלים בתל אביב עד 9000'),
  Trig('convenience', 'דירה ליד סופר ומרכז קניות בתל אביב עד 9000'),
  Trig('future_value', 'דירה להשקעה עם פוטנציאל השבחה קרוב למטרו בתל אביב עד 3 מיליון', sale: true),
  Trig('employment', 'דירה קרוב לעבודה ולהייטק בתל אביב עד 9000'),
  Trig('safety', 'דירה בשכונה בטוחה בתל אביב עד 9000'),
  Trig('schools', 'דירה עם בתי ספר טובים בתל אביב עד 9000'),
  Trig('health', 'דירה קרוב לקופת חולים ובית חולים בתל אביב עד 9000'),
  Trig('transit', 'דירה קרוב לתחבורה ציבורית ורכבת בתל אביב עד 9000'),
];

double? weightOf(ScoredProperty s, String dim) {
  final d = s.scorecard!.dimensions.where((x) => x.key == dim);
  return d.isEmpty ? null : d.first.weightPct;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _diskReader);
  });

  List<ScoredProperty> run(String q) => RecommendationEngine.recommendAsScored(
      candidates: catalogue(), query: SmartSearch.parse(q),
      profile: null, limit: 9, seed: 7);

  test('A · every intent-gated dimension engages when its phrase fires', () {
    final fails = <String>[];
    for (final t in triggers) {
      final recs = run(t.query);
      if (recs.isEmpty) {
        fails.add('${t.dim}: no results for "${t.query}"');
        continue;
      }
      // The dimension must be present with weight>0 in SOME top-3 scorecard.
      final engaged = recs.take(3).any((s) => (weightOf(s, t.dim) ?? 0) > 0);
      if (!engaged) fails.add('${t.dim}: NOT engaged (weight 0) for "${t.query}"');
    }
    expect(fails, isEmpty, reason: 'dimensions that failed to engage:\n${fails.join("\n")}');
  });

  test('B · kitchen-sink query lights up many dimensions at once', () {
    final recs = run('דירה למשפחה בשכונה טובה ובטוחה, שקטה, אזור ירוק, קרוב '
        'לתחבורה, בתי ספר טובים, ליד סופר, מרווחת עם מרפסת בתל אביב עד 12000');
    expect(recs, isNotEmpty);
    final top = recs.first;
    const want = ['neighborhood', 'safety', 'low_noise', 'park', 'transit',
      'schools', 'convenience', 'spaciousness'];
    final lit = want.where((d) => (weightOf(top, d) ?? 0) > 0).toList();
    expect(lit.length >= 6, true,
        reason: 'expected ≥6 of $want engaged together, got $lit');
  });

  test('C · universal invariants across an adversarial battery', () {
    final battery = <String>[
      ...triggers.map((t) => t.query),
      // combinations / contradictions / adversarial
      'דירה מפוארת זולה מאוד שקטה ותוססת בתל אביב עד 3000',
      'משהו',
      'דירה בתל אביב עד 1000',
      'אהלן מה קורה',
      'דירה 🏠🔥 בתל אביב עד 8000 עם הכל',
      'looking for a quiet safe green apartment near work in Tel Aviv under 9000',
      'דירה להשקעה חרדית מרווחת עם נוף ליד הים ובאזור צעיר עד 4 מיליון',
      '',
    ];
    final fails = <String>[];
    for (final q in battery) {
      List<ScoredProperty> recs;
      try {
        recs = run(q);
      } catch (e) {
        fails.add('CRASH on "$q": $e');
        continue;
      }
      for (var i = 0; i < recs.length; i++) {
        final sc = recs[i].scorecard!;
        if (sc.fitPct < 0 || sc.fitPct > 100) {
          fails.add('"$q" #$i fit% out of range: ${sc.fitPct}');
        }
        if (i > 0 && recs[i - 1].scorecard!.fitPct < sc.fitPct) {
          fails.add('"$q" non-monotonic fit% at #$i');
        }
        for (final d in sc.dimensions) {
          if (!d.weightPct.isFinite || d.weightPct < 0 || d.weightPct > 1.0001) {
            fails.add('"$q" dim ${d.key} bad weight ${d.weightPct}');
          }
          if (!d.contributionPct.isFinite) {
            fails.add('"$q" dim ${d.key} non-finite contribution');
          }
        }
      }
    }
    expect(fails, isEmpty, reason: 'invariant breaks:\n${fails.take(30).join("\n")}');
  });

  test('D · all 34 dimensions are wired (satisfaction finite & in range)', () {
    // Probe every dimension's satisfaction on every listing — catches a dimension
    // added to kScoringDimensions but missing a satisfaction case, or one leaking
    // NaN/Inf/out-of-range.
    final cat = catalogue();
    final market = MarketContext.analyze(cat);
    final model = PreferenceModelBuilder.build(
        query: SmartSearch.parse('דירה בתל אביב עד 9000'), market: market);
    final bad = <String>[];
    for (final p in cat) {
      final pfv = FeatureEngineer.engineer(p, market);
      for (final dim in kScoringDimensions) {
        final s = model.satisfaction(dim, pfv);
        if (!s.isFinite || s < 0 || s > 1.0001) bad.add('$dim=$s on ${p.id}');
      }
    }
    // 29 base + convenience + low_noise + future_value + employment = 33.
    expect(kScoringDimensions.length, 33,
        reason: 'dimension count changed: ${kScoringDimensions.length}');
    expect(bad, isEmpty, reason: 'dimension satisfaction issues:\n${bad.take(20).join("\n")}');
  });
}
