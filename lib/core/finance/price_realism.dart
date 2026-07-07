import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/data/models/rental_models.dart';

/// Verdict on whether a listing's price is realistic for its city + size.
enum PriceFlag {
  ok,
  tooLow, // suspiciously cheap — a typo, or lead-bait ("₪1,300 for a 430m² TLV house")
  tooHigh, // suspiciously expensive
  unknown, // no market prior for this city / missing price or size
}

/// Anti-bait price sanity check.
///
/// Some owners post an absurd price (₪1,300/mo for a 430m² Tel Aviv house →
/// ₪3/m² vs a ~₪70/m² market) purely to harvest leads. We compare the listing's
/// price-per-m² against the government market prior for its city, and flag gross
/// outliers. Used to (a) warn the owner on upload and (b) stop a fake from topping
/// results on a bogus "amazing value".
class PriceRealism {
  const PriceRealism._();

  static ({
    PriceFlag flag,
    int fair, // market-fair price for this size+city
    int expectedLow,
    int expectedHigh,
    double ratio, // price / fair
  }) check(RentalProperty p) {
    const unknown = (
      flag: PriceFlag.unknown,
      fair: 0,
      expectedLow: 0,
      expectedHigh: 0,
      ratio: 1.0
    );
    if (p.price <= 0 || p.sizeM2 <= 0 || p.city.trim().isEmpty) return unknown;

    final isSale = p.transactionType == PropertyTransactionType.sale;
    final prior = isSale
        ? GovData.instance.salePerSqm(p.city)
        : GovData.instance.rentPerSqm(p.city);
    if (prior == null || prior <= 0) return unknown;

    final fair = prior * p.sizeM2;
    final ratio = p.price / fair;
    // Generous band around the fair price (markets vary a lot by street/floor);
    // only GROSS outliers are flagged.
    final lowMul = isSale ? 0.55 : 0.55;
    final highMul = isSale ? 2.2 : 2.0;
    final flag = ratio < (isSale ? 0.35 : 0.4)
        ? PriceFlag.tooLow
        : ratio > (isSale ? 3.0 : 2.8)
            ? PriceFlag.tooHigh
            : PriceFlag.ok;
    return (
      flag: flag,
      fair: fair.round(),
      expectedLow: (fair * lowMul).round(),
      expectedHigh: (fair * highMul).round(),
      ratio: ratio,
    );
  }

  /// 0..1 "trust the price" multiplier — 1 for a realistic price, tapering to a
  /// floor for gross outliers, so a fake ultra-cheap flat can't win on value.
  static double priceTrust(RentalProperty p) {
    final v = check(p);
    switch (v.flag) {
      case PriceFlag.tooLow:
        // The more absurd the discount, the lower the trust.
        return (v.ratio / 0.4).clamp(0.15, 1.0);
      case PriceFlag.tooHigh:
        return 0.6;
      case PriceFlag.ok:
      case PriceFlag.unknown:
        return 1.0;
    }
  }
}
