// Israeli residential rental-income tax helper.
//
// Built for older, non-technical landlords who just want a single clear answer:
// "do I owe / report anything on my rent?".
//
// All figures are 2026 values. They live as named constants so a future agent
// can bump them in one place when the Tax Authority publishes new numbers.

import 'package:dating_app/l10n/app_localizations.dart';

/// 2026 monthly residential-rent tax-exemption ceiling (₪). Rent at or below
/// this is fully exempt — nothing to report.
const double kExemptCeilingMonthly = 5654.0;

/// Top of the "shrinking" partial-exemption band (₪/month). Between the ceiling
/// and this figure the exempt amount shrinks ₪1 for every ₪1 over the ceiling.
/// Above this, none of the rent is exempt under the exemption track.
const double kPartialCeilingMonthly = 11308.0;

/// Flat rate of the alternative §122 "10% track" on GROSS rent.
const double kTenPercentRate = 0.10;

/// Annual gross-rent threshold (₪) above which the 10% track carries an
/// annual-report duty.
const double kTenPercentAnnualReportThreshold = 375000.0;

/// Which bucket a given monthly rent falls into.
enum TaxCategory {
  /// Rent ≤ ceiling → fully exempt, nothing to report.
  exempt,

  /// Rent in the shrinking band → part of the rent is still exempt.
  partialExemption,

  /// Above the band → the simple 10% track is the easy/usually-cheaper choice.
  tenPercentBetter,

  /// Fallback taxable bucket (kept for completeness).
  taxable,
}

/// Deterministic result of [RentalTax.assess].
class RentalTaxResult {
  const RentalTaxResult({
    required this.monthlyRent,
    required this.category,
    required this.exemptCeiling,
    required this.partialCeiling,
    required this.tenPercentMonthly,
    required this.exemptPortionMonthly,
    required this.taxablePortionMonthly,
    required this.requiresAnnualReport,
    required this.plainHebrewSummary,
  });

  /// The monthly rent that was assessed (₪).
  final double monthlyRent;

  /// The bucket this rent falls into.
  final TaxCategory category;

  /// The exemption ceiling used (₪/month) — i.e. [kExemptCeilingMonthly].
  final double exemptCeiling;

  /// The top of the partial band used (₪/month) — i.e. [kPartialCeilingMonthly].
  final double partialCeiling;

  /// What the simple §122 track would cost per month (10% of gross rent, ₪).
  final double tenPercentMonthly;

  /// How much of the monthly rent stays exempt under the exemption track (₪).
  final double exemptPortionMonthly;

  /// How much of the monthly rent is taxable under the exemption track (₪).
  final double taxablePortionMonthly;

  /// True when the 10% track's annual gross rent crosses the report threshold.
  final bool requiresAnnualReport;

  /// A ready-to-show, jargon-light Hebrew sentence summarising the verdict.
  final String plainHebrewSummary;

  /// True only when nothing at all needs reporting.
  bool get isFullyExempt => category == TaxCategory.exempt;
}

/// Pure, deterministic rental-tax assessment.
class RentalTax {
  const RentalTax._();

  /// Assess a [monthlyRent] (₪/month). Negative input is clamped to 0.
  static RentalTaxResult assess(double monthlyRent, AppLocalizations l10n) {
    final double rent = monthlyRent < 0 ? 0 : monthlyRent;

    final double tenPercentMonthly = rent * kTenPercentRate;
    final bool requiresAnnualReport =
        rent * 12 > kTenPercentAnnualReportThreshold;

    // Exemption track: the exempt amount shrinks ₪1 per ₪1 over the ceiling.
    final double overCeiling = rent - kExemptCeilingMonthly;
    double exemptPortion;
    if (overCeiling <= 0) {
      exemptPortion = rent; // all of it is exempt
    } else {
      exemptPortion = kExemptCeilingMonthly - overCeiling; // shrinking band
      if (exemptPortion < 0) exemptPortion = 0; // fully eroded past 11,308
    }
    final double taxablePortion = rent - exemptPortion;

    final TaxCategory category;
    if (rent <= kExemptCeilingMonthly) {
      category = TaxCategory.exempt;
    } else if (rent < kPartialCeilingMonthly) {
      category = TaxCategory.partialExemption;
    } else {
      category = TaxCategory.tenPercentBetter;
    }

    final String summary = _summaryFor(
      l10n: l10n,
      category: category,
      rent: rent,
      tenPercentMonthly: tenPercentMonthly,
      exemptPortion: exemptPortion,
    );

    return RentalTaxResult(
      monthlyRent: rent,
      category: category,
      exemptCeiling: kExemptCeilingMonthly,
      partialCeiling: kPartialCeilingMonthly,
      tenPercentMonthly: tenPercentMonthly,
      exemptPortionMonthly: exemptPortion,
      taxablePortionMonthly: taxablePortion,
      requiresAnnualReport: requiresAnnualReport,
      plainHebrewSummary: summary,
    );
  }

  static String _summaryFor({
    required AppLocalizations l10n,
    required TaxCategory category,
    required double rent,
    required double tenPercentMonthly,
    required double exemptPortion,
  }) {
    final String rentStr = _shekel(rent);
    switch (category) {
      case TaxCategory.exempt:
        return l10n.rentalTax68d523ba(rentStr);
      case TaxCategory.partialExemption:
        return l10n.rentalTax9b398d34(_shekel(kExemptCeilingMonthly)) +
            l10n.rentalTaxDa3d1e79 +
            l10n.rentalTaxA2791ae8(_shekel(tenPercentMonthly));
      case TaxCategory.tenPercentBetter:
      case TaxCategory.taxable:
        return l10n.rentalTax9b398d34(_shekel(kExemptCeilingMonthly)) +
            l10n.rentalTaxDaaf39c6(_shekel(tenPercentMonthly));
    }
  }

  /// Formats an amount as `₪1,234` (no decimals, thousands separators).
  static String _shekel(double amount) {
    final int rounded = amount.round();
    final String digits = rounded.abs().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '₪${rounded < 0 ? '-' : ''}$out';
  }
}
