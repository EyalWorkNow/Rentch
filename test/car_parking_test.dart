import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('explicit car ownership → parking is a hard requirement', () {
    test('"יש לי רכב" requires parking', () {
      final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עד 6000, יש לי רכב');
      expect(q.requiredFeatures, contains('parking'));
    });
    test('"יש לי אוטו" / "מכונית" also require parking', () {
      expect(SmartSearch.parse('יש לי אוטו').requiredFeatures, contains('parking'));
      expect(SmartSearch.parse('יש לי מכונית פרטית').requiredFeatures, contains('parking'));
    });
    test('"אין לי רכב" does NOT require parking (negative wins)', () {
      final q = SmartSearch.parse('אין לי רכב, קרוב לתחבורה ציבורית');
      expect(q.requiredFeatures, isNot(contains('parking')));
    });
    test('no car mention → no forced parking', () {
      final q = SmartSearch.parse('דירת 2 חדרים ברמת גן עד 5000');
      expect(q.requiredFeatures, isNot(contains('parking')));
    });
  });
}
