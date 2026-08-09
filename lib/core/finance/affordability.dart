// Tenant affordability + true move-in cost calculator — pure Dart, no Flutter
// imports. Built so apartment-seekers (including new immigrants who don't yet
// know Israeli norms) aren't blindsided by stacked move-in costs.
//
// All figures are named constants so a future agent can bump them in one place
// when the law or norms change. The deposit cap is NOT reimplemented here — it
// reuses [maxLegalDepositNis] from the rental_contract model so there is a
// single source of truth for the 2017 חוק שכירות הוגנת cap.

import 'package:dating_app/data/models/rental_contract.dart';

/// Comfort norm: rent should sit around or below this share of gross monthly
/// income. Above it, a tenant is "stretched".
const double kRentToIncomeComfort = 0.30;

/// Above this share of income the burden is considered high.
const double kRentToIncomeHigh = 0.40;

/// Israeli broker (תיווך) fee, owed ONLY when the tenant signed a brokerage
/// agreement: one month's rent + VAT. VAT is 18% as of Jan 2025.
const double kBrokerVat = 0.18;

/// One month's rent + VAT, as a multiplier on the monthly rent.
const double kBrokerFeeMultiplier = 1.0 + kBrokerVat; // 1.18

/// How comfortably the rent sits against the tenant's income.
enum RentBand {
  /// rent ≤ 30% of income.
  comfortable,

  /// 30% < rent ≤ 40% of income.
  stretched,

  /// rent > 40% of income.
  high,

  /// Income wasn't provided — ratio can't be evaluated.
  unknown,
}

/// Which up-front move-in cost a [CostLineItem] represents. The display label
/// is localized at the UI layer (this file is pure Dart, no Flutter/l10n
/// imports) — see property_detail_screen.dart's `_lineItemLabel`.
enum CostLineKind { firstMonthRent, deposit, brokerFee }

/// One labelled component of the up-front move-in total.
class CostLineItem {
  const CostLineItem({required this.kind, required this.amount});

  /// Which cost this line item represents.
  final CostLineKind kind;

  /// Amount in ₪ (rounded to whole shekels).
  final int amount;
}

/// Deterministic result of [Affordability.assess]. Never throws, never blocks —
/// income is optional and missing/zero income simply yields [RentBand.unknown].
class AffordabilityResult {
  const AffordabilityResult({
    required this.monthlyRent,
    required this.monthlyIncome,
    required this.termMonths,
    required this.tenantPaysBroker,
    required this.rentToIncome,
    required this.band,
    required this.legalDepositCap,
    required this.firstMonthRent,
    required this.brokerFee,
    required this.moveInTotal,
    required this.lineItems,
    required this.plainHebrewSummary,
  });

  final int monthlyRent;

  /// Gross monthly income in ₪, or null if not supplied.
  final int? monthlyIncome;
  final int termMonths;
  final bool tenantPaysBroker;

  /// rent ÷ income (e.g. 0.32), or null when income is unknown.
  final double? rentToIncome;
  final RentBand band;

  /// The legal deposit cap for this rent/term (reused from rental_contract).
  final int legalDepositCap;
  final int firstMonthRent;

  /// Broker fee (rent × 1.18) if the tenant pays it, else 0.
  final int brokerFee;

  /// Sum of all line items — what the tenant needs on day one.
  final int moveInTotal;
  final List<CostLineItem> lineItems;

  /// Ready-to-show Hebrew summary covering the ratio band and the move-in total.
  final String plainHebrewSummary;

  /// Convenience: rent-to-income as a whole-percent int (e.g. 32), or null.
  int? get rentToIncomePercent =>
      rentToIncome == null ? null : (rentToIncome! * 100).round();
}

/// Pure affordability + move-in cost calculator.
class Affordability {
  const Affordability._();

  /// Assesses a tenant's affordability for a property.
  ///
  /// - [monthlyRent]: the listing's monthly rent in ₪.
  /// - [monthlyIncome]: gross monthly income in ₪. Optional — when null or ≤ 0
  ///   the ratio is skipped and [RentBand.unknown] is returned.
  /// - [termMonths]: lease length, used only for the legal deposit cap.
  /// - [tenantPaysBroker]: true only when the tenant signed a brokerage
  ///   agreement; then a one-month-rent + VAT(18%) broker fee is added.
  static AffordabilityResult assess({
    required int monthlyRent,
    int? monthlyIncome,
    int termMonths = 12,
    bool tenantPaysBroker = false,
  }) {
    final rent = monthlyRent < 0 ? 0 : monthlyRent;

    // Ratio + band (only when income is usable).
    double? ratio;
    RentBand band = RentBand.unknown;
    if (monthlyIncome != null && monthlyIncome > 0) {
      ratio = rent / monthlyIncome;
      if (ratio <= kRentToIncomeComfort) {
        band = RentBand.comfortable;
      } else if (ratio <= kRentToIncomeHigh) {
        band = RentBand.stretched;
      } else {
        band = RentBand.high;
      }
    }

    // Move-in total = capped legal deposit + first month + optional broker fee.
    final depositCap = maxLegalDepositNis(
      monthlyRent: rent,
      termMonths: termMonths,
    );
    final brokerFee =
        tenantPaysBroker ? (rent * kBrokerFeeMultiplier).round() : 0;

    final items = <CostLineItem>[
      CostLineItem(kind: CostLineKind.firstMonthRent, amount: rent),
      CostLineItem(kind: CostLineKind.deposit, amount: depositCap),
      if (tenantPaysBroker)
        CostLineItem(kind: CostLineKind.brokerFee, amount: brokerFee),
    ];
    final total = items.fold<int>(0, (sum, i) => sum + i.amount);

    return AffordabilityResult(
      monthlyRent: rent,
      monthlyIncome: monthlyIncome,
      termMonths: termMonths,
      tenantPaysBroker: tenantPaysBroker,
      rentToIncome: ratio,
      band: band,
      legalDepositCap: depositCap,
      firstMonthRent: rent,
      brokerFee: brokerFee,
      moveInTotal: total,
      lineItems: items,
      plainHebrewSummary: _summary(
        band: band,
        ratioPercent: ratio == null ? null : (ratio * 100).round(),
        total: total,
      ),
    );
  }

  static String _summary({
    required RentBand band,
    required int? ratioPercent,
    required int total,
  }) {
    final moveIn = 'עלות כניסה משוערת: ₪$total (מזומן שצריך ביום החתימה).';
    switch (band) {
      case RentBand.comfortable:
        return 'שכר הדירה הוא כ-$ratioPercent% מההכנסה — בתחום הנוח (עד 30%). '
            '$moveIn';
      case RentBand.stretched:
        return 'שכר הדירה הוא כ-$ratioPercent% מההכנסה — מתיחה תקציבית '
            '(30%–40%). שווה לבדוק שנשאר מספיק לשאר ההוצאות. $moveIn';
      case RentBand.high:
        return 'שכר הדירה הוא כ-$ratioPercent% מההכנסה — נטל גבוה (מעל 40%). '
            'מומלץ לשקול נכס זול יותר. $moveIn';
      case RentBand.unknown:
        return 'הוסיפו הכנסה חודשית כדי לראות אם השכירות נוחה לכם. $moveIn';
    }
  }
}
