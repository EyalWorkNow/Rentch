import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Realistic-ish Israeli listing.
RentalProperty flat({
  required String id,
  required int price,
  required double rooms,
  required int sizeM2,
  required String city,
  required double lat,
  required double lon,
  String floor = '3',
  List<String> features = const [],
  PropertyTransactionType type = PropertyTransactionType.rent,
  bool verified = true,
  int views = 120,
  int likes = 14,
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
      marketSignals: PropertyMarketSignals(views: views, likes: likes, saves: 4),
      verification: verified
          ? PropertyVerification.cameraVideo(
              videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1))
          : null,
    );

// A realistic mixed catalogue across real Israeli cities.
List<RentalProperty> catalogue() => [
      // Bnei Brak — charedi family stock
      flat(id: 'bb-4rm', price: 5400, rooms: 4, sizeM2: 95, city: 'בני ברק',
          lat: 32.083, lon: 34.836, features: ['elevator', 'mamad', 'balcony']),
      flat(id: 'bb-3rm', price: 4800, rooms: 3, sizeM2: 72, city: 'בני ברק',
          lat: 32.086, lon: 34.842, features: ['mamad']),
      flat(id: 'bb-5rm-pricey', price: 6900, rooms: 5, sizeM2: 120,
          city: 'בני ברק', lat: 32.08, lon: 34.83,
          features: ['elevator', 'mamad', 'parking', 'balcony']),
      // Tel Aviv — center, beach, nightlife
      flat(id: 'ta-beach-2rm', price: 8200, rooms: 2, sizeM2: 55,
          city: 'תל אביב', lat: 32.081, lon: 34.767, floor: '5',
          features: ['balcony', 'ac']),
      flat(id: 'ta-center-3rm', price: 8800, rooms: 3, sizeM2: 78,
          city: 'תל אביב', lat: 32.072, lon: 34.781, floor: '4',
          features: ['elevator', 'ac', 'balcony']),
      flat(id: 'ta-far-3rm', price: 7300, rooms: 3, sizeM2: 80, city: 'תל אביב',
          lat: 32.05, lon: 34.86, features: ['ac']),
      flat(id: 'ta-penthouse', price: 15000, rooms: 4, sizeM2: 140,
          city: 'תל אביב', lat: 32.083, lon: 34.77, floor: '22',
          features: ['elevator', 'ac', 'parking', 'balcony', 'storage', 'pool']),
      // Ramat Aviv — by Tel Aviv University
      flat(id: 'tau-2rm', price: 6400, rooms: 2, sizeM2: 58, city: 'תל אביב',
          lat: 32.1133, lon: 34.8044, features: ['ac', 'elevator']),
      // Beer Sheva — student stock by BGU
      flat(id: 'bgu-3rm', price: 2600, rooms: 3, sizeM2: 70, city: 'באר שבע',
          lat: 31.2635, lon: 34.8018, features: ['ac']),
      flat(id: 'bs-far', price: 2400, rooms: 3, sizeM2: 68, city: 'באר שבע',
          lat: 31.23, lon: 34.77, features: ['ac']),
      // Netanya — retirees, quiet, near sea
      flat(id: 'net-elev', price: 4900, rooms: 3, sizeM2: 82, city: 'נתניה',
          lat: 32.32, lon: 34.853, floor: '2', features: ['elevator', 'ac']),
      flat(id: 'net-walkup', price: 4600, rooms: 3, sizeM2: 80, city: 'נתניה',
          lat: 32.31, lon: 34.86, floor: '4', features: ['ac']),
      // Herzliya — luxury
      flat(id: 'hrz-lux', price: 13500, rooms: 4, sizeM2: 135, city: 'הרצליה',
          lat: 32.16, lon: 34.84, floor: '10',
          features: ['elevator', 'ac', 'parking', 'pool', 'storage', 'balcony']),
      // For-sale — investor stock
      flat(id: 'sale-ta', price: 3400000, rooms: 3, sizeM2: 78,
          city: 'תל אביב', lat: 32.07, lon: 34.78,
          type: PropertyTransactionType.sale),
      flat(id: 'sale-bs', price: 1250000, rooms: 4, sizeM2: 95,
          city: 'באר שבע', lat: 31.25, lon: 34.79,
          type: PropertyTransactionType.sale),
      flat(id: 'sale-net', price: 1750000, rooms: 3, sizeM2: 80, city: 'נתניה',
          lat: 32.32, lon: 34.85, type: PropertyTransactionType.sale),
    ];

int rankOf(List<ScoredProperty> l, String id) =>
    l.indexWhere((s) => s.property.id == id);

void show(String persona, String query, List<ScoredProperty> recs) {
  // ignore: avoid_print
  print('\n═══════════════════════════════════════════════════════');
  // ignore: avoid_print
  print('👤 $persona');
  // ignore: avoid_print
  print('   🔎 "$query"');
  if (recs.isEmpty) {
    // ignore: avoid_print
    print('   ⚠️  no results');
    return;
  }
  for (final s in recs.take(3)) {
    final p = s.property;
    final sc = s.scorecard!;
    final top = (List.of(sc.dimensions)
          ..sort((a, b) => b.weightPct.compareTo(a.weightPct)))
        .take(4)
        .map((d) => '${d.label} ${(d.contributionPct * 100).round()}%'
            '${d.stat != null ? "(${d.stat})" : ""}')
        .join(', ');
    // ignore: avoid_print
    print('   • ${p.id}: ${p.priceLabel}, ${p.rooms.toInt()}חד׳/${p.sizeM2}מ״ר, '
        '${p.city} · fit ${sc.fitPct}%');
    // ignore: avoid_print
    print('       ${top}');
    if (sc.concerns.isNotEmpty) {
      // ignore: avoid_print
      print('       ⚠ ${sc.concerns.join(" | ")}');
    }
  }
}

List<ScoredProperty> run(String query, {TenantProfile? profile}) =>
    RecommendationEngine.recommendAsScored(
      candidates: catalogue(),
      query: SmartSearch.parse(query),
      profile: profile,
      limit: 8,
      seed: 7,
    );

void main() {
  test('אברהם — אברך חרדי, בני ברק, תקציב הדוק, משפחה', () {
    const q = 'דירת 4 חדרים בבני ברק עד 5500 קרוב לבית ספר ולקהילה למשפחה';
    final profile = TenantProfile(
      id: 'avraham', name: 'אברהם', bio: '', photoUrls: const [],
      budgetMax: 5500, desiredRooms: 4, moveInWindow: 'מיידי',
      importantDetails: const ['מתאים למשפחות', 'קרוב לבית כנסת'],
      dealBreakers: const [],
    );
    final recs = run(q, profile: profile);
    show('אברהם · אברך חרדי · בני ברק · ₪5500 · 4 חד׳ · משפחתי', q, recs);
    expect(recs.isNotEmpty, true);
    expect(recs.first.property.city.contains('בני ברק'), true);
  });

  test('נועה — הייטקיסטית רווקה, תל אביב, ים וחיי לילה', () {
    const q = 'דירה בתל אביב קרוב לים ולחיי לילה עד 9000';
    final recs = run(q);
    show('נועה · הייטק · תל אביב · ₪9000 · ים+נייטלייף', q, recs);
    expect(recs.isNotEmpty, true);
    // "קרוב לים" must surface the beachfront flat into the shortlist (it was
    // off-list before the coast fix).
    expect(recs.take(3).any((s) => s.property.id == 'ta-beach-2rm'), true,
        reason: 'beach intent must surface the beachfront flat in the top 3');
  });

  test('יוסי — סטודנט, באר שבע, ליד הקמפוס, זול', () {
    const q = 'דירה לסטודנט בבאר שבע ליד האוניברסיטה עד 2800';
    final recs = run(q);
    show('יוסי · סטודנט · באר שבע · ₪2800 · ליד BGU', q, recs);
    expect(recs.isNotEmpty, true);
  });

  test('רחל ומשה — גמלאים, נתניה, שקט, מעלית', () {
    const q = 'דירה שקטה בנתניה עם מעלית עד 5000 לזוג מבוגר';
    final recs = run(q);
    show('רחל ומשה · גמלאים · נתניה · ₪5000 · שקט+מעלית', q, recs);
    expect(recs.isNotEmpty, true);
    // "מבוגר" → accessibility weighted; the elevator flat leads the walk-up.
    final acc = recs.first.scorecard!.dimensions
        .where((d) => d.key == 'accessibility');
    expect(acc.isNotEmpty && acc.first.weightPct > 0, true,
        reason: 'elderly intent must weight accessibility');
    expect(recs.first.property.id == 'net-elev', true,
        reason: 'the flat with an elevator should lead for an elderly couple');
  });

  test('דנה — משפחה: דירה מרווחת (spaciousness) עוקף יותר חדרים', () {
    final candidates = [
      flat(id: 'roomy', price: 7000, rooms: 3, sizeM2: 102, city: 'תל אביב',
          lat: 32.07, lon: 34.78), // 34 m²/room
      flat(id: 'cramped', price: 7000, rooms: 4, sizeM2: 72, city: 'תל אביב',
          lat: 32.07, lon: 34.78), // 18 m²/room
      ...catalogue(),
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: candidates,
      query: SmartSearch.parse('דירה מרווחת בתל אביב עד 8000'),
      profile: null,
      limit: 12,
      seed: 8,
    );
    show('דנה · מרווחת · תל אביב', 'דירה מרווחת בתל אביב עד 8000', recs);
    final sp = recs
        .firstWhere((s) => s.property.id == 'roomy')
        .scorecard!
        .dimensions
        .firstWhere((d) => d.key == 'spaciousness');
    expect(sp.weightPct > 0, true,
        reason: 'spacious intent must weight spaciousness');
    expect(rankOf(recs, 'roomy') < rankOf(recs, 'cramped'), true,
        reason: 'the roomier flat should outrank the cramped one with more rooms');
  });

  test('דניאל — משקיע, קונה לתשואה', () {
    const q = 'דירה להשקעה עם תשואה טובה עד 2 מיליון';
    final recs = run(q);
    show('דניאל · משקיע · קנייה · תשואה · עד 2M', q, recs);
    expect(recs.isNotEmpty, true);
    // Investment intent → sale gate: NEVER surface rentals.
    expect(
        recs.every(
            (s) => s.property.transactionType == PropertyTransactionType.sale),
        true,
        reason: 'investor search must return only sale listings');
    // "2 מיליון" parsed as a budget → the ₪3.4M flat is over budget, so an
    // under-2M sale leads.
    expect(recs.first.property.price <= 2000000, true,
        reason: '"עד 2 מיליון" must cap the budget at 2M');
  });

  test('display order is monotonic in fit% (ranking ↔ fit% aligned)', () {
    const queries = [
      'דירת 4 חדרים בבני ברק עד 5500 למשפחה',
      'דירה בתל אביב קרוב לים עד 9000',
      'דירה לסטודנט בבאר שבע ליד האוניברסיטה עד 2800',
      'דירה להשקעה עם תשואה עד 2 מיליון',
      'דירה מפוארת בהרצליה בקומה גבוהה עם נוף',
    ];
    for (final q in queries) {
      final recs = run(q);
      for (var i = 1; i < recs.length; i++) {
        expect(recs[i - 1].scorecard!.fitPct >= recs[i].scorecard!.fitPct, true,
            reason: 'fit% must never increase down the list — "$q"');
      }
    }
  });

  test('שירה — משפחה צעירה, פנטהאוז יוקרתי בהרצליה עם נוף', () {
    const q = 'דירה מפוארת בהרצליה בקומה גבוהה עם נוף ובריכה';
    final recs = run(q);
    show('שירה · יוקרה · הרצליה · פנטהאוז+נוף', q, recs);
    expect(recs.isNotEmpty, true);
  });
}
