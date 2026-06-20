import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

// Guideline 1.2: the app must filter objectionable user-generated content.
// These tests prove the filter catches abuse without blocking ordinary
// Hebrew rental wording (the "Scunthorpe" false-positive trap).
void main() {
  group('InputSanitizer.containsObjectionableContent', () {
    test('flags clear Hebrew abuse', () {
      expect(InputSanitizer.containsObjectionableContent('אתה בן זונה'), isTrue);
      expect(InputSanitizer.containsObjectionableContent('שרמוטה'), isTrue);
      expect(InputSanitizer.containsObjectionableContent('תזדיין מפה'), isTrue);
    });

    test('flags clear English abuse, including simple evasion', () {
      expect(InputSanitizer.containsObjectionableContent('you fucking idiot'),
          isTrue);
      expect(
          InputSanitizer.containsObjectionableContent('f.u.c.k you'), isTrue);
      expect(InputSanitizer.containsObjectionableContent('I will killyou'),
          isTrue);
    });

    test('does NOT flag legitimate Hebrew rental text', () {
      const samples = [
        'דירת 3 חדרים משופצת ברחוב דיזנגוף, קומה 2, כניסה מיידית',
        'מגזין עיצוב הבית ממליץ על השכונה',
        'אנסה לתאם ביקור מחר בבוקר',
        'דירה מהממת עם מרפסת שמש ונוף לים',
        'תשלומים נוחים, חניה ומחסן',
      ];
      for (final s in samples) {
        expect(InputSanitizer.containsObjectionableContent(s), isFalse,
            reason: 'should not flag: $s');
      }
    });

    test('does NOT flag legitimate English words with embedded letters', () {
      const samples = ['grape juice', 'peacock feathers', 'spice rack', 'class'];
      for (final s in samples) {
        expect(InputSanitizer.containsObjectionableContent(s), isFalse,
            reason: 'should not flag: $s');
      }
    });

    test('empty input is clean', () {
      expect(InputSanitizer.containsObjectionableContent(''), isFalse);
      expect(InputSanitizer.containsObjectionableContent('   '), isFalse);
    });
  });
}
