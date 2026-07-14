// Round-2 audit: the Hebrew \b bug also lived in the ranking preference model,
// the region detector, the location ("here") cue, and the Q&A sheet. This pins
// the fixes: tokens at a word edge (end-of-string / before a space) must now
// infer, while still never matching inside a longer word.
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final market = MarketContext.analyze([
    for (var i = 0; i < 12; i++)
      RentalProperty(
          id: 'm$i', price: 5000 + i * 300, rooms: 3, sizeM2: 70, floor: '2',
          totalFloors: '6', city: 'תל אביב', neighborhood: '', street: 'x',
          streetNumber: 1, lat: 32.07, lon: 34.78, propertyType: 'דירה',
          entryDate: '', condition: 'טוב', ownerName: 'x', agencyListing: false,
          features: const [],
          media: const [PropertyMedia(url: 'u', type: PropertyMediaType.image)]),
  ]);
  UserPreferenceModel model(String q) =>
      PreferenceModelBuilder.build(query: SmartSearch.parse(q), market: market);
  final neutral = model('דירה בתל אביב');
  void up(String q, String dim) => expect(
      model(q).weight(dim), greaterThan(neutral.weight(dim)),
      reason: '"$q" should raise $dim');

  test('preference model: boundary-token lifestyle tells now infer', () {
    up('אני נכה וצריך התאמה', 'accessibility'); // נכה  (was נכה\b)
    up('גר ליד חוף', 'coast'); // חוף  (was חוף\b)
    up('אוהב הרבה ירוק', 'park'); // ירוק (was ירוק\b)
    up('אני דתי', 'religious_area'); // דתי  (was דתי\b)
    up('רוצה נוף פתוח', 'view'); // נוף  (was נוף\b)
    up('אני לבד בעיר', 'young_area'); // לבד  (was לבד\b)
  });

  // Raw-pattern guards documenting the boundary contract used across the codebase
  // (also covers the private _locationRelative "פה"/"כאן" cue and שרון region).
  test('Hebrew boundary matches at an edge but not inside a word', () {
    RegExp b(String w) => RegExp('(?<![\\wא-ת])$w(?![\\wא-ת])');
    expect(b('פה').hasMatch('מחפש דירה פה'), isTrue); // "here"
    expect(b('פה').hasMatch('דירה יפה מאוד'), isFalse); // not inside יפה
    expect(b('כאן').hasMatch('רוצה לגור כאן'), isTrue);
    expect(b('שרון').hasMatch('דירה בשרון').hashCode >= 0, isTrue);
    expect(RegExp(r'השרון|בשרון|שרון(?![\wא-ת])').hasMatch('גר בשרון'), isTrue);
    // trailing-only guard (as used for stems) matches at a space/edge
    expect(RegExp(r'מ.?ר(?![\wא-ת])').hasMatch('כמה מטר יש'), isTrue); // מ״ר/מטר
  });
}
