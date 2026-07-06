import 'package:dating_app/core/search/search_intent.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase 2 — a single life-stage cue fills the whole bundle of priorities.
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

  test('neutral search infers no life-stage bundle', () {
    final n = SearchIntent.fromText('דירת 3 חדרים בתל אביב');
    expect(n.contains(SearchIntent.goodSchools), isFalse);
    expect(n.contains(SearchIntent.accessible), isFalse);
  });
}
