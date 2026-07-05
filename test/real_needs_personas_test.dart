import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

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
  bool verified = true,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor,
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      entryDate: '', condition: 'טוב', ownerName: 'בעלים', agencyListing: false,
      features: features,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: verified
          ? PropertyVerification.cameraVideo(
              videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1))
          : null,
    );

List<RentalProperty> catalogue() => [
      // ── Tel Aviv, near TAU (32.1133, 34.8044) — roommate + student stock ──────
      flat(id: 'tau-roomy', price: 6400, rooms: 3, sizeM2: 96, // 32 m²/room
          city: 'תל אביב', lat: 32.112, lon: 34.805,
          features: ['ac', 'balcony', 'elevator']),
      flat(id: 'tau-cramped', price: 6300, rooms: 3, sizeM2: 60, // 20 m²/room
          city: 'תל אביב', lat: 32.113, lon: 34.804, features: ['ac']),
      flat(id: 'ta-far-cheap', price: 6000, rooms: 3, sizeM2: 75, city: 'תל אביב',
          lat: 32.05, lon: 34.86, features: ['ac']),
      flat(id: 'ta-rail', price: 5900, rooms: 2, sizeM2: 52, city: 'תל אביב',
          lat: 32.083, lon: 34.80, features: ['ac']), // near light rail area
      // ── Petah Tikva — WFH stock ───────────────────────────────────────────────
      flat(id: 'pt-spacious', price: 5900, rooms: 4, sizeM2: 116, // 29 m²/room
          city: 'פתח תקווה', lat: 32.088, lon: 34.887,
          features: ['ac', 'balcony', 'storage', 'renovated']),
      flat(id: 'pt-small', price: 5700, rooms: 3, sizeM2: 66, city: 'פתח תקווה',
          lat: 32.09, lon: 34.88, features: ['ac']),
      // ── Haifa — accessibility stock ───────────────────────────────────────────
      flat(id: 'hf-elevator', price: 4800, rooms: 3, sizeM2: 78, city: 'חיפה',
          lat: 32.79, lon: 34.99, floor: '6', features: ['elevator', 'ac']),
      flat(id: 'hf-walkup', price: 4600, rooms: 3, sizeM2: 80, city: 'חיפה',
          lat: 32.80, lon: 34.98, floor: '4', features: ['ac']),
      flat(id: 'hf-ground', price: 4700, rooms: 3, sizeM2: 74, city: 'חיפה',
          lat: 32.81, lon: 34.99, floor: '0', features: ['ac']),
      // ── Bnei Brak — large religious family stock ──────────────────────────────
      flat(id: 'bb-5rm', price: 6400, rooms: 5, sizeM2: 118, city: 'בני ברק',
          lat: 32.083, lon: 34.836, features: ['elevator', 'mamad', 'balcony']),
      flat(id: 'bb-3rm', price: 5200, rooms: 3, sizeM2: 72, city: 'בני ברק',
          lat: 32.085, lon: 34.84, features: ['mamad']),
      // ── Netanya — furnished / oleh stock ──────────────────────────────────────
      flat(id: 'net-furnished', price: 5400, rooms: 3, sizeM2: 78, city: 'נתניה',
          lat: 32.32, lon: 34.853, features: ['furnished', 'ac', 'elevator']),
      flat(id: 'net-bare', price: 5200, rooms: 3, sizeM2: 80, city: 'נתניה',
          lat: 32.31, lon: 34.86, features: ['ac']),
    ];

int rankOf(List<ScoredProperty> l, String id) =>
    l.indexWhere((s) => s.property.id == id);

void show(String persona, String query, List<ScoredProperty> recs) {
  // ignore: avoid_print
  print('\n══════════════════════════════════════════════');
  // ignore: avoid_print
  print('👤 $persona\n   🔎 "$query"');
  for (final s in recs.take(3)) {
    final p = s.property;
    final sc = s.scorecard!;
    final top = (List.of(sc.dimensions)
          ..sort((a, b) => b.weightPct.compareTo(a.weightPct)))
        .take(4)
        .map((d) => '${d.label} ${(d.contributionPct * 100).round()}%')
        .join(', ');
    // ignore: avoid_print
    print('   • ${p.id}: ${p.priceLabel}, ${p.rooms.toInt()}חד׳/${p.sizeM2}מ״ר '
        '(${(p.sizeM2 / p.rooms).round()}/חדר), ${p.city} · fit ${sc.fitPct}%');
    // ignore: avoid_print
    print('       $top');
    if (sc.concerns.isNotEmpty) {
      // ignore: avoid_print
      print('       ⚠ ${sc.concerns.join(" | ")}');
    }
  }
}

List<ScoredProperty> run(String q) => RecommendationEngine.recommendAsScored(
    candidates: catalogue(), query: SmartSearch.parse(q), limit: 8, seed: 11);

void main() {
  test('metro gate — תל אביב includes גוש דן, excludes far cities', () {
    final candidates = [
      flat(id: 'ta', price: 6500, rooms: 3, sizeM2: 82, city: 'תל אביב',
          lat: 32.07, lon: 34.78, features: ['ac', 'elevator']),
      flat(id: 'ramat-gan', price: 6500, rooms: 3, sizeM2: 82, city: 'רמת גן',
          lat: 32.083, lon: 34.814, features: ['ac', 'elevator']), // ~3.5 km, equal
      flat(id: 'givatayim', price: 6800, rooms: 3, sizeM2: 80, city: 'גבעתיים',
          lat: 32.072, lon: 34.81, features: ['ac']), // ~2.8 km
      flat(id: 'netanya', price: 5200, rooms: 3, sizeM2: 85, city: 'נתניה',
          lat: 32.32, lon: 34.85, features: ['ac']), // ~28 km
      flat(id: 'beer-sheva', price: 3200, rooms: 3, sizeM2: 90, city: 'באר שבע',
          lat: 31.25, lon: 34.79, features: ['ac']), // ~91 km
    ];
    final recs = RecommendationEngine.recommendAsScored(
        candidates: candidates,
        query: SmartSearch.parse('דירה בתל אביב עד 8000'),
        limit: 8,
        seed: 12);
    final ids = recs.map((s) => s.property.id).toSet();
    expect(ids.containsAll({'ta', 'ramat-gan', 'givatayim'}), true,
        reason: 'the גוש דן metro (RG/Givatayim) must be included');
    expect(ids.contains('netanya') || ids.contains('beer-sheva'), false,
        reason: 'cities outside the metro (~28/91 km) must be excluded');
    // The exact-named city still leads (soft city penalty keeps it first).
    expect(recs.first.property.id == 'ta', true,
        reason: 'the exact city should rank first within the metro');
  });


  test('שותפים — 2 סטודנטים ליד TAU, מרווחת', () {
    const q = 'דירת שותפים 3 חדרים מרווחת ליד האוניברסיטה בתל אביב עד 6500';
    final recs = run(q);
    show('עומר+תומר · שותפים · TAU · מרווחת · ₪6500', q, recs);
    expect(recs.isNotEmpty, true);
    // Roomy-near-campus should beat cramped-near-campus.
    expect(rankOf(recs, 'tau-roomy') < rankOf(recs, 'tau-cramped'), true,
        reason: 'roommates want the roomier flat by the campus');
  });

  test('עובדת מהבית — חדר עבודה, מרווח, פתח תקווה', () {
    const q = 'דירה מרווחת עם חדר עבודה בפתח תקווה עד 6000, עובדת מהבית';
    final recs = run(q);
    show('מיכל · WFH · פתח תקווה · מרווח · ₪6000', q, recs);
    expect(recs.isNotEmpty, true);
    expect(rankOf(recs, 'pt-spacious') < rankOf(recs, 'pt-small'), true,
        reason: 'WFH needs the spacious flat with room for an office');
  });

  test('כיסא גלגלים — נגישות מלאה, חיפה', () {
    const q = 'דירה נגישה לכיסא גלגלים בחיפה עם מעלית עד 5000';
    final recs = run(q);
    show('יעקב · כיסא גלגלים · חיפה · נגישות · ₪5000', q, recs);
    expect(recs.isNotEmpty, true);
    // Elevator OR ground floor must beat the 4th-floor walk-up.
    expect(recs.first.property.id != 'hf-walkup', true,
        reason: 'a 4th-floor walk-up must not lead for a wheelchair user');
    expect(
        rankOf(recs, 'hf-elevator') < rankOf(recs, 'hf-walkup') &&
            rankOf(recs, 'hf-ground') < rankOf(recs, 'hf-walkup'),
        true,
        reason: 'elevator + ground floor both outrank the walk-up');
  });

  test('משפחה גדולה — 5 חדרים, בני ברק', () {
    const q = 'דירת 5 חדרים גדולה בבני ברק למשפחה עד 6500';
    final recs = run(q);
    show('הרב כהן · משפחה גדולה · בני ברק · 5 חד׳ · ₪6500', q, recs);
    expect(recs.isNotEmpty, true);
    expect(recs.first.property.id == 'bb-5rm', true,
        reason: 'a 5-room family search should lead with the 5-room flat');
  });

  test('עולה חדש — מרוהטת, נתניה', () {
    const q = 'דירה מרוהטת מרכזית בנתניה עד 5500';
    final recs = run(q);
    show('אלכס · עולה · נתניה · מרוהטת · ₪5500', q, recs);
    expect(recs.isNotEmpty, true);
    expect(rankOf(recs, 'net-furnished') < rankOf(recs, 'net-bare'), true,
        reason: 'a furnished search should prefer the furnished flat');
  });
}
