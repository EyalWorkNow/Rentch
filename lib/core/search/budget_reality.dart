import 'dart:math' as math;

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart' show TransactionTypeFilter;

/// REALITY-CHECK: is what the seeker asked for actually attainable in that city
/// at that budget? A good agent notices "4 חדרים בתל אביב עד 3000" is a fantasy
/// BEFORE searching, and guides — "raise the budget, or try a nearby city" —
/// instead of returning a wall of mismatched, low-fit flats.
///
/// Pure + on-device: it compares the stated budget to the real CBS/market ₪/m²
/// prior for the city (× a typical flat size for the requested rooms). Degrades
/// silently to `feasible` whenever the data or the query is too thin to judge.
enum RealityVerdict { feasible, tight, unrealistic }

class BudgetReality {
  const BudgetReality(
    this.verdict, {
    this.expected,
    this.nearbyCity,
    this.message = '',
  });

  final RealityVerdict verdict;
  final int? expected; // the realistic ₪ for this ask (rounded), or null
  final String? nearbyCity; // a nearby city where the budget DOES work, or null
  final String message; // Hebrew guidance ('' when feasible)

  bool get needsGuidance => verdict != RealityVerdict.feasible;
}

class BudgetRealityCheck {
  const BudgetRealityCheck._();

  // A typical flat is ~25 m² per room (a 3-room ≈ 75 m²).
  static const double _sqmPerRoom = 25.0;
  // Below this fraction of the market price, the ask is a fantasy; between this
  // and _tightAt it's a stretch; at/above _tightAt it's feasible.
  static const double _unrealisticAt = 0.60;
  static const double _tightAt = 0.85;

  /// Assess [q] against the market. [gov] defaults to the loaded singleton.
  static BudgetReality assess(SearchQuery q, {GovData? gov}) {
    final g = gov ?? GovData.instance;
    final city = q.city?.trim();
    final maxP = q.maxPrice;
    if (city == null || city.isEmpty || maxP == null || maxP <= 0) {
      return const BudgetReality(RealityVerdict.feasible);
    }
    final sale = q.transactionType == TransactionTypeFilter.sale;
    final perSqm = sale ? g.salePerSqm(city) : g.rentPerSqm(city);
    if (perSqm == null || perSqm <= 0) {
      return const BudgetReality(RealityVerdict.feasible);
    }
    final rooms = (q.minRooms ?? q.maxRooms ?? 3).clamp(1.0, 8.0);
    final expected = perSqm * rooms * _sqmPerRoom;
    if (expected <= 0) return const BudgetReality(RealityVerdict.feasible);

    final ratio = maxP / expected;
    if (ratio >= _tightAt) {
      return BudgetReality(RealityVerdict.feasible, expected: expected.round());
    }
    final verdict =
        ratio < _unrealisticAt ? RealityVerdict.unrealistic : RealityVerdict.tight;
    final nearby = _cheaperNearby(g, city, rooms, maxP, sale);
    return BudgetReality(
      verdict,
      expected: expected.round(),
      nearbyCity: nearby,
      message: _message(verdict, city, rooms.round(), sale, expected.round(),
          maxP, nearby),
    );
  }

  /// The nearest city (≤25 km) where the same ask DOES fit the budget.
  static String? _cheaperNearby(
      GovData g, String city, double rooms, int budget, bool sale) {
    final loc = g.localityByName(city);
    if (loc == null || loc.lat.abs() < 0.1) return null;
    String? best;
    var bestKm = 25.0;
    for (final rec in g.localities) {
      if (rec.name == city || rec.lat.abs() < 0.1) continue;
      final perSqm = sale ? g.salePerSqm(rec.name) : g.rentPerSqm(rec.name);
      if (perSqm == null || perSqm <= 0) continue;
      final expected = perSqm * rooms * _sqmPerRoom;
      if (budget < expected * _tightAt) continue; // still not feasible there
      final km = _km(loc.lat, loc.lon, rec.lat, rec.lon);
      if (km < bestKm) {
        bestKm = km;
        best = rec.name;
      }
    }
    return best;
  }

  static String _money(int v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '₪${m == m.roundToDouble() ? m.round() : m.toStringAsFixed(1)} מיליון';
    }
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '₪$b';
  }

  // Friendlier display: "תל אביב - יפו" → "תל אביב", "פרדס חנה-כרכור" stays.
  static String _cityName(String c) {
    final i = c.indexOf(' - ');
    return i > 0 ? c.substring(0, i).trim() : c;
  }

  static String _message(RealityVerdict v, String cityRaw, int rooms, bool sale,
      int expected, int budget, String? nearbyRaw) {
    final city = _cityName(cityRaw);
    final nearby = nearbyRaw == null ? null : _cityName(nearbyRaw);
    final what = '$rooms חדרים ב$city';
    final verb = sale ? 'לקנות' : 'לשכור';
    if (v == RealityVerdict.unrealistic) {
      final base =
          '$verb $what ב${_money(budget)} כמעט לא קיים — המחיר הריאלי הוא בערך ${_money(expected)}.';
      return nearby != null
          ? '$base אפשר להעלות תקציב, או שאבדוק לך ב$nearby — שם התקציב הזה עובד יפה. 🙂'
          : '$base שווה להעלות קצת את התקציב כדי שאמצא לך אופציות אמיתיות.';
    }
    // tight
    final base = '$what ב${_money(budget)} זה על הגבול — יש, אבל מעט וזה נחטף מהר.';
    return nearby != null
        ? '$base אם תרצה יותר בחירה, קצת יותר תקציב או $nearby הסמוכה יפתחו הרבה. 🙂'
        : '$base קצת יותר תקציב יפתח הרבה יותר אופציות.';
  }

  static double _km(double aLat, double aLon, double bLat, double bLon) {
    const r = 6371.0;
    final dLat = (bLat - aLat) * math.pi / 180;
    final dLon = (bLon - aLon) * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(aLat * math.pi / 180) *
            math.cos(bLat * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }
}
