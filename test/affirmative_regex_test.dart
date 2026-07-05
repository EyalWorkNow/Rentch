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

  // The awaiting-consent decision: show UNLESS negative or adds criteria.
  final negative = RegExp(
      r'\s(?:לא|רגע|חכה|חכי|המתן|עצור)\s|עוד לא|לא עדיין|not yet|\bwait\b',
      caseSensitive: false);
  final criteriaCue = RegExp(
      r'חדר|מרפסת|מעלית|ממ"?ד|חני|קומה|זול|יקר|גדול|קטן|מרוה|מרוו|נגיש|כלב|חתול|'
      r'קרוב|ליד|שקט|מרכז|תוסיף|תוסיפי|בנוסף|עוד|גם|באזור|בשכונ|בעיר|למכיר|להשקע|תקציב');
  bool holdsBack(String t) =>
      negative.hasMatch(' ${t.trim()} ') ||
      RegExp(r'\d').hasMatch(t) ||
      criteriaCue.hasMatch(t);

  test('consent: SHOW the apartments (do not hold back)', () {
    // The exact reply the user gave that was broken before ("תציג לי אותן").
    for (final y in ['תציג לי אותן', 'כן', 'בטח', 'תראה לי אותן', 'נו', 'בבקשה', 'אוקיי', 'קדימה']) {
      expect(holdsBack(y), false, reason: '"$y" should REVEAL the apartments');
    }
  });
  test('consent: HOLD BACK (refine / no)', () {
    for (final h in ['לא', 'רגע', 'תוסיף מרפסת', '4 חדרים', 'עוד חדר', 'משהו זול יותר']) {
      expect(holdsBack(h), true, reason: '"$h" should refine, not reveal');
    }
  });
}
