import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/widgets/ask_rently_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// "שאל את Rently" must ACTUALLY answer the common questions from the listing's
// own data — not always fall through to "couldn't answer". These lock that in.
RentalProperty _p({List<String> features = const []}) => RentalProperty(
      id: 'x',
      price: 6200,
      rooms: 3,
      sizeM2: 78,
      floor: '4',
      totalFloors: '9',
      city: 'תל אביב',
      neighborhood: 'פלורנטין',
      street: 'הרצל',
      streetNumber: 10,
      lat: 32.06,
      lon: 34.77,
      propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent,
      entryDate: '01/09/2026',
      condition: 'טוב',
      ownerName: 'בעלים',
      agencyListing: false,
      features: features,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image),
      ],
    );

void main() {
  test('answers floor / rooms / price / size / entry from the listing data', () {
    final f = _p();
    expect(answerFromListing('באיזו קומה הדירה?', f), contains('קומה 4'));
    expect(answerFromListing('כמה חדרים יש בדירה?', f), contains('3 חדרים'));
    expect(answerFromListing('מה המחיר?', f), contains('6200'));
    expect(answerFromListing('כמה מטר הדירה?', f), contains('78'));
    expect(answerFromListing('מתי אפשר להיכנס?', f), contains('01/09/2026'));
    expect(answerFromListing('באיזו שכונה זה?', f), contains('פלורנטין'));
  });

  test('parking / pets reflect the listing features', () {
    expect(answerFromListing('יש חניה?', _p(features: ['parking'])), contains('כן'));
    expect(answerFromListing('יש חניה?', _p(features: const [])),
        contains('לא צוינה'));
    expect(answerFromListing('מותר להחזיק כלב?', _p(features: ['petsAllowed'])),
        contains('כן'));
    expect(answerFromListing('מותר חתול?', _p(features: const [])),
        contains('לא צוין'));
  });

  test('a question the data cannot answer → null (→ landlord CTA)', () {
    expect(answerFromListing('האם השכנים רועשים בלילה?', _p()), isNull);
    expect(answerFromListing('מי הבעלים הקודמים?', _p()), isNull);
  });
}
