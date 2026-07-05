// ════════════════════════════════════════════════════════════════════════════
// RENTAL YIELD — gross annual yield for a FOR-SALE listing
// ════════════════════════════════════════════════════════════════════════════
//
// For buyers-as-investors, the deciding number isn't the sticker price — it's the
// yield: what annual rent the flat would earn vs what it costs. This pure,
// deterministic helper estimates the rent a sale listing could fetch (from a
// per-city ₪/m²/month benchmark) and returns the gross annual yield %.
//
// Coarse on purpose (bundled rent table, ballpark), labels prefixed "כ-"/"~".
// Gross only — excludes arnona/vaad/vacancy/management, which a real investor
// nets out separately.
// ════════════════════════════════════════════════════════════════════════════

/// A coarse gross-yield estimate for a for-sale listing.
class RentalYieldEstimate {
  const RentalYieldEstimate({
    required this.estMonthlyRent,
    required this.grossYieldPct,
    required this.plainHebrewLabel,
  });

  final int estMonthlyRent; // rent the flat could plausibly earn, ₪/month
  final double grossYieldPct; // annual gross yield, %
  final String plainHebrewLabel; // e.g. `תשואה ברוטו ~3.1% (שכ״ד ~₪5,700/ח׳)`
}

class RentalYield {
  const RentalYield._();

  // Ballpark residential asking rent, ₪/m²/month, matched by city substring.
  static const Map<String, double> _rentPerSqmMonth = {
    'תל אביב': 95,
    'גבעתיים': 80,
    'רמת גן': 78,
    'הרצליה': 85,
    'רעננה': 68,
    'כפר סבא': 62,
    'ירושלים': 65,
    'חיפה': 48,
    'ראשון': 56,
    'פתח תקווה': 58,
    'נתניה': 55,
    'אשדוד': 45,
    'אשקלון': 42,
    'באר שבע': 42,
    'בני ברק': 58,
    'חולון': 56,
    'בת ים': 55,
    'מודיעין': 52,
  };
  static const double _rentDefaultPerSqmMonth = 55;

  /// Estimate gross yield for a sale listing. Returns null when it isn't a usable
  /// sale (missing size or an implausibly low price that looks like a rent).
  static RentalYieldEstimate? estimate({
    required int salePrice,
    required int sizeM2,
    required String city,
  }) {
    // A "sale" under ₪200k is almost certainly a mislabelled rent → skip.
    if (sizeM2 <= 0 || salePrice < 200000) return null;

    final rentPerSqm = _rateFor(city);
    final estMonthlyRent = (rentPerSqm * sizeM2).round();
    final grossYield = estMonthlyRent * 12 / salePrice * 100;

    return RentalYieldEstimate(
      estMonthlyRent: estMonthlyRent,
      grossYieldPct: grossYield,
      plainHebrewLabel: 'תשואה ברוטו ~${grossYield.toStringAsFixed(1)}% '
          '(שכ״ד מוערך ~₪${_thousands(estMonthlyRent)}/ח׳)',
    );
  }

  static double _rateFor(String city) {
    for (final e in _rentPerSqmMonth.entries) {
      if (city.contains(e.key)) return e.value;
    }
    return _rentDefaultPerSqmMonth;
  }

  static String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

// ponytail: bundled rent table — derive from live catalogue rentals only if it
// proves off. Self-check:
void main() {
  final e = RentalYield.estimate(salePrice: 2200000, sizeM2: 80, city: 'תל אביב-יפו')!;
  // 95 ₪/m²/mo × 80 = 7600 rent → 91,200/yr / 2.2M ≈ 4.1%
  assert(e.estMonthlyRent == 7600, 'got ${e.estMonthlyRent}');
  assert(e.grossYieldPct > 4.0 && e.grossYieldPct < 4.3, 'got ${e.grossYieldPct}');
  assert(RentalYield.estimate(salePrice: 6000, sizeM2: 80, city: 'חיפה') == null,
      'rent-priced listing must be rejected');
  // ignore: avoid_print
  print('ok: ${e.plainHebrewLabel}');
}
