import 'package:dating_app/core/finance/price_realism.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty flat(
        {required int price,
        required int size,
        String city = 'תל אביב',
        PropertyTransactionType tx = PropertyTransactionType.rent}) =>
    RentalProperty(
      id: 'x', price: price, rooms: 3, sizeM2: size, floor: '2',
      totalFloors: '5', city: city, neighborhood: '', street: 'x',
      streetNumber: 1, lat: 32.08, lon: 34.78, propertyType: 'דירה',
      transactionType: tx, entryDate: '', condition: 'טוב', ownerName: 'o',
      agencyListing: false, features: const [],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
  });

  test('₪1,300/mo for a 430m² Tel Aviv house → tooLow (bait)', () {
    final v = PriceRealism.check(flat(price: 1300, size: 430));
    expect(v.flag, PriceFlag.tooLow);
    // Its "value" reward is heavily discounted so it can't top results.
    expect(PriceRealism.priceTrust(flat(price: 1300, size: 430)),
        lessThan(0.5));
  });

  test('a realistic Tel Aviv rent is OK', () {
    final v = PriceRealism.check(flat(price: 6500, size: 75));
    expect(v.flag, PriceFlag.ok);
    expect(PriceRealism.priceTrust(flat(price: 6500, size: 75)), 1.0);
  });

  test('missing size/price or unknown city → unknown (never a false alarm)', () {
    expect(PriceRealism.check(flat(price: 0, size: 80)).flag, PriceFlag.unknown);
    expect(
        PriceRealism.check(flat(price: 5000, size: 0)).flag, PriceFlag.unknown);
  });
}
