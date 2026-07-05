import 'package:flutter_test/flutter_test.dart';
// Mirrors _affirmative in search_chat_screen — guards the Hebrew \b bug.
final _affirmative = RegExp(
    r'\s(?:כן|בטח|בהחלט|יאללה|יאלה|קדימה|סבבה|אוקיי|אוקי|בסדר|נכון|וודאי|בטוח|בבקשה|נו)\s'
    r'|נשמע טוב|למה לא|תראי לי|תראה לי|בוא נראה|בואי נראה|קדימה נראה'
    r'|yes|okay|\bok\b|sure|go ahead',
    caseSensitive: false);
bool isAff(String t) => _affirmative.hasMatch(' ${t.trim()} ');
void main() {
  test('affirmatives match', () {
    for (final y in ['כן', 'כן בבקשה', 'בטח', 'יאללה', 'קדימה', 'אוקיי', 'תראה לי', 'בוא נראה', 'yes', 'ok']) {
      expect(isAff(y), true, reason: '"$y" should be affirmative');
    }
  });
  test('non-affirmatives do NOT match', () {
    for (final n in ['לא', 'תוכן', 'לכן', 'מסוכן', 'אולי', 'עוד משהו', 'שלושה חדרים']) {
      expect(isAff(n), false, reason: '"$n" must NOT be affirmative');
    }
  });
}
