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

  group('age range (candidate declared)', () {
    const aged = CandidateAttributes(fitScore: 50, age: 29);

    test('within range passes, outside fails', () {
      expect(const CandidateFilters(ageMin: 25).matches(aged), isTrue);
      expect(const CandidateFilters(ageMax: 35).matches(aged), isTrue);
      expect(const CandidateFilters(ageMin: 30).matches(aged), isFalse);
      expect(const CandidateFilters(ageMax: 28).matches(aged), isFalse);
      expect(const CandidateFilters(ageMin: 25, ageMax: 35).matches(aged),
          isTrue);
    });

    test('unknown age never excluded', () {
      const noAge = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(ageMin: 25, ageMax: 35).matches(noAge),
          isTrue);
    });

    test('activeCount counts an age window once', () {
      expect(const CandidateFilters(ageMin: 25, ageMax: 35).activeCount, 1);
      expect(const CandidateFilters(ageMin: 25).activeCount, 1);
    });
  });

  group('lifeStage set membership', () {
    const student = CandidateAttributes(fitScore: 50, lifeStage: 'student');

    test('membership passes, non-membership fails', () {
      expect(const CandidateFilters(lifeStage: {'student'}).matches(student),
          isTrue);
      expect(
          const CandidateFilters(lifeStage: {'family', 'senior'})
              .matches(student),
          isFalse);
    });

    test('unknown lifeStage never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(lifeStage: {'student'}).matches(unknown),
          isTrue);
    });

    test('empty set is inactive', () {
      expect(const CandidateFilters(lifeStage: {}).activeCount, 0);
      expect(const CandidateFilters(lifeStage: {'family'}).activeCount, 1);
    });
  });

  group('roomsMin (candidate declared)', () {
    const threeRooms = CandidateAttributes(fitScore: 50, rooms: 3);

    test('at/above floor passes, below fails', () {
      expect(const CandidateFilters(roomsMin: 3).matches(threeRooms), isTrue);
      expect(const CandidateFilters(roomsMin: 2.5).matches(threeRooms), isTrue);
      expect(const CandidateFilters(roomsMin: 4).matches(threeRooms), isFalse);
    });

    test('unknown rooms never excluded', () {
      const noRooms = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(roomsMin: 4).matches(noRooms), isTrue);
    });
  });

  group('recentOnly (liked in last 7 days)', () {
    const fresh = CandidateAttributes(fitScore: 50, likedInDays: 2);
    const stale = CandidateAttributes(fitScore: 50, likedInDays: 30);

    test('keeps fresh likes, drops old ones', () {
      expect(const CandidateFilters(recentOnly: true).matches(fresh), isTrue);
      expect(const CandidateFilters(recentOnly: true).matches(stale), isFalse);
      // Exactly at the 7-day boundary still counts as recent.
      const boundary = CandidateAttributes(fitScore: 50, likedInDays: 7);
      expect(
          const CandidateFilters(recentOnly: true).matches(boundary), isTrue);
    });

    test('unknown like-age always passes', () {
      const noDate = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(recentOnly: true).matches(noDate), isTrue);
    });

    test('activeCount counts recentOnly', () {
      expect(const CandidateFilters(recentOnly: true).activeCount, 1);
      expect(const CandidateFilters(recentOnly: false).activeCount, 0);
    });
  });

  group('affordability — minIncomeToRentRatio', () {
    const strong = CandidateAttributes(fitScore: 50, incomeToRentRatio: 3.2);
    const weak = CandidateAttributes(fitScore: 50, incomeToRentRatio: 1.8);

    test('floors known ratio', () {
      expect(const CandidateFilters(minIncomeToRentRatio: 2.5).matches(strong),
          isTrue);
      expect(const CandidateFilters(minIncomeToRentRatio: 2.5).matches(weak),
          isFalse);
      expect(const CandidateFilters(minIncomeToRentRatio: 3.0).matches(strong),
          isTrue);
    });

    test('unknown ratio never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(minIncomeToRentRatio: 3.0).matches(unknown),
          isTrue);
    });

    test('activeCount counts it once', () {
      expect(const CandidateFilters(minIncomeToRentRatio: 2.0).activeCount, 1);
    });
  });

  group('oleh (new immigrant)', () {
    const oleh = CandidateAttributes(fitScore: 50, isOleh: true);
    const notOleh = CandidateAttributes(fitScore: 50, isOleh: false);

    test('equality when known', () {
      expect(const CandidateFilters(oleh: true).matches(oleh), isTrue);
      expect(const CandidateFilters(oleh: true).matches(notOleh), isFalse);
    });

    test('unknown oleh never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(oleh: true).matches(unknown), isTrue);
    });

    test('activeCount counts it once', () {
      expect(const CandidateFilters(oleh: true).activeCount, 1);
    });
  });

  group('commute distance — maxCommuteKm', () {
    const near = CandidateAttributes(fitScore: 50, commuteKm: 4.2);
    const far = CandidateAttributes(fitScore: 50, commuteKm: 18.0);

    test('caps known distance', () {
      expect(const CandidateFilters(maxCommuteKm: 5).matches(near), isTrue);
      expect(const CandidateFilters(maxCommuteKm: 5).matches(far), isFalse);
      expect(const CandidateFilters(maxCommuteKm: 20).matches(far), isTrue);
    });

    test('unknown commute never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(maxCommuteKm: 5).matches(unknown), isTrue);
    });

    test('activeCount counts it once', () {
      expect(const CandidateFilters(maxCommuteKm: 10).activeCount, 1);
    });
  });

  group('smoker', () {
    const smokes = CandidateAttributes(fitScore: 50, smoker: true);
    const nonSmoker = CandidateAttributes(fitScore: 50, smoker: false);

    test('"non-smoker only" (smoker:false) excludes smokers', () {
      expect(const CandidateFilters(smoker: false).matches(smokes), isFalse);
      expect(const CandidateFilters(smoker: false).matches(nonSmoker), isTrue);
    });

    test('unknown smoker never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(smoker: false).matches(unknown), isTrue);
    });

    test('activeCount counts it once', () {
      expect(const CandidateFilters(smoker: false).activeCount, 1);
    });
  });

  group('hasGuarantor', () {
    const withGuarantor = CandidateAttributes(fitScore: 50, hasGuarantor: true);
    const without = CandidateAttributes(fitScore: 50, hasGuarantor: false);

    test('"with guarantor" (hasGuarantor:true) excludes those without', () {
      expect(const CandidateFilters(hasGuarantor: true).matches(withGuarantor),
          isTrue);
      expect(const CandidateFilters(hasGuarantor: true).matches(without),
          isFalse);
    });

    test('unknown guarantor never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(hasGuarantor: true).matches(unknown),
          isTrue);
    });

    test('activeCount counts it once', () {
      expect(const CandidateFilters(hasGuarantor: true).activeCount, 1);
    });
  });

  group('lease length — minLeaseMonths', () {
    const longLease = CandidateAttributes(fitScore: 50, leaseMonths: 24);
    const shortLease = CandidateAttributes(fitScore: 50, leaseMonths: 6);

    test('floors known lease length', () {
      expect(const CandidateFilters(minLeaseMonths: 12).matches(longLease),
          isTrue);
      expect(const CandidateFilters(minLeaseMonths: 12).matches(shortLease),
          isFalse);
      expect(const CandidateFilters(minLeaseMonths: 6).matches(shortLease),
          isTrue);
    });

    test('unknown lease length never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(minLeaseMonths: 24).matches(unknown),
          isTrue);
    });

    test('activeCount counts it once', () {
      expect(const CandidateFilters(minLeaseMonths: 12).activeCount, 1);
    });
  });

  group('incomeProofReady', () {
    const ready = CandidateAttributes(fitScore: 50, incomeProofReady: true);
    const notReady = CandidateAttributes(fitScore: 50, incomeProofReady: false);

    test('equality when known', () {
      expect(const CandidateFilters(incomeProofReady: true).matches(ready),
          isTrue);
      expect(const CandidateFilters(incomeProofReady: true).matches(notReady),
          isFalse);
    });

    test('unknown income-proof never excluded', () {
      const unknown = CandidateAttributes(fitScore: 50);
      expect(const CandidateFilters(incomeProofReady: true).matches(unknown),
          isTrue);
    });

    test('activeCount counts it once', () {
      expect(const CandidateFilters(incomeProofReady: true).activeCount, 1);
    });
  });

  group('copyWith — the 7 new candidate filters', () {
    test('sets and clears each new field', () {
      const base = CandidateFilters(
        minIncomeToRentRatio: 2.0,
        oleh: true,
        maxCommuteKm: 10,
        smoker: false,
        hasGuarantor: true,
        minLeaseMonths: 12,
        incomeProofReady: true,
      );
      // set
      expect(base.copyWith(minIncomeToRentRatio: 3.0).minIncomeToRentRatio, 3.0);
      expect(base.copyWith(oleh: false).oleh, isFalse);
      expect(base.copyWith(maxCommuteKm: 5).maxCommuteKm, 5);
      expect(base.copyWith(smoker: true).smoker, isTrue);
      expect(base.copyWith(hasGuarantor: false).hasGuarantor, isFalse);
      expect(base.copyWith(minLeaseMonths: 24).minLeaseMonths, 24);
      expect(base.copyWith(incomeProofReady: false).incomeProofReady, isFalse);
      // clear
      expect(
          base.copyWith(clearMinIncomeToRentRatio: true).minIncomeToRentRatio,
          isNull);
      expect(base.copyWith(clearOleh: true).oleh, isNull);
      expect(base.copyWith(clearMaxCommuteKm: true).maxCommuteKm, isNull);
      expect(base.copyWith(clearSmoker: true).smoker, isNull);
      expect(base.copyWith(clearHasGuarantor: true).hasGuarantor, isNull);
      expect(base.copyWith(clearMinLeaseMonths: true).minLeaseMonths, isNull);
      expect(base.copyWith(clearIncomeProofReady: true).incomeProofReady,
          isNull);
      // unrelated fields preserved through a clear
      expect(base.copyWith(clearOleh: true).minLeaseMonths, 12);
      expect(base.copyWith(clearSmoker: true).hasGuarantor, isTrue);
    });

    test('all seven active together count seven', () {
      const f = CandidateFilters(
        minIncomeToRentRatio: 2.0,
        oleh: true,
        maxCommuteKm: 10,
        smoker: false,
        hasGuarantor: true,
        minLeaseMonths: 12,
        incomeProofReady: true,
      );
      expect(f.activeCount, 7);
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

    test('sets and clears the new fields', () {
      const base = CandidateFilters(
        ageMin: 25,
        ageMax: 40,
        roomsMin: 3,
        recentOnly: true,
        lifeStage: {'student'},
      );
      expect(base.copyWith(ageMin: 30).ageMin, 30);
      expect(base.copyWith(clearAgeMin: true).ageMin, isNull);
      expect(base.copyWith(clearAgeMax: true).ageMax, isNull);
      expect(base.copyWith(clearRoomsMin: true).roomsMin, isNull);
      expect(base.copyWith(recentOnly: false).recentOnly, isFalse);
      expect(base.copyWith(lifeStage: {'family'}).lifeStage, {'family'});
      // Unrelated new field preserved through a clear.
      expect(base.copyWith(clearAgeMin: true).roomsMin, 3);
      expect(base.copyWith(clearAgeMin: true).recentOnly, isTrue);
    });
  });
}
