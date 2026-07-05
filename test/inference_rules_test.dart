import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('price magnitude infers rent vs sale (no explicit word)', () {
    expect(SmartSearch.parse('דירה בתל אביב עד 5000').transactionType, TransactionTypeFilter.rent);
    expect(SmartSearch.parse('דירה בחיפה עד 3200').transactionType, TransactionTypeFilter.rent);
    expect(SmartSearch.parse('דירה במודיעין עד מיליון וחצי').transactionType, TransactionTypeFilter.sale);
    expect(SmartSearch.parse('דירה בחיפה עד 900 אלף').transactionType, TransactionTypeFilter.sale);
    // explicit words still win
    expect(SmartSearch.parse('דירה למכירה עד 5000').transactionType, TransactionTypeFilter.sale);
  });
  test('pets → HARD requirement (a dog owner cannot take a no-pets flat)', () {
    expect(SmartSearch.parse('דירה בתל אביב עם כלב').requiredFeatures.contains('petsAllowed'), true);
    expect(SmartSearch.parse('דירה שמאפשרת חיות מחמד').requiredFeatures.contains('petsAllowed'), true);
    expect(SmartSearch.parse('דירה יפה בתל אביב').requiredFeatures.contains('petsAllowed'), false);
  });
  test('explicit "חייב + feature" → hard requirement', () {
    expect(SmartSearch.parse('דירה בפתח תקווה חייב מעלית').requiredFeatures.contains('elevator'), true);
    expect(SmartSearch.parse('חובה ממד בדירה').requiredFeatures.contains('mamad'), true);
    // a mere mention (no "חייב") stays a soft preference, not a hard filter
    expect(SmartSearch.parse('דירה עם מעלית').requiredFeatures.contains('elevator'), false);
  });
}
