import 'package:dating_app/data/models/user_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserSignals.update reducer', () {
    final t0 = DateTime.utc(2026, 6, 28, 14, 0);

    test('liking an over-budget listing raises revealedBudgetTolerance', () {
      const start = UserSignals(); // tolerance == 1.0
      final after = UserSignals.update(
        start,
        type: 'swipeOutcome',
        event: {'direction': 'like', 'priceToBudgetRatio': 1.3},
        at: t0,
      );

      expect(after.revealedBudgetTolerance, greaterThan(1.0),
          reason: 'an over-budget like must raise tolerance');
      expect(after.revealedBudgetTolerance, lessThan(1.3),
          reason: 'blend should not jump straight to the raw ratio');

      // A skip of an over-budget listing must NOT raise tolerance.
      final skip = UserSignals.update(
        start,
        type: 'swipeOutcome',
        event: {'direction': 'skip', 'priceToBudgetRatio': 1.3},
        at: t0,
      );
      expect(skip.revealedBudgetTolerance, 1.0);

      // An under-budget like must not shrink an already-high tolerance.
      final high = start.copyWith(revealedBudgetTolerance: 1.2);
      final cheap = UserSignals.update(
        high,
        type: 'swipeOutcome',
        event: {'direction': 'like', 'priceToBudgetRatio': 0.9},
        at: t0,
      );
      expect(cheap.revealedBudgetTolerance, 1.2);
    });

    test('repeated likes of a tag raise its affinity', () {
      var s = const UserSignals();
      for (var i = 0; i < 3; i++) {
        s = UserSignals.update(
          s,
          type: 'tagLiked',
          event: {'tag': 'balcony'},
          at: t0,
        );
      }
      final a1 = s.tagAffinity['balcony']!;
      expect(a1, greaterThan(0.0));

      // One more like raises it further (monotonic, until clamp).
      final s2 = UserSignals.update(
        s,
        type: 'tagLiked',
        event: {'tag': 'balcony'},
        at: t0,
      );
      expect(s2.tagAffinity['balcony']!, greaterThan(a1));

      // A deal-breaker on the same tag lowers affinity.
      final s3 = UserSignals.update(
        s2,
        type: 'dealBreakerApplied',
        event: {'tag': 'balcony', 'kind': 'critical'},
        at: t0,
      );
      expect(s3.tagAffinity['balcony']!, lessThan(s2.tagAffinity['balcony']!));

      // Affinity stays clamped within [-1, 1] under many likes.
      var spam = const UserSignals();
      for (var i = 0; i < 50; i++) {
        spam = UserSignals.update(spam,
            type: 'tagLiked', event: {'tag': 'x'}, at: t0);
      }
      expect(spam.tagAffinity['x']!, lessThanOrEqualTo(1.0));
    });

    test('dwell folds into a running average', () {
      const start = UserSignals(); // avgDwellMs == 0
      final first = UserSignals.update(
        start,
        type: 'cardDwell',
        event: {'dwellMs': 1000},
        at: t0,
      );
      // First sample seeds the average exactly.
      expect(first.avgDwellMs, 1000.0);

      final second = UserSignals.update(
        first,
        type: 'cardDwell',
        event: {'dwellMs': 3000},
        at: t0,
      );
      // EMA: strictly between the old average and the new sample.
      expect(second.avgDwellMs, greaterThan(1000.0));
      expect(second.avgDwellMs, lessThan(3000.0));
    });

    test('likedLocation merges nearby points and appends distant ones', () {
      var s = const UserSignals();
      // Two near Tel Aviv (~within 2km) collapse into one centroid.
      s = UserSignals.update(s,
          type: 'likedLocation', event: {'lat': 32.0853, 'lng': 34.7818}, at: t0);
      s = UserSignals.update(s,
          type: 'likedLocation', event: {'lat': 32.0900, 'lng': 34.7850}, at: t0);
      expect(s.preferredAreas.length, 1);
      expect(s.preferredAreas.first.weight, 2.0);

      // A far point (Haifa) creates a second centroid.
      s = UserSignals.update(s,
          type: 'likedLocation', event: {'lat': 32.7940, 'lng': 34.9896}, at: t0);
      expect(s.preferredAreas.length, 2);
    });

    test('media engagement and activity bookkeeping fold in', () {
      const start = UserSignals();
      final after = UserSignals.update(
        start,
        type: 'mediaEngagement',
        event: {'opened360': true, 'opened3d': true, 'photosViewed': 5},
        at: t0,
      );
      expect(after.mediaEngagementScore, greaterThan(0.0));
      expect(after.activeHours, contains(t0.toLocal().hour));
      expect(after.lastActiveAt, t0);

      final session = UserSignals.update(after,
          type: 'sessionStarted', at: t0.add(const Duration(hours: 1)));
      expect(session.sessionCount, 1);
    });

    test('JSON round-trip preserves all derived columns', () {
      final s = UserSignals.update(
        const UserSignals(),
        type: 'swipeOutcome',
        event: {'direction': 'superlike', 'priceToBudgetRatio': 1.4},
        at: t0,
      ).copyWith(
        tagAffinity: {'balcony': 0.6},
        preferredAreas: const [AreaCentroid(lat: 32.0, lng: 34.0, weight: 3)],
        activeHours: const [14, 20],
        sessionCount: 7,
      );

      final round = UserSignals.decode(s.encode());
      expect(round.revealedBudgetTolerance, s.revealedBudgetTolerance);
      expect(round.tagAffinity['balcony'], 0.6);
      expect(round.preferredAreas.first.weight, 3);
      expect(round.activeHours, [14, 20]);
      expect(round.sessionCount, 7);
      expect(round.lastActiveAt, t0);
    });
  });
}
