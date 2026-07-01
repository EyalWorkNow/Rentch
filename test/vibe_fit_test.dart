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
}
