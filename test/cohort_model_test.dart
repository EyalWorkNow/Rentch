import 'package:dating_app/core/search/cohort_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distribution is a probability vector that reflects the signals', () {
    final d = CohortModel.distribution({'household': 'family', 'isReligious': 'true', 'religiousStream': 'dati_leumi'});
    final sum = d.values.fold<double>(0, (a, b) => a + b);
    expect(sum, closeTo(1.0, 1e-9));
    expect(CohortModel.topCohort({'household': 'family', 'isReligious': 'true', 'religiousStream': 'dati_leumi'}),
        'dati_leumi');
  });

  test('no signals → all-zero, no cohort guessed', () {
    final d = CohortModel.distribution(const {});
    expect(d.values.every((v) => v == 0), isTrue);
    expect(CohortModel.topCohort(const {}), isNull);
  });

  test('investor intent dominates', () {
    expect(CohortModel.topCohort({'isInvestor': 'true'}), 'investor');
  });

  test('belief sharpens toward a consistent signal over sessions', () {
    final b = CohortBelief();
    expect(b.top, isNull);
    for (var i = 0; i < 5; i++) {
      b.observe({'lifeStage': 'student', 'household': 'student'});
    }
    expect(b.top, 'student');
    expect(b.observations, 5);
    expect(b.weights['student']!, greaterThan(0.5));
  });

  test('a one-off different signal does not immediately flip a settled belief', () {
    final b = CohortBelief();
    for (var i = 0; i < 6; i++) {
      b.observe({'household': 'family'});
    }
    final familyBefore = b.weights['family']!;
    b.observe({'isInvestor': 'true'}); // single outlier
    expect(b.top, 'family', reason: 'one outlier should not flip a settled belief');
    expect(b.weights['investor']!, lessThan(familyBefore));
  });

  test('JSON round-trip preserves the belief', () {
    final b = CohortBelief();
    b.observe({'wfh': 'true', 'household': 'single'});
    b.observe({'household': 'single'});
    final back = CohortBelief.fromJson(b.toJson());
    expect(back.observations, b.observations);
    expect(back.top, b.top);
    expect(back.weights['remote'], closeTo(b.weights['remote']!, 1e-3));
  });

  test('topK returns the strongest cohorts above the floor', () {
    final b = CohortBelief();
    b.observe({'household': 'family', 'wfh': 'true'});
    final top = b.topK(3);
    expect(top, isNotEmpty);
    expect(top.first, anyOf('family', 'remote'));
  });
}
