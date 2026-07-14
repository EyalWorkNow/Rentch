// ═══════════════════════════════════════════════════════════════════════════
// WHAT-IF simulation — turns a dead-end search ("0-2 results") into actionable,
// QUANTIFIED guidance: "אם תעלה ל-9,600 ₪ → עוד 12 דירות".
//
// Pure Dart: given the current query and a `countMatches` function (in the app,
// `provider.recommendForTenant(...).length`), it tries a few targeted relaxations
// of the user's OWN constraints and returns only the ones that MATERIALLY help
// (gain ≥ minGain). No network, no model — it leans entirely on the existing fast
// local ranker, so it's cheap to run and trivial to unit-test.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dating_app/core/search/smart_search.dart';

/// One "what-if" the seeker can apply with a tap.
class WhatIfSuggestion {
  const WhatIfSuggestion({
    required this.key,
    required this.label,
    required this.gainText,
    required this.mutated,
    required this.deltaCount,
    required this.baselineCount,
  });

  /// Stable identifier: 'budget' | 'rooms' | 'feature:<name>'.
  final String key;

  /// Chip text describing the CHANGE, e.g. "עד 9,600 ₪" / "בלי ממ״ד".
  final String label;

  /// Human gain text, e.g. "עוד 12 דירות".
  final String gainText;

  /// The query to apply on tap.
  final SearchQuery mutated;

  /// Extra matches vs. the current query (always ≥ minGain when surfaced).
  final int deltaCount;
  final int baselineCount;
}

class WhatIfEngine {
  const WhatIfEngine._();

  // Canonical required-feature key → Hebrew label (requiredFeatures use canonical
  // keys like 'mamad', NOT the 'feat_*' amenity keys). Unknown keys fall back to
  // the raw key so a new feature never crashes the chip.
  static const Map<String, String> _featureLabels = {
    'mamad': 'ממ״ד',
    'parking': 'חניה',
    'elevator': 'מעלית',
    'petsAllowed': 'בעלי חיים',
    'furnished': 'ריהוט',
    'balcony': 'מרפסת',
    'ac': 'מיזוג',
    'garden': 'גינה',
    'accessible': 'נגישות',
    'storage': 'מחסן',
    'renovated': 'שיפוץ',
  };

  /// The what-ifs that materially help, most-helpful first.
  ///
  /// [countMatches] returns how many listings a query yields (the app passes the
  /// real ranker; a test can pass a trivial catalog filter). [baselineCount], if
  /// known by the caller, avoids one extra count for the current query.
  static List<WhatIfSuggestion> suggest({
    required SearchQuery query,
    required int Function(SearchQuery) countMatches,
    int? baselineCount,
    int minGain = 3,
    int maxSuggestions = 3,
  }) {
    final base = baselineCount ?? countMatches(query);
    final out = <WhatIfSuggestion>[];
    for (final c in _candidates(query)) {
      final gain = countMatches(c.mutated) - base;
      if (gain >= minGain) {
        out.add(WhatIfSuggestion(
          key: c.key,
          label: c.label,
          gainText: 'עוד $gain דירות',
          mutated: c.mutated,
          deltaCount: gain,
          baselineCount: base,
        ));
      }
    }
    out.sort((a, b) => b.deltaCount.compareTo(a.deltaCount));
    return out.take(maxSuggestions).toList();
  }

  // ── the relaxations we consider (only those the user's query makes applicable) ─
  static List<_Cand> _candidates(SearchQuery q) {
    final cands = <_Cand>[];

    // Raise the budget ~20% (rounded to ₪100). Only when a ceiling is set and the
    // rounded value is actually higher.
    if (q.maxPrice != null) {
      final raised = ((q.maxPrice! * 1.2) / 100).round() * 100;
      if (raised > q.maxPrice!) {
        cands.add(_Cand(
            'budget', 'עד ${_money(raised)} ₪', q.copyWith(maxPrice: raised)));
      }
    }

    // Accept one fewer room (never below 1).
    if (q.minRooms != null && q.minRooms! > 1) {
      final r = q.minRooms! - 1;
      cands.add(_Cand('rooms', 'מ-${_rooms(r)} חדרים', q.copyWith(minRooms: r)));
    }

    // Drop each hard-required feature (one candidate per feature — suggest() keeps
    // whichever actually frees up listings, so we don't need a rarity heuristic).
    for (final f in q.requiredFeatures) {
      final rest = {...q.requiredFeatures}..remove(f);
      cands.add(_Cand(
          'feature:$f', 'בלי ${_featureLabels[f] ?? f}',
          q.copyWith(requiredFeatures: rest)));
    }

    return cands;
  }

  static String _rooms(double r) =>
      r == r.roundToDouble() ? r.toInt().toString() : r.toString();

  static String _money(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _Cand {
  const _Cand(this.key, this.label, this.mutated);
  final String key;
  final String label;
  final SearchQuery mutated;
}
