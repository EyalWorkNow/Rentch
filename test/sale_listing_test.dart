import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty _property({
  required String id,
  required int price,
  required PropertyTransactionType transactionType,
}) {
  return RentalProperty(
    id: id,
    price: price,
    rooms: 3,
    sizeM2: 80,
    floor: '2',
    totalFloors: '5',
    city: 'תל אביב',
    neighborhood: 'פלורנטין',
    street: 'הרצל',
    streetNumber: 10,
    lat: 32.05,
    lon: 34.77,
    propertyType: 'דירה',
    entryDate: '2026-09-01',
    condition: 'תקין',
    ownerName: 'בעל הנכס',
    agencyListing: false,
    features: const [],
    media: const [],
    transactionType: transactionType,
  );
}

void main() {
  group('RentalProperty sale serialization', () {
    test('sale transactionType round-trips through JSON', () {
      final sale = _property(
        id: 'sale-1',
        price: 1850000,
        transactionType: PropertyTransactionType.sale,
      );
      final restored = RentalProperty.fromJson(sale.toJson());
      expect(restored.transactionType, PropertyTransactionType.sale);
      expect(restored.price, 1850000);
      expect(restored.priceSuffixLabel, 'למכירה');
      expect(restored.transactionLabel, 'מכירה');
    });

    test('rent remains the default and round-trips', () {
      final rent = _property(
        id: 'rent-1',
        price: 5200,
        transactionType: PropertyTransactionType.rent,
      );
      final restored = RentalProperty.fromJson(rent.toJson());
      expect(restored.transactionType, PropertyTransactionType.rent);
      expect(restored.priceSuffixLabel, 'לחודש');
    });

    test('legacy JSON without transactionType parses as rent (back-compat)', () {
      final json = _property(
        id: 'legacy-1',
        price: 4800,
        transactionType: PropertyTransactionType.rent,
      ).toJson()
        ..remove('transactionType');
      final restored = RentalProperty.fromJson(json);
      expect(restored.transactionType, PropertyTransactionType.rent);
    });

    test('alternate sale spellings parse to sale', () {
      for (final raw in ['sale', 'sell', 'for_sale']) {
        final json = _property(
          id: 'x',
          price: 1000000,
          transactionType: PropertyTransactionType.rent,
        ).toJson()
          ..['transactionType'] = raw;
        expect(RentalProperty.fromJson(json).transactionType,
            PropertyTransactionType.sale,
            reason: 'value "$raw" should map to sale');
      }
    });
  });

  group('SmartSearch sale intent', () {
    test('"למכירה" sets sale transaction type', () {
      final q = SmartSearch.parse('דירת 4 חדרים למכירה בתל אביב');
      expect(q.transactionType, TransactionTypeFilter.sale);
    });

    test('"לקנות" sets sale transaction type', () {
      final q = SmartSearch.parse('אני רוצה לקנות דירה בחיפה');
      expect(q.transactionType, TransactionTypeFilter.sale);
    });

    test('"להשכרה" pins rent', () {
      final q = SmartSearch.parse('דירה להשכרה בתל אביב');
      expect(q.transactionType, TransactionTypeFilter.rent);
    });

    test('no rent/sale phrasing stays "any"', () {
      final q = SmartSearch.parse('דירת 3 חדרים בפלורנטין');
      expect(q.transactionType, TransactionTypeFilter.any);
    });

    test('sale search never surfaces rent listings', () {
      final props = [
        _property(
          id: 'rent',
          price: 6000,
          transactionType: PropertyTransactionType.rent,
        ),
        _property(
          id: 'sale',
          price: 1900000,
          transactionType: PropertyTransactionType.sale,
        ),
      ];
      final q = SmartSearch.parse('דירה למכירה בתל אביב');
      final results = SmartSearch.rank(props, q, limit: 10);
      expect(results.isNotEmpty, true);
      expect(
        results.every(
            (r) => r.property.transactionType == PropertyTransactionType.sale),
        true,
      );
    });
  });
}
