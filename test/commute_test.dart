import 'package:dating_app/core/finance/commute.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Commute.estimate', () {
    test('haversine + minute estimate on a known pair (TLV → Herzliya)', () {
      // Tel Aviv center → Herzliya: a well-known ~12 km hop.
      final e = Commute.estimate(
        propLat: 32.0853,
        propLon: 34.7818,
        workLat: 32.1624,
        workLon: 34.8443,
      )!;

      // Great-circle distance is ~10.4 km — assert a tight band around it.
      expect(e.straightLineKm, closeTo(10.4, 0.5));

      // road ≈ 1.3× straight ≈ 13.5 km at 25 km/h ⇒ ~32 min drive.
      expect(e.approxDriveMinutes, inInclusiveRange(30, 36));

      // Transit is slower than driving + fixed overhead.
      expect(e.approxTransitMinutes, greaterThan(e.approxDriveMinutes));

      // Honest, approximate Hebrew label.
      expect(e.plainHebrewLabel, contains('כ-'));
      expect(e.plainHebrewLabel, contains('לעבודה'));
    });

    test('zero distance ⇒ ~0 minutes', () {
      final e = Commute.estimate(
        propLat: 32.0853,
        propLon: 34.7818,
        workLat: 32.0853,
        workLon: 34.7818,
      )!;
      expect(e.straightLineKm, closeTo(0.0, 0.01));
      expect(e.approxDriveMinutes, 0);
    });

    test('invalid (null-island) coords ⇒ null', () {
      expect(
        Commute.estimate(
          propLat: 0,
          propLon: 0,
          workLat: 32.0853,
          workLon: 34.7818,
        ),
        isNull,
      );
    });
  });
}
