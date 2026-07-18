import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression: the backend sometimes stores media/imageUrls as JSON-ENCODED
// STRINGS (not arrays). A hard `as List<dynamic>?` cast in RentalProperty.fromJson
// threw 'String is not a subtype of List<dynamic>?', which silently dropped the
// listing from search AND broke deep links to it (rently://property/<id> that
// fetched the row by id would fail to open the apartment page). fromJson must
// decode these tolerantly.
// Minimal always-present fields a real listing carries (rooms/sizeM2/city are
// required by fromJson); the fields under test are layered on top per-case.
Map<String, dynamic> _base(Map<String, dynamic> extra) => {
      'id': 'x',
      'price': 5500,
      'rooms': 3,
      'sizeM2': 65,
      'city': 'רמת גן',
      'lat': 32.08,
      'lon': 34.81,
      'propertyType': 'apartment',
      ...extra,
    };

void main() {
  group('RentalProperty.fromJson tolerates string-encoded list fields', () {
    test('imageUrls given as a JSON-encoded string', () {
      final p = RentalProperty.fromJson(
          _base({'imageUrls': '["https://a/1.jpg","https://a/2.jpg"]'}));
      expect(p.imageUrls, ['https://a/1.jpg', 'https://a/2.jpg']);
    });

    test('media given as a JSON-encoded string', () {
      final p = RentalProperty.fromJson(
          _base({'media': '[{"url":"https://a/v.mp4","type":"video"}]'}));
      expect(p.media.length, 1);
      expect(p.mediaUrls, ['https://a/v.mp4']);
    });

    test('garbage / empty strings never throw', () {
      expect(
        () => RentalProperty.fromJson(_base({'imageUrls': '', 'media': 'oops'})),
        returnsNormally,
      );
    });
  });
}
