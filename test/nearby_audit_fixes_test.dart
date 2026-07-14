// Regression suite for the war-room audit of nearby_relevance.dart.
// Each group pins one fixed bug so it can never silently regress.
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:flutter_test/flutter_test.dart';

NearbyProfile p(String s) => NearbyProfile.fromText(s);
Set<NearbyKind> kinds(String s) =>
    relevantNearbySections(p(s)).map((x) => x.kind).toSet();

void main() {
  // ── H1 · Dart \b is ASCII-only → broken next to Hebrew ──────────────────────
  group('H1 · Hebrew word boundaries', () {
    test('car owner phrased in pure Hebrew is detected', () {
      expect(p('יש לי רכב').car, isTrue); // was false (רכב\b)
      expect(p('יש לי אוטו').car, isTrue);
    });
    test('standalone Hebrew tokens at an edge match', () {
      expect(p('מחפש מקום זול').budget, isTrue); // זול at end
      expect(p('דירה יקר מדי').luxury, isTrue); // יקר
      expect(p('הרבה ירוק מסביב').green, isTrue); // ירוק
      expect(p('יש בר טוב קרוב').nightlife, isTrue); // \bבר\b
      expect(p('קרוב לסופר').groceries, isTrue); // סופר at edge
    });
    test('boundary still prevents matching inside a longer word', () {
      // בר must NOT fire inside בריא/מברוק etc.
      expect(p('אזור בריא ונקי').nightlife, isFalse);
      // רכב must NOT fire inside מרכבה/הרכבה
      expect(p('שיעור הרכבה של רהיטים').car, isFalse);
    });
  });

  // ── H2 · definite article ה breaks two-word phrases ─────────────────────────
  group('H2 · definite article between words', () {
    test('young area with ה prefix', () {
      expect(p('דירה באזור הצעיר').young, isTrue); // was false
      expect(p('אזור צעיר').young, isTrue); // still works
    });
    test('transit with ה prefix', () {
      expect(p('ליד הרכבת הקלה').transitWanted, isTrue); // was false
      expect(p('רכבת קלה').transitWanted, isTrue);
    });
    test('school / hospital / synagogue / café / gym with ה', () {
      expect(p('ליד בית הספר').schoolChild, isTrue);
      expect(p('קרוב לבית החולים').health, isTrue);
      expect(p('דתי, ליד בית הכנסת').observant, isTrue);
      expect(p('אוהב חיי הלילה').nightlife, isTrue);
      expect(p('חשוב לי חדר הכושר').active, isTrue);
    });
  });

  // ── H3 · transitWanted must not nuke an explicit parking request ────────────
  group('H3 · car vs transit', () {
    test('transit + explicit parking → both honored', () {
      final q = p('דירה עם תחבורה ציבורית וגם חנייה');
      expect(q.transitWanted, isTrue);
      expect(q.car, isTrue); // was false
      expect(kinds('דירה עם תחבורה ציבורית וגם חנייה'),
          containsAll({NearbyKind.transit, NearbyKind.parking}));
    });
    test('genuinely car-free still suppresses parking', () {
      final q = p('אין לי רכב, קרוב לרכבת');
      expect(q.car, isFalse);
      expect(kinds('אין לי רכב, קרוב לרכבת'), isNot(contains(NearbyKind.parking)));
    });
  });

  // ── M1 · spelling variant איזור ─────────────────────────────────────────────
  test('M1 · "איזור צעיר" (yud spelling) sets young', () {
    expect(p('מחפש דירה באיזור צעיר').young, isTrue); // was false
    expect(p('אזור צעיר').young, isTrue);
  });

  // ── M2 · orderedNearbySections respects hard suppression ────────────────────
  test('M2 · a secular seeker never sees synagogues, even in browse-all', () {
    final all = orderedNearbySections(p('חילוני, מחפש דירה'))
        .map((s) => s.kind)
        .toSet();
    expect(all, isNot(contains(NearbyKind.synagogues)));
    expect(all, isNot(contains(NearbyKind.worship)));
  });

  // ── M3 · quiet / secular count as signals ───────────────────────────────────
  test('M3 · a quiet-only / secular-only query has anySignal=true', () {
    expect(p('דירה שקטה').anySignal, isTrue); // was false → stale-profile leak
    expect(p('חילוני').anySignal, isTrue);
  });

  // ── L1 · deterministic ordering on priority ties ────────────────────────────
  test('L1 · equal-priority sections order deterministically', () {
    const q = 'משפחה עם ילד וגם זוג'; // dining(48) & culture(48) tie
    final a =
        relevantNearbySections(p(q)).map((s) => '${s.kind.index}:${s.priority}');
    final b =
        relevantNearbySections(p(q)).map((s) => '${s.kind.index}:${s.priority}');
    expect(a, b);
    // among equal priority, lower enum index comes first
    final ties = relevantNearbySections(p(q)).where((s) => s.priority == 48).toList();
    for (var i = 1; i < ties.length; i++) {
      expect(ties[i - 1].kind.index, lessThan(ties[i].kind.index));
    }
  });

  // ── L2 · dog-parks for dog owners only, not cat owners ──────────────────────
  test('L2 · cat owner gets a vet but NOT a dog park', () {
    expect(kinds('יש לי חתול'), contains(NearbyKind.vets));
    expect(kinds('יש לי חתול'), isNot(contains(NearbyKind.dogParks)));
    expect(kinds('יש לי כלב'), containsAll({NearbyKind.vets, NearbyKind.dogParks}));
  });

  // ── L4 · no signal fires on neutral / empty text (guards empty-match) ───────
  test('L4 · empty & neutral text produce NO signals', () {
    for (final junk in ['', '   ', 'zzz 999 ...', '.....', '12345']) {
      final q = p(junk);
      expect(q.anySignal, isFalse, reason: 'input="$junk"');
      expect(q.family, isFalse);
      expect(q.schoolChild, isFalse);
      expect(q.young, isFalse);
      expect(relevantNearbySections(q), isEmpty);
    }
  });

  // ── Guard · the childless-couple case that started it all ───────────────────
  test('childless couple → lifestyle, never schools/kindergartens', () {
    final k = kinds('זוג צעיר בלי ילדים בתל אביב');
    expect(k, isNot(contains(NearbyKind.schools)));
    expect(k, isNot(contains(NearbyKind.kindergartens)));
    expect(k, contains(NearbyKind.dining));
  });
}
