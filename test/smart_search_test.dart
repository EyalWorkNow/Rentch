import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the natural-language example', () {
    final q = SmartSearch.parse(
      'אני מחפש דירה באזור של הרכבת, משופצת עם 3 חדרים לזוג עם כלבה בלי ילדים',
    );
    expect(q.nearTrain, true);
    expect(q.minRooms, 3);
    expect(q.amenities.contains('feat_renovated'), true);
    expect(q.amenities.contains('feat_pets'), true);
    expect(q.isEmpty, false);
  });

  test('parses city and budget', () {
    final q = SmartSearch.parse('דירת 4 חדרים בתל אביב עד 7500 שקל, עם מרפסת וחניה');
    expect(q.city, 'תל אביב');
    expect(q.minRooms, 4);
    expect(q.maxPrice, 7500);
    expect(q.amenities.contains('feat_balcony'), true);
    expect(q.amenities.contains('feat_parking'), true);
  });

  test('empty when nothing concrete', () {
    expect(SmartSearch.parse('שלום מה נשמע').isEmpty, true);
  });
}
