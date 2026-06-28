import 'package:dating_app/core/finance/affordability.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Affordability ratio bands', () {
    test('comfortable when rent <= 30% of income', () {
      final r = Affordability.assess(monthlyRent: 3000, monthlyIncome: 12000);
      expect(r.rentToIncome, closeTo(0.25, 1e-9));
      expect(r.rentToIncomePercent, 25);
      expect(r.band, RentBand.comfortable);
    });

    test('boundary: exactly 30% is still comfortable', () {
      final r = Affordability.assess(monthlyRent: 3000, monthlyIncome: 10000);
      expect(r.band, RentBand.comfortable);
    });

    test('stretched between 30% and 40%', () {
      final r = Affordability.assess(monthlyRent: 3500, monthlyIncome: 10000);
      expect(r.band, RentBand.stretched);
    });

    test('boundary: exactly 40% is still stretched', () {
      final r = Affordability.assess(monthlyRent: 4000, monthlyIncome: 10000);
      expect(r.band, RentBand.stretched);
    });

    test('high above 40%', () {
      final r = Affordability.assess(monthlyRent: 5000, monthlyIncome: 10000);
      expect(r.band, RentBand.high);
    });

    test('unknown when income missing or zero', () {
      final noIncome = Affordability.assess(monthlyRent: 5000);
      expect(noIncome.band, RentBand.unknown);
      expect(noIncome.rentToIncome, isNull);
      expect(noIncome.rentToIncomePercent, isNull);

      final zero = Affordability.assess(monthlyRent: 5000, monthlyIncome: 0);
      expect(zero.band, RentBand.unknown);
    });
  });

  group('Move-in total', () {
    test('without broker = deposit cap + first month', () {
      final r = Affordability.assess(monthlyRent: 5000, termMonths: 12);
      final cap = maxLegalDepositNis(monthlyRent: 5000, termMonths: 12);
      expect(r.legalDepositCap, cap);
      expect(r.firstMonthRent, 5000);
      expect(r.brokerFee, 0);
      expect(r.moveInTotal, cap + 5000);
      // No broker line item when tenant doesn't pay broker.
      expect(r.lineItems.length, 2);
    });

    test('with broker adds one month + VAT 18%', () {
      final r = Affordability.assess(
        monthlyRent: 5000,
        termMonths: 12,
        tenantPaysBroker: true,
      );
      final cap = maxLegalDepositNis(monthlyRent: 5000, termMonths: 12);
      const broker = 5900; // 5000 * 1.18
      expect(r.brokerFee, broker);
      expect(r.moveInTotal, cap + 5000 + broker);
      expect(r.lineItems.length, 3);
      expect(r.lineItems.last.amount, broker);
    });

    test('line items sum to move-in total', () {
      final r = Affordability.assess(
        monthlyRent: 4200,
        termMonths: 12,
        tenantPaysBroker: true,
      );
      final sum = r.lineItems.fold<int>(0, (a, i) => a + i.amount);
      expect(sum, r.moveInTotal);
    });
  });

  group('Deposit cap reuse', () {
    test('short term: cap = 1/3 of lease-term rent (lower of the two)', () {
      // 5000 * 6 / 3 = 10000  vs  3 months = 15000 -> lower is 10000.
      final r = Affordability.assess(monthlyRent: 5000, termMonths: 6);
      expect(r.legalDepositCap, 10000);
      expect(r.legalDepositCap,
          maxLegalDepositNis(monthlyRent: 5000, termMonths: 6));
    });

    test('long term: cap = 3 months rent (lower of the two)', () {
      // 5000 * 24 / 3 = 40000  vs  3 months = 15000 -> lower is 15000.
      final r = Affordability.assess(monthlyRent: 5000, termMonths: 24);
      expect(r.legalDepositCap, 15000);
    });

    test('12-month term: 1/3 (=4 months) vs 3 months -> 3 months wins', () {
      final r = Affordability.assess(monthlyRent: 5000, termMonths: 12);
      expect(r.legalDepositCap, 15000);
    });
  });

  group('Robustness', () {
    test('summary is non-empty for every band', () {
      expect(Affordability.assess(monthlyRent: 3000, monthlyIncome: 12000)
          .plainHebrewSummary, isNotEmpty);
      expect(Affordability.assess(monthlyRent: 5000)
          .plainHebrewSummary, isNotEmpty);
    });

    test('never throws on zero/negative rent', () {
      final r = Affordability.assess(monthlyRent: -100, monthlyIncome: 5000);
      expect(r.monthlyRent, 0);
      expect(r.moveInTotal, greaterThanOrEqualTo(0));
    });
  });
}
