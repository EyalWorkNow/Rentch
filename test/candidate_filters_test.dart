import 'package:dating_app/data/models/candidate_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const highFit = CandidateAttributes(fitScore: 82, availableInDays: 0);
  const lowFit = CandidateAttributes(fitScore: 40, availableInDays: 120);

  group('CandidateFilters — empty / active count', () {
    test('empty filter matches anything and is empty', () {
      expect(CandidateFilters.empty.isEmpty, isTrue);
      expect(CandidateFilters.empty.activeCount, 0);
      expect(CandidateFilters.empty.matches(highFit), isTrue);
      expect(CandidateFilters.empty.matches(lowFit), isTrue);
    });

    test('activeCount counts each active constraint', () {
      const f = CandidateFilters(
        minFitScore: 70,
        moveInWindow: 'immediate',
        verifiedOnly: true,
      );
      expect(f.activeCount, 3);
      expect(f.isEmpty, isFalse);
    });

    test('self-check demo() passes its own asserts', () {
      // Throws only if an assert trips (asserts are on under `flutter test`).
      CandidateFilters.demo();
    });
  });

  group('minFitScore', () {
    test('excludes below threshold, keeps at/above', () {
      expect(const CandidateFilters(minFitScore: 70).matches(highFit), isTrue);
      expect(const CandidateFilters(minFitScore: 70).matches(lowFit), isFalse);
      expect(const CandidateFilters(minFitScore: 82).matches(highFit), isTrue);
    });
  });

  group('move-in / availability window', () {
    const soon = CandidateAttributes(fitScore: 50, availableInDays: 20);
    const later = CandidateAttributes(fitScore: 50, availableInDays: 150);

    test('immediate requires available now', () {
      expect(
          const CandidateFilters(moveInWindow: 'immediate').matches(highFit),
          isTrue);
      expect(const CandidateFilters(moveInWindow: 'immediate').matches(soon),
          isFalse);
    });

    test('within-month keeps <=30 days, drops later', () {
      expect(const CandidateFilters(moveInWindow: 'month').matches(soon),
          isTrue);
      expect(const CandidateFilters(moveInWindow: 'month').matches(later),
          isFalse);
    });

    test('unknown availability always passes', () {
      const noDate = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(moveInWindow: 'immediate').matches(noDate),
          isTrue);
    });
  });

  group('budget range (candidate declared)', () {
    const budgeted = CandidateAttributes(fitScore: 50, budget: 6000);

    test('within range passes, outside fails', () {
      expect(const CandidateFilters(budgetMin: 5000).matches(budgeted), isTrue);
      expect(const CandidateFilters(budgetMax: 7000).matches(budgeted), isTrue);
      expect(
          const CandidateFilters(budgetMin: 6500).matches(budgeted), isFalse);
      expect(
          const CandidateFilters(budgetMax: 5500).matches(budgeted), isFalse);
    });

    test('unknown budget never excluded', () {
      const noBudget = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(budgetMin: 5000, budgetMax: 7000)
          .matches(noBudget), isTrue);
    });
  });

  group('attribute constraints (future-proof, unknown passes)', () {
    test('pets / car / wfh equality when known', () {
      const withPets = CandidateAttributes(fitScore: 50, hasPets: true);
      expect(const CandidateFilters(hasPets: false).matches(withPets), isFalse);
      expect(const CandidateFilters(hasPets: true).matches(withPets), isTrue);
      // Unknown pets → passes even a strict pets filter.
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(hasPets: false).matches(unknown), isTrue);
    });

    test('numChildrenMax caps known counts', () {
      const three = CandidateAttributes(fitScore: 50, numChildren: 3);
      expect(const CandidateFilters(numChildrenMax: 2).matches(three), isFalse);
      expect(const CandidateFilters(numChildrenMax: 3).matches(three), isTrue);
    });

    test('incomeMin floors known income', () {
      const earner = CandidateAttributes(fitScore: 50, income: 12000);
      expect(const CandidateFilters(incomeMin: 15000).matches(earner), isFalse);
      expect(const CandidateFilters(incomeMin: 10000).matches(earner), isTrue);
    });

    test('household / occupation set membership', () {
      const c = CandidateAttributes(
          fitScore: 50, household: 'family', occupation: 'engineer');
      expect(
          const CandidateFilters(household: {'single'}).matches(c), isFalse);
      expect(const CandidateFilters(household: {'family', 'couple'}).matches(c),
          isTrue);
      expect(const CandidateFilters(occupation: {'engineer'}).matches(c),
          isTrue);
    });

    test('verifiedOnly excludes explicitly-unverified, passes unknown', () {
      const unverified = CandidateAttributes(fitScore: 50, verified: false);
      const verified = CandidateAttributes(fitScore: 50, verified: true);
      const unknown = CandidateAttributes(fitScore: 50);
      expect(
          const CandidateFilters(verifiedOnly: true).matches(unverified),
          isFalse);
      expect(
          const CandidateFilters(verifiedOnly: true).matches(verified), isTrue);
      expect(
          const CandidateFilters(verifiedOnly: true).matches(unknown), isTrue);
    });
  });

  group('copyWith', () {
    test('sets and clears fields', () {
      const base = CandidateFilters(minFitScore: 70, moveInWindow: 'month');
      expect(base.copyWith(minFitScore: 90).minFitScore, 90);
      expect(base.copyWith(clearMinFitScore: true).minFitScore, isNull);
      // Unrelated field preserved through a clear.
      expect(base.copyWith(clearMinFitScore: true).moveInWindow, 'month');
    });
  });
}
