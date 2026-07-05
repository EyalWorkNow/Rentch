// ════════════════════════════════════════════════════════════════════════════
// MONTHLY COST — the TRUE monthly cost of a listing, not just the rent
// ════════════════════════════════════════════════════════════════════════════
//
// A listing that fits the budget on rent can blow it once ARNONA (municipal tax,
// billed ₪/m²/year, varies a lot by city) and VAAD BAYIT (building maintenance)
// are added. This pure, deterministic helper estimates the real ₪/month so the
// algorithm — and the "why I picked this" — can reason about total cost.
//
// Intentionally coarse and clearly approximate (every label is prefixed "כ-"/"~"):
// arnona uses a per-city ₪/m²/year table (residential ballpark), vaad a simple
// size curve. It is NOT a billing engine; utilities/gas are excluded (usage-based)
// and noted as such.
// ════════════════════════════════════════════════════════════════════════════

/// A coarse, deterministic breakdown of a listing's true monthly cost.
class MonthlyCostEstimate {
  const MonthlyCostEstimate({
    required this.rent,
    required this.arnona,
    required this.vaad,
    required this.total,
    required this.plainHebrewLabel,
  });

  final int rent;
  final int arnona; // municipal tax, monthly (annual ₪/m² ÷ 12 × size)
  final int vaad; // building maintenance, monthly
  final int total; // rent + arnona + vaad (before usage-based utilities)

  /// e.g. `כ-₪7,450/חודש · כולל ארנונה ~₪380 וועד ~₪260`.
  final String plainHebrewLabel;
}

class MonthlyCost {
  const MonthlyCost._();

  // Residential arnona, annual ₪/m² — ballpark municipal rates (mid-zone). Coarse
  // on purpose; matched by Hebrew city-name substring.
  static const Map<String, double> _arnonaPerSqmYear = {
    'ירושלים': 72,
    'תל אביב': 52,
    'רמת גן': 55,
    'גבעתיים': 55,
    'הרצליה': 56,
    'רעננה': 50,
    'כפר סבא': 48,
    'חיפה': 55,
    'ראשון': 48,
    'פתח תקווה': 50,
    'נתניה': 45,
    'אשדוד': 42,
    'אשקלון': 40,
    'באר שבע': 40,
    'בני ברק': 40,
    'חולון': 48,
    'בת ים': 46,
    'מודיעין': 46,
  };
  static const double _arnonaDefaultPerSqmYear = 48;

  /// Estimate the true monthly cost. Returns null when [sizeM2] is unusable
  /// (0/negative) — the caller degrades to rent-only, unchanged.
  static MonthlyCostEstimate? estimate({
    required int rent,
    required int sizeM2,
    required String city,
  }) {
    if (sizeM2 <= 0 || rent <= 0) return null;

    final perSqmYear = _rateFor(city);
    final arnona = (perSqmYear * sizeM2 / 12).round();
    // Vaad bayit: a small base + a per-m² curve (bigger/newer buildings cost more).
    final vaad = (100 + sizeM2 * 2).round();
    final total = rent + arnona + vaad;

    return MonthlyCostEstimate(
      rent: rent,
      arnona: arnona,
      vaad: vaad,
      total: total,
      plainHebrewLabel: 'כ-₪${_thousands(total)}/חודש · כולל ארנונה ~₪'
          '${_thousands(arnona)} וועד ~₪${_thousands(vaad)}',
    );
  }

  static double _rateFor(String city) {
    for (final e in _arnonaPerSqmYear.entries) {
      if (city.contains(e.key)) return e.value;
    }
    return _arnonaDefaultPerSqmYear;
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

// ponytail: coarse estimator — swap the arnona table for live municipal rates only
// if users complain it's off. Self-check:
void main() {
  final e = MonthlyCost.estimate(rent: 6000, sizeM2: 80, city: 'תל אביב-יפו')!;
  assert(e.total > e.rent, 'total must exceed rent');
  assert(e.arnona > 0 && e.vaad > 0);
  assert(e.total == e.rent + e.arnona + e.vaad);
  // 52 ₪/m²/yr × 80 / 12 ≈ 347 arnona; vaad 100+160=260 → total ≈ 6607
  assert(e.total > 6500 && e.total < 6700, 'got ${e.total}');
  // ignore: avoid_print
  print('ok: ${e.plainHebrewLabel}');
}
