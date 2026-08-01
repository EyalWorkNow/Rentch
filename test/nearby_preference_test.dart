import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nearbyKindToDimension', () {
    test('maps categories to existing ranking dimensions', () {
      expect(nearbyKindToDimension(NearbyKind.schools), 'schools');
      expect(nearbyKindToDimension(NearbyKind.kindergartens), 'school_young');
      expect(nearbyKindToDimension(NearbyKind.playgrounds), 'school_young');
      expect(nearbyKindToDimension(NearbyKind.clinics), 'health');
      expect(nearbyKindToDimension(NearbyKind.pharmacies), 'health');
      expect(nearbyKindToDimension(NearbyKind.hospitals), 'health');
      expect(nearbyKindToDimension(NearbyKind.supermarkets), 'convenience');
      expect(nearbyKindToDimension(NearbyKind.parks), 'park');
      expect(nearbyKindToDimension(NearbyKind.gyms), 'park');
      expect(nearbyKindToDimension(NearbyKind.pools), 'park');
      expect(nearbyKindToDimension(NearbyKind.synagogues), 'religious_area');
      expect(nearbyKindToDimension(NearbyKind.worship), 'religious_area');
      expect(nearbyKindToDimension(NearbyKind.transit), 'transit');
      expect(nearbyKindToDimension(NearbyKind.bikeShare), 'transit');
      expect(nearbyKindToDimension(NearbyKind.nightlife), 'nightlife');
      expect(nearbyKindToDimension(NearbyKind.dining), 'nightlife');
      expect(nearbyKindToDimension(NearbyKind.culture), 'university');
      expect(nearbyKindToDimension(NearbyKind.coworking), 'employment');
    });

    test('display-only categories have no ranking dimension', () {
      expect(nearbyKindToDimension(NearbyKind.vets), isNull);
      expect(nearbyKindToDimension(NearbyKind.parking), isNull);
    });

    test('every NearbyKind is handled (no missing switch case)', () {
      for (final k in NearbyKind.values) {
        nearbyKindToDimension(k); // must not throw
      }
    });
  });

  group('SearchFilters.preferredNearby', () {
    SearchFilters base() => SearchFilters.fromJson(const {});

    test('defaults to empty', () {
      expect(base().preferredNearby, isEmpty);
    });

    test('toggleNearby adds then removes', () {
      var f = base();
      f = f.toggleNearby(NearbyKind.parks);
      expect(f.preferredNearby, contains(NearbyKind.parks));
      f = f.toggleNearby(NearbyKind.transit);
      expect(f.preferredNearby, {NearbyKind.parks, NearbyKind.transit});
      f = f.toggleNearby(NearbyKind.parks);
      expect(f.preferredNearby, {NearbyKind.transit});
    });

    test('survives a toJson → fromJson round-trip', () {
      final f = base().copyWith(
        preferredNearby: {NearbyKind.schools, NearbyKind.synagogues},
      );
      final round = SearchFilters.fromJson(f.toJson());
      expect(round.preferredNearby, {NearbyKind.schools, NearbyKind.synagogues});
    });

    test('fromJson silently skips unknown category names', () {
      final json = base().toJson();
      json['preferredNearby'] = ['parks', 'not_a_real_kind', 'transit'];
      final f = SearchFilters.fromJson(json);
      expect(f.preferredNearby, {NearbyKind.parks, NearbyKind.transit});
    });
  });
}
