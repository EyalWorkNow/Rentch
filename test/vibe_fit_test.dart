import 'package:dating_app/core/search/advanced_matcher.dart';
import 'package:dating_app/data/repositories/property_search_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// vibe_fit as computed in PropertySearchRepository._features (kept in sync).
double _vibeFit(String? vibe, String neighborhood, String city) {
  final target = vibeTargetVibrancy(vibe);
  if (target == null) return 0.5;
  final v = AdvancedMatcher.neighborhoodVibrancy(neighborhood, city);
  return (1.0 - ((v - target).abs() / 2.0)).clamp(0.0, 1.0);
}

void main() {
  test('vibe target mapping', () {
    expect(vibeTargetVibrancy(null), isNull);
    expect(vibeTargetVibrancy('  '), isNull);
    expect(vibeTargetVibrancy('משהו אחר'), isNull); // unknown → neutral
    expect(vibeTargetVibrancy('שקט')! < 0, isTrue);
    expect(vibeTargetVibrancy('תוסס')! > 0, isTrue);
  });

  test('no vibe requested → neutral 0.5 (no sort effect)', () {
    expect(_vibeFit(null, 'פלורנטין', 'תל אביב'), 0.5);
    expect(_vibeFit('', 'רמת אביב', 'תל אביב'), 0.5);
  });

  test('quiet request ranks a quiet neighborhood above a vibrant one', () {
    final quietHood = _vibeFit('שקט', 'רמת אביב', 'תל אביב');
    final vibrantHood = _vibeFit('שקט', 'פלורנטין', 'תל אביב');
    expect(quietHood, greaterThan(vibrantHood));
  });

  test('vibrant request flips the ranking', () {
    final quietHood = _vibeFit('תוסס', 'רמת אביב', 'תל אביב');
    final vibrantHood = _vibeFit('תוסס', 'פלורנטין', 'תל אביב');
    expect(vibrantHood, greaterThan(quietHood));
  });

  group('per-cohort weights', () {
    test('cohort inferred from vibe', () {
      expect(PropertySearchRepository.cohortFromVibe('סטודנטיאלי'), 'student');
      expect(PropertySearchRepository.cohortFromVibe('משפחתי'), 'family');
      expect(PropertySearchRepository.cohortFromVibe('שקט'), isNull);
      expect(PropertySearchRepository.cohortFromVibe(null), isNull);
    });

    test('unknown cohort → base weights', () {
      final base = PropertySearchRepository.weightsFor(null);
      expect(base['price_fit'], 0.25);
      expect(base['tag_overlap'], 0.30);
    });

    test('semantic_sim term is in every weight-set', () {
      for (final cohort in [null, 'student', 'family']) {
        final w = PropertySearchRepository.weightsFor(cohort);
        expect(w['semantic_sim'], isNotNull,
            reason: 'cohort=$cohort must keep semantic_sim');
        expect(w['semantic_sim']! > 0, isTrue);
      }
    });

    test('students weight price higher, families weight amenities higher', () {
      final base = PropertySearchRepository.weightsFor(null);
      final student = PropertySearchRepository.weightsFor('student');
      final family = PropertySearchRepository.weightsFor('family');
      expect(student['price_fit'], greaterThan(base['price_fit']!));
      expect(family['tag_overlap'], greaterThan(base['tag_overlap']!));
      // Overrides don't drop the untouched terms.
      expect(student['vibe_fit'], base['vibe_fit']);
    });
  });

  group('effectiveQueryText (kNN query source)', () {
    test('raw NL text wins when provided', () {
      const c = PropertySearchCriteria(
        city: 'תל אביב',
        vibe: 'שקט',
        queryText: 'משהו ליד הים עם מרפסת',
      );
      expect(PropertySearchRepository.effectiveQueryText(c),
          'משהו ליד הים עם מרפסת');
    });

    test('synthesized from chips when no raw text', () {
      const c = PropertySearchCriteria(city: 'חיפה', vibe: 'משפחתי', minRooms: 3);
      final q = PropertySearchRepository.effectiveQueryText(c)!;
      expect(q, contains('משפחתי'));
      expect(q, contains('חיפה'));
      expect(q, contains('3 חדרים'));
    });

    test('null when there is nothing meaningful to search on', () {
      expect(PropertySearchRepository.effectiveQueryText(
          const PropertySearchCriteria()), isNull);
      expect(PropertySearchRepository.effectiveQueryText(
          const PropertySearchCriteria(queryText: '   ')), isNull);
    });
  });

  group('neighborhood_fit (public-data personalization)', () {
    // A: family-friendly area (great schools + safety, poor transit).
    final areaA = {
      'neighborhoodScore': {
        'sub': {'safety': 90, 'schools': 95, 'green': 80, 'walkability': 40, 'transit': 20},
      },
    };
    // B: student-friendly area (great transit + walkability, weak schools).
    final areaB = {
      'neighborhoodScore': {
        'sub': {'safety': 50, 'schools': 30, 'green': 30, 'walkability': 90, 'transit': 95},
      },
    };

    test('neutral 0.5 when the listing has no neighborhood score', () {
      expect(PropertySearchRepository.neighborhoodFit(const {}, 'family'), 0.5);
      expect(PropertySearchRepository.neighborhoodFit(
          {'neighborhoodScore': {}}, 'student'), 0.5);
    });

    test('families rank the schools/safety area above the transit area', () {
      final famA = PropertySearchRepository.neighborhoodFit(areaA, 'family');
      final famB = PropertySearchRepository.neighborhoodFit(areaB, 'family');
      expect(famA, greaterThan(famB));
    });

    test('students rank the transit area above the schools area (flip)', () {
      final stuA = PropertySearchRepository.neighborhoodFit(areaA, 'student');
      final stuB = PropertySearchRepository.neighborhoodFit(areaB, 'student');
      expect(stuB, greaterThan(stuA));
    });

    test('renormalizes when a dimension (e.g. safety) is missing', () {
      final noSafety = {
        'neighborhoodScore': {'sub': {'schools': 100, 'walkability': 100}},
      };
      final fit = PropertySearchRepository.neighborhoodFit(noSafety, 'family');
      expect(fit, closeTo(1.0, 1e-9)); // all present dims maxed → 1.0
    });

    test('cohort weights favor the expected dimension', () {
      expect(PropertySearchRepository.neighborhoodWeightsFor('family')['schools']!,
          greaterThan(PropertySearchRepository.neighborhoodWeightsFor(null)['schools']!));
      expect(PropertySearchRepository.neighborhoodWeightsFor('student')['transit']!,
          greaterThan(PropertySearchRepository.neighborhoodWeightsFor(null)['transit']!));
    });
  });
}
