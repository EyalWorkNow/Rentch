import 'package:dating_app/core/finance/rental_tax.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('he'));

  group('RentalTax.assess boundaries', () {
    test('well below ceiling → fully exempt', () {
      final r = RentalTax.assess(3400, l10n);
      expect(r.category, TaxCategory.exempt);
      expect(r.isFullyExempt, isTrue);
      expect(r.exemptPortionMonthly, 3400);
      expect(r.taxablePortionMonthly, 0);
      expect(r.plainHebrewSummary, contains('פטור ממס'));
    });

    test('exactly at the ceiling → still fully exempt', () {
      final r = RentalTax.assess(kExemptCeilingMonthly, l10n); // 5654
      expect(r.category, TaxCategory.exempt);
      expect(r.exemptPortionMonthly, kExemptCeilingMonthly);
      expect(r.taxablePortionMonthly, 0);
    });

    test('one shekel above the ceiling → partial exemption', () {
      final r = RentalTax.assess(kExemptCeilingMonthly + 1, l10n); // 5655
      expect(r.category, TaxCategory.partialExemption);
      // Exempt portion shrinks ₪1 for the ₪1 over the ceiling.
      expect(r.exemptPortionMonthly, kExemptCeilingMonthly - 1); // 5653
      expect(r.taxablePortionMonthly, 2);
    });

    test('mid partial band → exempt portion shrinks ₪1 per ₪1 over', () {
      const rent = 7000.0;
      final r = RentalTax.assess(rent, l10n);
      expect(r.category, TaxCategory.partialExemption);
      final over = rent - kExemptCeilingMonthly; // 1346
      expect(r.exemptPortionMonthly, kExemptCeilingMonthly - over); // 4308
      expect(r.taxablePortionMonthly, rent - (kExemptCeilingMonthly - over));
    });

    test('at the partial ceiling → exemption fully eroded, 10% track', () {
      final r = RentalTax.assess(kPartialCeilingMonthly, l10n); // 11308
      expect(r.category, TaxCategory.tenPercentBetter);
      expect(r.exemptPortionMonthly, 0);
      expect(r.taxablePortionMonthly, kPartialCeilingMonthly);
    });

    test('well above partial ceiling → 10% track', () {
      final r = RentalTax.assess(15000, l10n);
      expect(r.category, TaxCategory.tenPercentBetter);
      expect(r.exemptPortionMonthly, 0);
    });
  });

  group('RentalTax.assess 10% track', () {
    test('10% monthly is exactly a tenth of gross rent', () {
      final r = RentalTax.assess(8000, l10n);
      expect(r.tenPercentMonthly, 800);
    });

    test('annual report duty only when annual gross > ₪375,000', () {
      // 31,250/mo * 12 = 375,000 → not over → no duty.
      expect(RentalTax.assess(31250, l10n).requiresAnnualReport, isFalse);
      // Just above → duty kicks in.
      expect(RentalTax.assess(31251, l10n).requiresAnnualReport, isTrue);
    });
  });

  group('RentalTax.assess edge cases', () {
    test('zero rent → exempt, no tax', () {
      final r = RentalTax.assess(0, l10n);
      expect(r.category, TaxCategory.exempt);
      expect(r.tenPercentMonthly, 0);
    });

    test('negative rent is clamped to zero', () {
      final r = RentalTax.assess(-500, l10n);
      expect(r.monthlyRent, 0);
      expect(r.category, TaxCategory.exempt);
    });

    test('constants carried on the result', () {
      final r = RentalTax.assess(4000, l10n);
      expect(r.exemptCeiling, kExemptCeilingMonthly);
      expect(r.partialCeiling, kPartialCeilingMonthly);
    });
  });
}
