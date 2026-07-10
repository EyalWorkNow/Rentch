import 'package:dating_app/core/services/assistant_service.dart';
import 'package:flutter_test/flutter_test.dart';

// The streamed-voice split: first chunk must be a whole short sentence (fast
// first word), and runt fragments must never stand alone (no wasted round-trip).
void main() {
  test('splits on sentence enders; first chunk is a whole short sentence', () {
    final s = splitForSpeech('מצאתי דירה מהממת בתל אביב. היא ממש קרובה לים. רוצה לראות?');
    // First long sentence stands alone (fast first word); the short trailing
    // "רוצה לראות?" (< 14) glues onto the sentence before it → 2 clips, not 3.
    expect(s.length, 2);
    expect(s.first, 'מצאתי דירה מהממת בתל אביב.');
  });

  test('glues a runt fragment onto its neighbour', () {
    // "כן!" is < 14 chars → must merge, not become its own clip.
    final s = splitForSpeech('כן! מצאתי לך שלוש דירות מעולות באזור שאהבת.');
    expect(s.length, 1);
    expect(s.first.startsWith('כן!'), isTrue);
  });

  test('single sentence stays one chunk', () {
    expect(splitForSpeech('ספר לי עוד קצת על מה שאתה מחפש').length, 1);
  });

  test('never emits empty chunks', () {
    final s = splitForSpeech('שלום...\n\n  מה נשמע?  ');
    expect(s.any((c) => c.trim().isEmpty), isFalse);
  });
}
