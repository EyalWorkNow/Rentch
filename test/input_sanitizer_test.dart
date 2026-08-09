import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitizeText does not throw when control chars shrink the string', () {
    // Regression: the end index for substring() was computed from the
    // ORIGINAL string's trimmed length instead of the cleaned string's own
    // length, so stripping a control char made the cleaned string shorter
    // than the computed index — a RangeError on ordinary pasted text.
    final input = 'Tel Aviv\x0bStreet 12';
    expect(() => InputSanitizer.sanitizeText(input), returnsNormally);
    expect(InputSanitizer.sanitizeText(input), 'Tel AvivStreet 12');
  });

  test('sanitizeText still enforces maxLength', () {
    final input = 'a' * 600;
    expect(InputSanitizer.sanitizeText(input, maxLength: 500).length, 500);
  });
}
