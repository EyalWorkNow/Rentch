import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/models/saved_search.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty _property({
  String id = 'p1',
  int price = 5000,
  double rooms = 3,
  String city = 'תל אביב',
  PropertyTransactionType transactionType = PropertyTransactionType.rent,
  List<String> features = const [],
}) {
  return RentalProperty(
    id: id,
    price: price,
    rooms: rooms,
    sizeM2: 80,
    floor: '2',
    totalFloors: '5',
    city: city,
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
    features: features,
    media: const [],
    transactionType: transactionType,
  );
}

void main() {
  group('SavedSearch.matches', () {
    test('empty search matches any property', () {
      final search = SavedSearch(id: '1', name: 'הכל');
      expect(search.matches(_property()), isTrue);
    });

    test('city must match (case-insensitive, anywhere when unset)', () {
      final tlv = SavedSearch(id: '1', name: 'תל אביב', city: 'תל אביב');
      expect(tlv.matches(_property(city: 'תל אביב')), isTrue);
      expect(tlv.matches(_property(city: 'חיפה')), isFalse);

      final anywhere = SavedSearch(id: '2', name: 'הכל');
      expect(anywhere.matches(_property(city: 'באר שבע')), isTrue);
    });

    test('budget bounds are inclusive', () {
      final search =
          SavedSearch(id: '1', name: 'תקציב', minBudget: 4000, maxBudget: 6000);
      expect(search.matches(_property(price: 4000)), isTrue);
      expect(search.matches(_property(price: 6000)), isTrue);
      expect(search.matches(_property(price: 3999)), isFalse);
      expect(search.matches(_property(price: 6001)), isFalse);
    });

    test('room bounds are inclusive', () {
      final search =
          SavedSearch(id: '1', name: 'חדרים', minRooms: 3, maxRooms: 4);
      expect(search.matches(_property(rooms: 3)), isTrue);
      expect(search.matches(_property(rooms: 4)), isTrue);
      expect(search.matches(_property(rooms: 2.5)), isFalse);
      expect(search.matches(_property(rooms: 4.5)), isFalse);
    });

    test('transactionType filters rent vs sale', () {
      final rent = SavedSearch(id: '1', name: 'השכרה', transactionType: 'rent');
      expect(
        rent.matches(_property(transactionType: PropertyTransactionType.rent)),
        isTrue,
      );
      expect(
        rent.matches(_property(transactionType: PropertyTransactionType.sale)),
        isFalse,
      );
    });

    test('requiredTags must all be present in searchable text', () {
      final search = SavedSearch(
        id: '1',
        name: 'מרפסת',
        requiredTags: const ['מרפסת'],
      );
      expect(search.matches(_property(features: const ['מרפסת'])), isTrue);
      expect(search.matches(_property(features: const ['מעלית'])), isFalse);
    });

    test('combined criteria require all to pass', () {
      final search = SavedSearch(
        id: '1',
        name: 'משולב',
        city: 'תל אביב',
        maxBudget: 6000,
        minRooms: 3,
        transactionType: 'rent',
      );
      expect(
        search.matches(_property(city: 'תל אביב', price: 5500, rooms: 3)),
        isTrue,
      );
      // Right city/rooms but over budget.
      expect(
        search.matches(_property(city: 'תל אביב', price: 7000, rooms: 3)),
        isFalse,
      );
    });
  });

  group('SavedSearch JSON round-trip', () {
    test('full object round-trips', () {
      final original = SavedSearch(
        id: 'ss_1',
        name: '3 חדרים בתל אביב',
        city: 'תל אביב',
        minBudget: 4000,
        maxBudget: 6500,
        minRooms: 3,
        maxRooms: 4,
        transactionType: 'rent',
        requiredTags: const ['מרפסת', 'מעלית'],
        alertsOn: false,
        createdAt: DateTime.parse('2026-06-20T10:00:00.000'),
      );

      final restored = SavedSearch.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.city, original.city);
      expect(restored.minBudget, original.minBudget);
      expect(restored.maxBudget, original.maxBudget);
      expect(restored.minRooms, original.minRooms);
      expect(restored.maxRooms, original.maxRooms);
      expect(restored.transactionType, original.transactionType);
      expect(restored.requiredTags, original.requiredTags);
      expect(restored.alertsOn, original.alertsOn);
      expect(restored.createdAt, original.createdAt);
    });

    test('minimal object round-trips with null optionals', () {
      final original = SavedSearch(id: 'ss_2', name: 'הכל');
      final restored = SavedSearch.fromJson(original.toJson());
      expect(restored.id, 'ss_2');
      expect(restored.city, isNull);
      expect(restored.minBudget, isNull);
      expect(restored.requiredTags, isEmpty);
      expect(restored.alertsOn, isTrue);
    });
  });
}
