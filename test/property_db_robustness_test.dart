import 'dart:convert';

import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RentalProperty.fromJson tolerates DynamoDB scalar variance', () {
    // A row where EVERY numeric field is a string (common DynamoDB shape) and id
    // is under propertyId — previously each hard cast dropped the whole listing.
    test('numbers-as-strings + propertyId key still parse', () {
      final p = RentalProperty.fromJson({
        'propertyId': 'X1',
        'rooms': '3.5',
        'sizeM2': '70',
        'lat': '32.08',
        'lon': '34.78',
        'streetNumber': '12',
        'price': '5400',
        'city': 'תל אביב',
        'propertyType': 'דירה',
      });
      expect(p.id, 'X1');
      expect(p.rooms, 3.5);
      expect(p.sizeM2, 70);
      expect(p.lat, closeTo(32.08, 0.001));
      expect(p.lon, closeTo(34.78, 0.001));
      expect(p.streetNumber, 12);
    });

    test('latitude/longitude alt keys work', () {
      final p = RentalProperty.fromJson({
        'id': 'Y', 'latitude': 31.5, 'longitude': 34.5,
      });
      expect(p.lat, 31.5);
      expect(p.lon, 34.5);
    });

    test('status string drives isActive (removed/paused/rented/draft → inactive)', () {
      for (final s in ['removed', 'paused', 'rented', 'draft']) {
        expect(RentalProperty.fromJson({'id': 'z', 'status': s}).isActive, isFalse,
            reason: 'status=$s should be inactive');
      }
      expect(RentalProperty.fromJson({'id': 'z', 'status': 'active'}).isActive, isTrue);
      // No status → falls back to isActive bool / default true.
      expect(RentalProperty.fromJson({'id': 'z'}).isActive, isTrue);
      expect(RentalProperty.fromJson({'id': 'z', 'isActive': false}).isActive, isFalse);
    });

    test('epoch-number dates (ms + seconds) parse for createdAt/boostedUntil', () {
      final ms = RentalProperty.fromJson({'id': 'a', 'boostedUntil': 1785500000000});
      expect(ms.boostedUntil, isNotNull);
      final secs = RentalProperty.fromJson({'id': 'b', 'createdAt': 1785500000});
      expect(secs.createdAt?.year ?? 0, greaterThan(2020));
    });

    test('boostedUntil survives toJson → fromJson round-trip', () {
      final until = DateTime.utc(2026, 8, 3);
      final p = RentalProperty.fromJson({'id': 'c'}).copyWith(boostedUntil: until);
      final round = RentalProperty.fromJson(p.toJson());
      expect(round.boostedUntil, until);
    });

    test('bool flags as 0/1 do not drop the listing', () {
      final p = RentalProperty.fromJson({'id': 'd', 'isActive': 1, 'agencyListing': 0});
      expect(p.isActive, isTrue);
      expect(p.agencyListing, isFalse);
    });

    test('panoramaTour stored as a JSON STRING still parses (not dropped)', () {
      // The backend persists the tour as jsonEncode(toJson()) → a String. A
      // remote fetch must decode it, or the 360 vanishes off-device.
      final tourJson = jsonEncode({
        'nodes': [
          {'id': 'n1', 'imageUrl': 'https://x/pano1.jpg', 'haov': 360, 'vaov': 180},
        ],
      });
      final p = RentalProperty.fromJson({'id': 'e', 'panoramaTour': tourJson});
      expect(p.hasPanoramaTour, isTrue, reason: 'string-encoded tour must survive');
      expect(p.panoramaTour?.nodes.length, 1);
    });

    test('virtualTour stored as a JSON STRING still parses (not dropped)', () {
      final vtJson = jsonEncode({
        'id': 'vt1', 'status': 'ready', 'viewerUrl': 'https://x/tour',
      });
      final p = RentalProperty.fromJson({'id': 'f', 'virtualTour': vtJson});
      expect(p.hasReadyVirtualTour, isTrue,
          reason: 'string-encoded virtual tour must survive');
    });
  });
}
