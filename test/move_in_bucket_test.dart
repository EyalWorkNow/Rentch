import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies moveInBucketOf() normalizes canonical tokens, legacy Hebrew strings,
// and ISO dates into the 4 locked buckets. Bucket tokens are a LOCKED contract
// with the backend gate: immediate | month | quarter | flexible.
void main() {
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('moveInBucketOf', () {
    test('passes canonical tokens through', () {
      expect(moveInBucketOf('immediate'), 'immediate');
      expect(moveInBucketOf('month'), 'month');
      expect(moveInBucketOf('quarter'), 'quarter');
      expect(moveInBucketOf('flexible'), 'flexible');
    });

    test('empty / unknown falls back to flexible', () {
      expect(moveInBucketOf(''), 'flexible');
      expect(moveInBucketOf('   '), 'flexible');
      expect(moveInBucketOf('שטויות'), 'flexible');
    });

    test('legacy profile_screen presets', () {
      expect(moveInBucketOf('מיידי'), 'immediate');
      expect(moveInBucketOf('בחודש הקרוב'), 'month');
      expect(moveInBucketOf('בעוד חודשיים'), 'quarter');
      expect(moveInBucketOf('גמיש'), 'flexible');
    });

    test('legacy edit_profile options', () {
      expect(moveInBucketOf('תוך חודש'), 'month');
      expect(moveInBucketOf('1-3 חודשים'), 'quarter');
      expect(moveInBucketOf('3-6 חודשים'), 'quarter');
    });

    test('legacy seed string', () {
      expect(moveInBucketOf('כניסה תוך 30 יום'), 'month');
    });

    test('ISO dates bucket by days from today', () {
      final now = DateTime.now();
      expect(moveInBucketOf(iso(now.add(const Duration(days: 5)))), 'immediate');
      expect(moveInBucketOf(iso(now.add(const Duration(days: 25)))), 'month');
      expect(moveInBucketOf(iso(now.add(const Duration(days: 60)))), 'quarter');
      expect(moveInBucketOf(iso(now.add(const Duration(days: 200)))), 'flexible');
    });
  });
}
