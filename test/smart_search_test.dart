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

  test('parses Hebrew "אלף" budgets and pet+city', () {
    final q = SmartSearch.parse(
      'דירה במקסימום 7 וחצי אלף שח במרכז תל אביב עם אפשרות להכניס כלב',
    );
    expect(q.maxPrice, 7500);
    expect(q.city, 'תל אביב');
    expect(q.amenities.contains('feat_pets'), true);
  });

  test('plain "7 אלף" → 7000', () {
    expect(SmartSearch.parse('עד 7 אלף בחיפה').maxPrice, 7000);
  });

  test('budget range "בין X ל-Y"', () {
    final q = SmartSearch.parse('דירה בין 5000 ל-7000 בתל אביב');
    expect(q.minPrice, 5000);
    expect(q.maxPrice, 7000);
  });

  test('budget "בערך" → window', () {
    final q = SmartSearch.parse('משהו בערך 6000 בחיפה');
    expect(q.minPrice, 5100);
    expect(q.maxPrice, 6900);
  });

  test('rooms range "3-4"', () {
    final q = SmartSearch.parse('דירת 3-4 חדרים');
    expect(q.minRooms, 3);
    expect(q.maxRooms, 4);
  });

  test('half rooms "שלוש וחצי"', () {
    expect(SmartSearch.parse('דירה שלוש וחצי חדרים').minRooms, 3.5);
  });

  test('neighborhood + property type + studio sizing', () {
    final q = SmartSearch.parse('סטודיו בפלורנטין עד 5000');
    expect(q.neighborhood, 'פלורנטין');
    expect(q.propertyType, 'סטודיו');
    expect(q.maxRooms, 2); // studio capped
    expect(q.maxPrice, 5000);
  });

  test('persona: student defaults to small when rooms unstated', () {
    final q = SmartSearch.parse('אני סטודנט מחפש משהו זול בבאר שבע');
    expect(q.minRooms, 1);
    expect(q.maxRooms, 2);
    expect(q.cheapPreference, true);
  });

  test('empty when nothing concrete', () {
    expect(SmartSearch.parse('שלום מה נשמע').isEmpty, true);
  });
}
