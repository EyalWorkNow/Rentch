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

  test('couple WITH a child → education leads, NOT restaurants (the reported bug)',
      () {
    final list = secs('דירה לזוג בהרצליה עם ילד ותקציב');
    final kindList = list.map((s) => s.kind).toList();
    int rank(NearbyKind k) => kindList.indexOf(k);
    // Education/kids sections must be present and lead the list.
    expect(kindList.first,
        anyOf(NearbyKind.schools, NearbyKind.kindergartens, NearbyKind.playgrounds),
        reason: 'a family-couple must see education first, not dining');
    // If dining appears at all, it sits BELOW schools & kindergartens.
    if (kindList.contains(NearbyKind.dining)) {
      expect(rank(NearbyKind.dining), greaterThan(rank(NearbyKind.schools)));
      if (kindList.contains(NearbyKind.kindergartens)) {
        expect(rank(NearbyKind.dining),
            greaterThan(rank(NearbyKind.kindergartens)));
      }
    }
  });

  test('elderly couple → HEALTH leads, not restaurants', () {
    final list = secs('זוג מבוגר מחפש דירה שקטה');
    final kinds = list.map((s) => s.kind).toList();
    expect(kinds.first, NearbyKind.clinics,
        reason: 'a senior couple must see clinics/health first, not dining');
    if (kinds.contains(NearbyKind.dining)) {
      expect(kinds.indexOf(NearbyKind.dining),
          greaterThan(kinds.indexOf(NearbyKind.clinics)));
    }
  });

  test('UC1 family + toddler → kindergartens + playgrounds + clinics + parks', () {
    final k = kinds('משפחה עם פעוט, מחפשים קרוב לגן ילדים');
    expect(k, contains(NearbyKind.kindergartens));
    expect(k, contains(NearbyKind.playgrounds)); // young child → playgrounds
    expect(k, contains(NearbyKind.parks)); // family → parks
    expect(k, contains(NearbyKind.clinics)); // family → clinics (important!)
    expect(k, contains(NearbyKind.supermarkets)); // families need groceries too
    // A non-religious family is NOT shown synagogues (a hard suppression rule).
    expect(k, isNot(contains(NearbyKind.synagogues)));
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

  test('UC6 young single / nightlife → lifestyle layers (nightlife/dining/gyms)', () {
    final k = kinds('רווק, חיי לילה, ברים ומסעדות, מרכז תל אביב');
    expect(k, contains(NearbyKind.nightlife));
    expect(k, contains(NearbyKind.dining));
    expect(k, contains(NearbyKind.gyms));
    // no family/health signal → no schools/kindergartens/clinics
    expect(k, isNot(contains(NearbyKind.schools)));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
    expect(k, isNot(contains(NearbyKind.clinics)));
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
    // Clinics still show (it's a family) but with NO HMO filter — the point is
    // that "דתית לאומית" must NOT be mis-read as the Leumit fund.
    final s = secs('משפחה דתית לאומית עם ילדים');
    final clinic = s.where((x) => x.kind == NearbyKind.clinics);
    if (clinic.isNotEmpty) expect(clinic.first.hmo, isEmpty);
  });

  test('R2 "בלי ילדים" negation → no school/kindergarten sections', () {
    // A childless couple into nightlife → lifestyle layers, never schools.
    final k = kinds('זוג צעיר בלי ילדים, קרוב לחיי לילה');
    expect(k, isNot(contains(NearbyKind.schools)));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
    expect(k, isNot(contains(NearbyKind.playgrounds)));
    expect(k, contains(NearbyKind.nightlife));
    // A single wanting a supermarket → groceries + single lifestyle, no schools.
    final s = kinds('רווקה בלי ילדים קרוב לסופר');
    expect(s, contains(NearbyKind.supermarkets));
    expect(s, isNot(contains(NearbyKind.schools)));
    expect(s, isNot(contains(NearbyKind.kindergartens)));
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

  test('orderedNearbySections shows ALL 5 kinds (detail screen), relevant first', () {
    // Even a no-signal profile → all kinds present (full reference on detail).
    final all = orderedNearbySections(NearbyProfile.fromText('3 חדרים'));
    expect(all.map((s) => s.kind).toSet(), NearbyKind.values.toSet());
    // A family+health persona → its relevant kinds lead the list.
    final fam = orderedNearbySections(
        NearbyProfile.fromText('משפחה עם ילדים, קרוב לכללית'));
    expect(fam.first.priority, greaterThan(0)); // a relevant kind is first
    expect(fam.map((s) => s.kind).toSet(), NearbyKind.values.toSet());
  });

  test('R7 plural "גני ילדים" and "גן חובה" → kindergartens (youngChild)', () {
    expect(NearbyProfile.fromText('קרוב לגני ילדים').youngChild, isTrue);
    expect(NearbyProfile.fromText('ילד בגן חובה').youngChild, isTrue);
    expect(kinds('קרוב לגני ילדים'), contains(NearbyKind.kindergartens));
  });

  // ── lifestyle personas (the three under-served groups) ────────────────────
  test('P1 couple → dining + gyms + parks, NOT nightlife (not pushed on couples)', () {
    final k = kinds('זוג צעיר מחפש דירה בזוגיות');
    expect(k, contains(NearbyKind.dining));
    expect(k, contains(NearbyKind.gyms));
    expect(k, contains(NearbyKind.parks));
    expect(k, isNot(contains(NearbyKind.nightlife)));
    expect(k, isNot(contains(NearbyKind.schools)));
  });

  test('P2 roommates/friends → nightlife + dining + gyms + supermarket', () {
    final k = kinds('שלושה שותפים מחפשים דירה יחד');
    expect(k, contains(NearbyKind.nightlife));
    expect(k, contains(NearbyKind.dining));
    expect(k, contains(NearbyKind.gyms));
    expect(k, contains(NearbyKind.supermarkets));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
  });

  test('P3 explicit gym/fitness → gyms leads', () {
    final s = secs('חשוב חדר כושר קרוב לבית');
    expect(s.first.kind, NearbyKind.gyms);
  });

  test('P4 explicit pharmacy → pharmacies section', () {
    expect(NearbyProfile.fromText('קרוב לבית מרקחת').pharmacy, isTrue);
    expect(kinds('קרוב לבית מרקחת'), contains(NearbyKind.pharmacies));
  });

  test('P5 family gets clinics AND pharmacies AND playgrounds', () {
    final k = kinds('משפחה עם שני ילדים');
    expect(k, containsAll([
      NearbyKind.clinics,
      NearbyKind.pharmacies,
      NearbyKind.playgrounds,
    ]));
  });

  test('P6 "שותפים" beats bare "צעיר" → roommates, not single-only', () {
    final p = NearbyProfile.fromText('שני שותפים צעירים');
    expect(p.roommates, isTrue);
    expect(p.single, isFalse); // couple/roommates suppress single
  });

  test('P7 observant seeker → synagogues; "דתי לאומי" ≠ Leumit HMO', () {
    final p = NearbyProfile.fromText('משפחה שומרת שבת קרוב לבית כנסת ומניין');
    expect(p.observant, isTrue);
    expect(kinds('קרוב לבית כנסת ומניין'), contains(NearbyKind.synagogues));
    // religious-national must register observant but NOT the Leumit fund.
    final rn = NearbyProfile.fromText('משפחה דתית לאומית');
    expect(rn.observant, isTrue);
    expect(rn.hmo, isEmpty);
  });

  test('P8 culture lover → culture section', () {
    expect(NearbyProfile.fromText('אוהבים מוזיאונים ותיאטרון').culture, isTrue);
    expect(kinds('קרוב למוזיאון ולתיאטרון'), contains(NearbyKind.culture));
  });

  test('P11 transit: explicit ask + young-leaning personas get the stops', () {
    expect(NearbyProfile.fromText('בלי רכב, קרוב לרכבת קלה').transitWanted, isTrue);
    expect(kinds('תחבורה ציבורית טובה קרוב לרכבת'),
        contains(NearbyKind.transit));
    expect(kinds('דירה בסביבה צעירה'), contains(NearbyKind.transit));
  });

  test('P12 hospitals show for health / senior / family', () {
    expect(kinds('זוג מבוגר קרוב לרפואה'), contains(NearbyKind.hospitals));
    expect(kinds('משפחה עם ילדים'), contains(NearbyKind.hospitals));
    // a young single with no health/family signal → no hospital section
    expect(kinds('רווק אוהב חיי לילה'), isNot(contains(NearbyKind.hospitals)));
  });

  test('P13 mosques/churches for a Muslim/Arab or Christian signal', () {
    expect(NearbyProfile.fromText('משפחה ערבית קרוב למסגד').muslim, isTrue);
    expect(kinds('משפחה ערבית קרוב למסגד'), contains(NearbyKind.worship));
    expect(kinds('קרוב לכנסייה נוצרית'), contains(NearbyKind.worship));
    // a plain Jewish-family search doesn't surface mosques/churches
    expect(kinds('משפחה עם ילדים'), isNot(contains(NearbyKind.worship)));
  });

  test('P10 young-area vibe → supermarkets + dining + parks, NOT schools', () {
    // The chat example: "דרום תל אביב, סביבה צעירה, עד 4000" → daily-life amenities.
    final p = NearbyProfile.fromText('דירה בדרום תל אביב בסביבה צעירה עד 4000');
    expect(p.young, isTrue);
    final k = kinds('דירה בדרום תל אביב בסביבה צעירה עד 4000');
    expect(k, containsAll(
        [NearbyKind.supermarkets, NearbyKind.dining, NearbyKind.parks]));
    expect(k, isNot(contains(NearbyKind.schools)));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
    expect(k, isNot(contains(NearbyKind.clinics)));
  });

  test('P9 non-religious family → culture + hospitals, but NOT synagogues', () {
    final k = kinds('משפחה עם שני ילדים');
    expect(k, contains(NearbyKind.culture));
    expect(k, contains(NearbyKind.hospitals));
    expect(k, isNot(contains(NearbyKind.synagogues))); // suppression rule
    // …unless the family says it's religious.
    expect(kinds('משפחה דתית עם ילדים'), contains(NearbyKind.synagogues));
  });

  test('P14 new signals: student / WFH / pet / accessible / car map correctly', () {
    expect(kinds('סטודנט קרוב לאוניברסיטה'), containsAll(
        [NearbyKind.transit, NearbyKind.coworking, NearbyKind.nightlife]));
    expect(kinds('עובד מהבית פרילנסר'), containsAll(
        [NearbyKind.coworking, NearbyKind.dining]));
    expect(kinds('יש לי כלב'),
        containsAll([NearbyKind.dogParks, NearbyKind.vets]));
    expect(kinds('נגיש לכיסא גלגלים'),
        containsAll([NearbyKind.clinics, NearbyKind.hospitals]));
    expect(kinds('דירה עם חניה לרכב'), contains(NearbyKind.parking));
    expect(kinds('ספורטיבי אוהב לשחות'), contains(NearbyKind.pools));
    // car-free must NOT trigger parking, and DOES trigger transit.
    expect(kinds('בלי רכב, תחבורה ציבורית'),
        contains(NearbyKind.transit));
    expect(kinds('בלי רכב, תחבורה ציבורית'),
        isNot(contains(NearbyKind.parking)));
  });

  test('P15 quiet suppresses nightlife even for a young single', () {
    final k = kinds('רווק צעיר שאוהב שקט ורוגע');
    expect(k, isNot(contains(NearbyKind.nightlife)));
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
