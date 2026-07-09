import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:flutter_test/flutter_test.dart';

// 10 diverse persona use-cases. For each we assert that the RELEVANT nearby
// sections appear, the IRRELEVANT ones do NOT, the HMO filter is applied, and
// the ordering puts the most-relevant first. This is the "only what's relevant
// to you" contract the product requires.
void main() {
  Set<NearbyKind> kinds(String q) =>
      relevantNearbySections(NearbyProfile.fromText(q)).map((s) => s.kind).toSet();

  List<NearbySection> secs(String q) =>
      relevantNearbySections(NearbyProfile.fromText(q));

  test('UC1 family + toddler → kindergartens (+parks), NOT schools-primary/clinics', () {
    final k = kinds('משפחה עם פעוט, מחפשים קרוב לגן ילדים');
    expect(k, contains(NearbyKind.kindergartens));
    expect(k, contains(NearbyKind.parks)); // family → parks
    expect(k, isNot(contains(NearbyKind.clinics)));
    expect(k, isNot(contains(NearbyKind.supermarkets)));
    expect(secs('משפחה עם פעוט קרוב לגן').first.kind, NearbyKind.kindergartens);
  });

  test('UC2 family with teens → schools (high priority), NOT kindergartens', () {
    final k = kinds('משפחה עם ילדים בתיכון');
    expect(k, contains(NearbyKind.schools));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
    expect(secs('משפחה עם ילדים בתיכון').first.kind, NearbyKind.schools);
  });

  test('UC3 elementary-age child → schools, NOT kindergartens', () {
    final k = kinds('יש לנו ילד בבית ספר יסודי');
    expect(k, contains(NearbyKind.schools));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
  });

  test('UC4 health + specific HMO (מכבי) → clinics filtered to מכבי, no schools', () {
    final s = secs('חשוב לנו להיות קרוב לקופת חולים מכבי');
    final clinic = s.firstWhere((x) => x.kind == NearbyKind.clinics);
    expect(clinic.hmo, 'מכבי');
    final k = s.map((x) => x.kind).toSet();
    expect(k, isNot(contains(NearbyKind.schools)));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
  });

  test('UC5 generic health need → clinics (all HMOs, no filter)', () {
    final s = secs('קרוב לשירותי בריאות ומרפאה');
    final clinic = s.firstWhere((x) => x.kind == NearbyKind.clinics);
    expect(clinic.hmo, isEmpty); // no specific HMO → all
  });

  test('UC6 young single / nightlife → NOTHING relevant (card hides)', () {
    final k = kinds('רווק, חיי לילה, ברים ומסעדות, מרכז תל אביב');
    expect(k, isEmpty);
  });

  test('UC7 groceries/errands → supermarkets, NOT family sections', () {
    final k = kinds('חשוב שיהיה סופר וקניות קרוב');
    expect(k, contains(NearbyKind.supermarkets));
    expect(k, isNot(contains(NearbyKind.schools)));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
  });

  test('UC8 elderly + quiet + health → clinics, NOT schools/kindergartens', () {
    final k = kinds('זוג מבוגר, שקט, קרוב לרפואה');
    expect(k, contains(NearbyKind.clinics));
    expect(k, isNot(contains(NearbyKind.schools)));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
  });

  test('UC9 family that loves parks/nature → parks + family school section', () {
    final k = kinds('משפחה שאוהבת פארקים וטבע ושטחים ירוקים');
    expect(k, contains(NearbyKind.parks));
    // family (no age) → schools at family priority
    expect(k, contains(NearbyKind.schools));
    // parks should be prioritised (explicit green wish) over the family school.
    final s = secs('משפחה שאוהבת פארקים וטבע');
    expect(s.first.kind, NearbyKind.parks);
  });

  // ── regression cases found via persona diagnostics ────────────────────────
  test('R1 "דתית לאומית" is the religious stream, NOT the Leumit HMO', () {
    final p = NearbyProfile.fromText('משפחה דתית לאומית עם ילדים');
    expect(p.hmo, isEmpty);
    expect(p.health, isFalse);
    expect(kinds('משפחה דתית לאומית עם ילדים'),
        isNot(contains(NearbyKind.clinics)));
  });

  test('R2 "בלי ילדים" negation → not a family, no school sections', () {
    final k = kinds('זוג צעיר בלי ילדים, קרוב לחיי לילה');
    expect(k, isEmpty);
    expect(kinds('רווקה בלי ילדים קרוב לסופר'), {NearbyKind.supermarkets});
  });

  test('R3 "רופא ילדים" (pediatrician) counts as a health signal', () {
    expect(NearbyProfile.fromText('קרוב לרופא ילדים').health, isTrue);
    expect(kinds('משפחה קרוב לרופא ילדים'), contains(NearbyKind.clinics));
  });

  test('R4 "מכבי" as a sports club is NOT the HMO', () {
    expect(NearbyProfile.fromText('אוהד מכבי תל אביב בכדורגל').hmo, isEmpty);
  });

  test('R5 legit "קופת חולים לאומית" still resolves to Leumit', () {
    final s = secs('קרוב לקופת חולים לאומית');
    expect(s.firstWhere((x) => x.kind == NearbyKind.clinics).hmo, 'לאומית');
  });

  test('R6 supermarket chain names (שופרסל/רמי לוי/…) → groceries', () {
    for (final q in [
      'קרוב לשופרסל',
      'ליד רמי לוי',
      'קרוב ליינות ביתן ולאושר עד'
    ]) {
      expect(kinds(q), contains(NearbyKind.supermarkets), reason: q);
    }
  });

  test('R7 plural "גני ילדים" and "גן חובה" → kindergartens (youngChild)', () {
    expect(NearbyProfile.fromText('קרוב לגני ילדים').youngChild, isTrue);
    expect(NearbyProfile.fromText('ילד בגן חובה').youngChild, isTrue);
    expect(kinds('קרוב לגני ילדים'), contains(NearbyKind.kindergartens));
  });

  test('UC10 multi-signal: school kids + סופר + כללית → schools + supermarket + clinics(כללית)', () {
    final s = secs('משפחה עם ילדים בבית ספר, קרוב לסופר ולקופת חולים כללית');
    final k = s.map((x) => x.kind).toSet();
    expect(k, containsAll([
      NearbyKind.schools,
      NearbyKind.supermarkets,
      NearbyKind.clinics,
    ]));
    expect(s.firstWhere((x) => x.kind == NearbyKind.clinics).hmo, 'כללית');
    // sorted by priority descending
    for (var i = 1; i < s.length; i++) {
      expect(s[i].priority, lessThanOrEqualTo(s[i - 1].priority));
    }
  });
}
