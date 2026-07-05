import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

// A property with a transaction-type knob (the engine test's prop() is rent-only).
RentalProperty prop({
  required String id,
  int price = 6000,
  double rooms = 3,
  int sizeM2 = 70,
  String city = 'תל אביב',
  double lat = 32.07,
  double lon = 34.78,
  String floor = '2',
  List<String> features = const [],
  PropertyTransactionType type = PropertyTransactionType.rent,
  PropertyMarketSignals? signals,
}) =>
    RentalProperty(
      id: id,
      price: price,
      rooms: rooms,
      sizeM2: sizeM2,
      floor: floor,
      totalFloors: '20',
      city: city,
      neighborhood: '',
      street: 'הרצל',
      streetNumber: 10,
      lat: lat,
      lon: lon,
      propertyType: 'דירה',
      transactionType: type,
      entryDate: '',
      condition: 'טוב',
      ownerName: 'בעלים',
      agencyListing: false,
      features: features,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: signals,
    );

List<RentalProperty> bgRent() => [
      for (var i = 0; i < 12; i++)
        prop(
          id: 'bg$i',
          price: 5500 + i * 300,
          rooms: 2 + (i % 4).toDouble(),
          sizeM2: 55 + i * 5,
          lat: 32.06 + i * 0.002,
          lon: 34.77 + i * 0.002,
          signals: PropertyMarketSignals(views: 40 + i, likes: 5 + i, saves: 2),
        ),
    ];

int rankOf(List<ScoredProperty> l, String id) =>
    l.indexWhere((s) => s.property.id == id);

void dump(String persona, ScoredProperty s) {
  final sc = s.scorecard!;
  // ignore: avoid_print
  print('\n─── $persona · top = ${s.property.id} '
      '(${s.property.priceLabel}, ${s.property.sizeM2}מ״ר, ${s.property.city}) '
      '· fit ${sc.fitPct}% ───');
  for (final d in sc.dimensions.take(8)) {
    // ignore: avoid_print
    print('  • ${d.label}: ${(d.contributionPct * 100).round()}%'
        '${d.stat != null ? " · ${d.stat}" : ""}'
        ' [w=${(d.weightPct * 100).round()}%]');
  }
  if (sc.personaReasons.isNotEmpty) {
    // ignore: avoid_print
    print('  reasons: ${sc.personaReasons.join(" | ")}');
  }
  if (sc.concerns.isNotEmpty) {
    // ignore: avoid_print
    print('  concerns: ${sc.concerns.join(" | ")}');
  }
}

void main() {
  test('PERSONA A — budget-tight renter: total cost re-ranks same-rent flats',
      () {
    // Two flats, SAME rent ₪6,500, SAME size — differ only by city arnona rate.
    // Jerusalem arnona (72 ₪/m²/yr) > Beer Sheva (40) → higher true cost → lower.
    final candidates = [
      ...bgRent(),
      prop(id: 'cheapTotal', price: 6500, sizeM2: 90, city: 'באר שבע',
          lat: 31.25, lon: 34.79),
      prop(id: 'pricyTotal', price: 6500, sizeM2: 90, city: 'ירושלים',
          lat: 31.78, lon: 35.21),
    ];
    final q = SmartSearch.parse('דירת 3 חדרים עד 7000');
    final profile = TenantProfile(
      id: 'a', name: 'רון', bio: '', photoUrls: const [],
      budgetMax: 7000, desiredRooms: 3, moveInWindow: 'מיידי',
      importantDetails: const [], dealBreakers: const [],
    );
    final scored = RecommendationEngine.recommendAsScored(
        candidates: candidates, query: q, profile: profile, limit: 20, seed: 1);
    final cheap = scored.firstWhere((s) => s.property.id == 'cheapTotal');
    final pricy = scored.firstWhere((s) => s.property.id == 'pricyTotal');
    dump('A cheapTotal', cheap);
    dump('A pricyTotal', pricy);
    // The one with the lower TRUE cost should score at least as high on budget.
    final cb = cheap.scorecard!.dimensions.firstWhere((d) => d.key == 'budget');
    final pb = pricy.scorecard!.dimensions.firstWhere((d) => d.key == 'budget');
    // ignore: avoid_print
    print('A budget sat: cheap=${cb.contributionPct} pricy=${pb.contributionPct}');
    expect(cb.contributionPct >= pb.contributionPct, true,
        reason: 'lower true cost must not score worse on budget');
    expect(
        cheap.scorecard!.dimensions.any((d) => d.key == 'total_cost'), true,
        reason: 'total-cost dimension expected on a rental');
  });

  test('PERSONA B — investor buying: yield shows on sale, not total-cost', () {
    final candidates = [
      prop(id: 'saleLowYield', price: 3200000, sizeM2: 80,
          type: PropertyTransactionType.sale),
      prop(id: 'saleHighYield', price: 1900000, sizeM2: 80,
          type: PropertyTransactionType.sale),
      for (var i = 0; i < 8; i++)
        prop(id: 'sbg$i', price: 2400000 + i * 100000, sizeM2: 70 + i * 4,
            type: PropertyTransactionType.sale, lat: 32.06 + i * 0.003),
    ];
    final q = SmartSearch.parse('דירה להשקעה בתל אביב עם תשואה טובה');
    final scored = RecommendationEngine.recommendAsScored(
        candidates: candidates, query: q, profile: null, limit: 12, seed: 2);
    final hi = scored.firstWhere((s) => s.property.id == 'saleHighYield');
    dump('B highYield', hi);
    final dims = hi.scorecard!.dimensions;
    final yieldDim = dims.firstWhere((d) => d.key == 'yield');
    // ignore: avoid_print
    print('B yield weight=${(yieldDim.weightPct * 100).round()}% '
        'score=${yieldDim.contributionPct.toStringAsFixed(2)}');
    expect(yieldDim.weightPct > 0, true,
        reason: 'investment intent must give yield real weight (was 0)');
    // The higher-yield sale should rank above the lower-yield one.
    // ignore: avoid_print
    print('B ranks: high=${rankOf(scored, "saleHighYield")} '
        'low=${rankOf(scored, "saleLowYield")}');
    expect(rankOf(scored, 'saleHighYield') < rankOf(scored, 'saleLowYield'), true,
        reason: 'better-yield sale should outrank worse-yield sale');
    expect(dims.any((d) => d.key == 'total_cost'), false,
        reason: 'total monthly cost must NOT apply to a sale listing');
  });

  test('PERSONA C — beach lover: coast proximity shows near the sea', () {
    final candidates = [
      ...bgRent(),
      // On the TA beachfront vs a few km inland.
      prop(id: 'beach', price: 6800, lat: 32.08, lon: 34.767),
      prop(id: 'inland', price: 6800, lat: 32.08, lon: 34.86),
    ];
    final q = SmartSearch.parse('דירה בתל אביב ליד הים עד 7500');
    final scored = RecommendationEngine.recommendAsScored(
        candidates: candidates, query: q, profile: null, limit: 20, seed: 3);
    final beach = scored.firstWhere((s) => s.property.id == 'beach');
    dump('C beach', beach);
    final coast =
        beach.scorecard!.dimensions.where((d) => d.key == 'coast').toList();
    expect(coast.isNotEmpty, true, reason: 'coast dimension expected near sea');
    // ignore: avoid_print
    print('C coast: ${coast.first.stat} · weight='
        '${(coast.first.weightPct * 100).round()}%');
    expect(coast.first.weightPct > 0, true,
        reason: 'beach intent ("ליד הים") must give coast real weight');
    // Beach flat and inland flat are identical except location → coast decides.
    // ignore: avoid_print
    print('C ranks: beach=${rankOf(scored, "beach")} '
        'inland=${rankOf(scored, "inland")}');
    // Beach intent now either GATES OUT the far inland flat, or (if it's within
    // the 3km near-sea band) still ranks the beachfront one above it.
    final inlandRank = rankOf(scored, 'inland');
    expect(inlandRank == -1 || rankOf(scored, 'beach') < inlandRank, true,
        reason: 'a far-from-sea flat is gated out / ranked below the beachfront');
  });

  test('PERSONA D — student: campus proximity weighted + re-ranks', () {
    final candidates = [
      ...bgRent(),
      // At Tel Aviv University vs south of the city.
      prop(id: 'nearUni', price: 6500, lat: 32.1133, lon: 34.8044),
      prop(id: 'farUni', price: 6500, lat: 32.02, lon: 34.75),
    ];
    final q = SmartSearch.parse('דירה לסטודנט ליד האוניברסיטה עד 7000');
    final scored = RecommendationEngine.recommendAsScored(
        candidates: candidates, query: q, profile: null, limit: 20, seed: 4);
    final nearU = scored.firstWhere((s) => s.property.id == 'nearUni');
    dump('D nearUni', nearU);
    final uni = nearU.scorecard!.dimensions.firstWhere((d) => d.key == 'university');
    // ignore: avoid_print
    print('D uni weight=${(uni.weightPct * 100).round()}% score=${uni.contributionPct.toStringAsFixed(2)} '
        '· ranks near=${rankOf(scored, "nearUni")} far=${rankOf(scored, "farUni")}');
    expect(uni.weightPct > 0, true, reason: 'student intent must weight university');
    expect(rankOf(scored, 'nearUni') < rankOf(scored, 'farUni'), true,
        reason: 'flat by the campus should outrank the far one');
  });

  test('PERSONA E — luxury/high-floor: view weighted + re-ranks', () {
    final candidates = [
      ...bgRent(),
      prop(id: 'highFloor', price: 7000, floor: '18'),
      prop(id: 'lowFloor', price: 7000, floor: '2'),
    ];
    final q = SmartSearch.parse('דירה מפוארת בקומה גבוהה עם נוף עד 8000');
    final scored = RecommendationEngine.recommendAsScored(
        candidates: candidates, query: q, profile: null, limit: 20, seed: 5);
    final hi = scored.firstWhere((s) => s.property.id == 'highFloor');
    dump('E highFloor', hi);
    final view = hi.scorecard!.dimensions.firstWhere((d) => d.key == 'view');
    // ignore: avoid_print
    print('E view weight=${(view.weightPct * 100).round()}% score=${view.contributionPct.toStringAsFixed(2)} '
        '· ranks high=${rankOf(scored, "highFloor")} low=${rankOf(scored, "lowFloor")}');
    expect(view.weightPct > 0, true, reason: 'view intent must weight the floor axis');
    expect(rankOf(scored, 'highFloor') < rankOf(scored, 'lowFloor'), true,
        reason: 'high-floor flat should outrank the identical low-floor one');
  });

  test('REGRESSION — an ordinary search activates none of the intent factors', () {
    final candidates = [...bgRent(), prop(id: 't', price: 6500)];
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עד 7000');
    final scored = RecommendationEngine.recommendAsScored(
        candidates: candidates, query: q, profile: null, limit: 8, seed: 6);
    final dims = scored.first.scorecard!.dimensions;
    for (final key in ['coast', 'yield', 'university', 'young_area',
      'senior_area', 'luxury', 'view']) {
      final d = dims.where((d) => d.key == key);
      // Either absent from the shown card, or present at zero weight — never
      // skewing an ordinary search.
      expect(d.isEmpty || d.first.weightPct == 0, true,
          reason: '$key must stay off without intent');
    }
  });
}
