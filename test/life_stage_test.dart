import 'package:dating_app/core/search/search_intent.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase 2 + 5 — a single cue about who the seeker is fills the whole bundle of
// priorities a real agent would infer.
void main() {
  test('family cue → schools + quiet + spacious + quality area', () {
    final f = SearchIntent.fromText('משפחה עם שני ילדים ותינוק בדרך');
    expect(f.contains(SearchIntent.goodSchools), isTrue);
    expect(f.contains(SearchIntent.quiet), isTrue);
    expect(f.contains(SearchIntent.spacious), isTrue);
    expect(f.contains(SearchIntent.qualityArea), isTrue);
  });

  test('retiree cue → accessible + quiet', () {
    final s = SearchIntent.fromText('דירה לפנסיונר מבוגר');
    expect(s.contains(SearchIntent.accessible), isTrue);
    expect(s.contains(SearchIntent.quiet), isTrue);
  });

  test('olim/anglo cue → quality area + schools; no false positive on מעולה', () {
    final o = SearchIntent.fromText('עולה חדש דובר אנגלית מחפש דירה');
    expect(o.contains(SearchIntent.qualityArea), isTrue);
    expect(o.contains(SearchIntent.goodSchools), isTrue);
    final f = SearchIntent.fromText('דירה מעולה במרכז');
    expect(f.contains(SearchIntent.qualityArea), isFalse);
  });

  test('neutral search infers no life-stage bundle', () {
    final n = SearchIntent.fromText('דירת 3 חדרים בתל אביב');
    expect(n.contains(SearchIntent.goodSchools), isFalse);
    expect(n.contains(SearchIntent.accessible), isFalse);
  });
}
