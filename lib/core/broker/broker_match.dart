import 'package:dating_app/data/models/broker_client.dart';
import 'package:dating_app/data/models/rental_models.dart';

/// One listing scored against one [BrokerClient] requirement.
class BrokerMatch {
  const BrokerMatch({
    required this.property,
    required this.score,
    required this.reasons,
  });

  final RentalProperty property;

  /// 0–100. Higher = better fit. Only [fits] matches are surfaced.
  final int score;

  /// Short Hebrew reasons (e.g. "בתוך התקציב", "מעלית ✓"), best-first.
  final List<String> reasons;

  bool get fits => score > 0;
}

/// Pure, deterministic broker matcher: does the agent's listing satisfy what a
/// client is looking for?
///
/// Why not [MatchEngine]? That engine models a *two-sided tenant↔landlord*
/// profile match (lifestyle tags, deal-breakers, mutual interest). A broker's
/// check is one-sided and hard-edged — budget range, area, rooms, must-have
/// features — so a small deterministic scorer reads clearer and is trivially
/// testable. The hard criteria act as gates (miss any → score 0 → not shown);
/// the score then just ranks the listings that already qualify.
class BrokerMatcher {
  const BrokerMatcher();

  /// All of [properties] that satisfy [client]'s hard criteria, ranked best
  /// first. Non-matching listings are dropped entirely.
  List<BrokerMatch> rank(
    BrokerClient client,
    Iterable<RentalProperty> properties,
  ) {
    final out = <BrokerMatch>[];
    for (final p in properties) {
      final m = score(client, p);
      if (m.fits) out.add(m);
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// How many of [properties] fit [client] — for the "X נכסים מתאימים" badge.
  int countFits(BrokerClient client, Iterable<RentalProperty> properties) {
    var n = 0;
    for (final p in properties) {
      if (score(client, p).fits) n++;
    }
    return n;
  }

  /// Scores one property against one client. Hard criteria gate to a 0 (no
  /// match); when all pass, the soft signals (budget headroom, area, fresh
  /// listing) build the rank score.
  BrokerMatch score(BrokerClient client, RentalProperty property) {
    final reasons = <String>[];

    // ── Gate: transaction type (rent vs sale) ──────────────────────────────
    if (property.transactionType.name != client.transactionType) {
      return BrokerMatch(property: property, score: 0, reasons: reasons);
    }

    // ── Gate: budget within [min, max] ─────────────────────────────────────
    final price = property.price;
    if (client.budgetMin != null && price > 0 && price < client.budgetMin!) {
      return BrokerMatch(property: property, score: 0, reasons: reasons);
    }
    if (client.budgetMax != null && price > 0 && price > client.budgetMax!) {
      return BrokerMatch(property: property, score: 0, reasons: reasons);
    }

    // ── Gate: area (city or neighborhood) ──────────────────────────────────
    if (client.areas.isNotEmpty) {
      final hay = '${property.city} ${property.neighborhood}'.toLowerCase();
      final areaHit = client.areas.any((a) {
        final needle = a.trim().toLowerCase();
        return needle.isNotEmpty && hay.contains(needle);
      });
      if (!areaHit) {
        return BrokerMatch(property: property, score: 0, reasons: reasons);
      }
      reasons.add('באזור המבוקש');
    }

    // ── Gate: rooms >= minRooms ────────────────────────────────────────────
    if (client.minRooms != null && property.rooms < client.minRooms!) {
      return BrokerMatch(property: property, score: 0, reasons: reasons);
    }

    // ── Gate: must-have features all present ───────────────────────────────
    if (client.mustHaves.isNotEmpty) {
      final haystack = property.searchableText; // already lower-cased
      for (final tag in client.mustHaves) {
        final needle = tag.trim().toLowerCase();
        if (needle.isEmpty) continue;
        if (!haystack.contains(needle)) {
          return BrokerMatch(property: property, score: 0, reasons: reasons);
        }
        reasons.add('$tag ✓');
      }
    }

    // ── All gates passed → build a rank score (50 baseline). ───────────────
    var s = 50;

    // Budget headroom: the deeper inside the client's budget, the better the
    // deal. Reward up to +25 when the price sits in the lower half of the band.
    if (client.budgetMax != null && client.budgetMax! > 0 && price > 0) {
      final lower = (client.budgetMin ?? 0).toDouble();
      final span = client.budgetMax! - lower;
      if (span > 0) {
        final frac = ((price - lower) / span).clamp(0.0, 1.0);
        s += ((1 - frac) * 25).round();
        if (frac <= 0.5) reasons.add('בתוך התקציב, מחיר נוח');
      } else {
        reasons.add('בתוך התקציב');
      }
    }

    // Rooms comfortably above the minimum is a small plus.
    if (client.minRooms != null && property.rooms >= client.minRooms! + 1) {
      s += 5;
    }

    // Verified + fresh listings rank a touch higher (easier to close).
    if (property.isVerifiedListing) {
      s += 8;
      reasons.add('מודעה מאומתת');
    }
    if (property.isNewListing) {
      s += 7;
      reasons.add('עלה לאחרונה');
    }

    return BrokerMatch(
      property: property,
      score: s.clamp(1, 100),
      reasons: reasons,
    );
  }
}

/// Builds a [RentalProperty] for the self-check below without needing real data.
RentalProperty _p({
  required String id,
  required int price,
  required double rooms,
  String city = 'תל אביב',
  String neighborhood = '',
  String transaction = 'rent',
  List<String> features = const [],
}) {
  return RentalProperty(
    id: id,
    price: price,
    rooms: rooms,
    sizeM2: 80,
    floor: '2',
    totalFloors: '5',
    city: city,
    neighborhood: neighborhood,
    street: 'דיזנגוף',
    streetNumber: 10,
    lat: 32.07,
    lon: 34.78,
    propertyType: 'דירה',
    entryDate: '',
    condition: 'משופצת',
    ownerName: 'בעלים',
    agencyListing: false,
    features: features,
    media: const [],
    transactionType: transaction == 'sale'
        ? PropertyTransactionType.sale
        : PropertyTransactionType.rent,
  );
}

/// Deterministic assert-based self-check. Run with:
///   dart run lib/core/broker/broker_match.dart
void main() {
  const matcher = BrokerMatcher();

  final client = BrokerClient(
    id: 'c1',
    name: 'משפחת כהן',
    transactionType: 'rent',
    budgetMin: 4000,
    budgetMax: 7000,
    areas: const ['תל אביב'],
    minRooms: 3,
    mustHaves: const ['מעלית'],
  );

  final inBudgetWithElevator =
      _p(id: 'a', price: 5000, rooms: 4, features: const ['מעלית', 'חניה']);
  final overBudget = _p(id: 'b', price: 9000, rooms: 4, features: const ['מעלית']);
  final wrongCity = _p(
      id: 'c', price: 5000, rooms: 4, city: 'חיפה', features: const ['מעלית']);
  final tooFewRooms =
      _p(id: 'd', price: 5000, rooms: 2, features: const ['מעלית']);
  final noElevator = _p(id: 'e', price: 5000, rooms: 4, features: const ['חניה']);
  final saleNotRent = _p(
      id: 'f',
      price: 5000,
      rooms: 4,
      transaction: 'sale',
      features: const ['מעלית']);
  final cheaperInBudget =
      _p(id: 'g', price: 4200, rooms: 4, features: const ['מעלית', 'חניה']);

  final all = [
    inBudgetWithElevator,
    overBudget,
    wrongCity,
    tooFewRooms,
    noElevator,
    saleNotRent,
    cheaperInBudget,
  ];

  // Only the two qualifying listings match.
  final ranked = matcher.rank(client, all);
  assert(ranked.length == 2, 'expected 2 matches, got ${ranked.length}');
  assert(matcher.countFits(client, all) == 2);

  // The cheaper in-budget listing should rank above the pricier one.
  assert(ranked.first.property.id == 'g',
      'expected cheaper listing first, got ${ranked.first.property.id}');

  // Each gate excludes correctly.
  assert(!matcher.score(client, overBudget).fits);
  assert(!matcher.score(client, wrongCity).fits);
  assert(!matcher.score(client, tooFewRooms).fits);
  assert(!matcher.score(client, noElevator).fits);
  assert(!matcher.score(client, saleNotRent).fits);

  // A match surfaces a human reason.
  assert(matcher.score(client, inBudgetWithElevator).reasons.isNotEmpty);

  // An open client (no criteria) matches everything of the right type.
  final openClient = BrokerClient(id: 'c2', name: 'פתוח');
  assert(matcher.countFits(openClient, all) == 6); // all rent listings

  // ignore: avoid_print
  print('broker_match self-check passed: ${ranked.length} matches, '
      'ranked ${ranked.map((m) => "${m.property.id}:${m.score}").join(", ")}');
}
