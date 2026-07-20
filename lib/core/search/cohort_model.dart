/// Client-side SOFT cohort membership — a probability vector over the 14
/// cohorts, evolving across sessions (Phase-0, Layer-1 of the targeting plan).
///
/// The server ([cohort.mjs] `cohortFromSignals`) resolves a SINGLE cohort label
/// per request, first-match-wins, and never stores it. This model instead turns
/// the same [SmartSearch.cohortSignals] into a *distribution* (a person can be
/// 0.6 family / 0.3 new_parents / 0.1 remote) and accumulates it as an evolving
/// belief ([CohortBelief]) so cohort becomes a persisted, personalised trait
/// rather than a throwaway per-query guess.
///
/// Pure Dart, no I/O — the provider persists [CohortBelief.toJson].
library;

/// The 14 canonical cohorts — mirrors the server `COHORT_KEYS`.
const List<String> kCohortKeys = [
  'investor',
  'arab_family',
  'oleh',
  'charedi',
  'dati_leumi',
  'senior',
  'single_parent',
  'new_parents',
  'remote',
  'student',
  'young_professional',
  'family',
  'couple',
  'single',
];

class CohortModel {
  CohortModel._();

  static bool _truthy(String? v) => v == 'true' || v == '1';
  static bool _contains(String? v, String needle) =>
      v != null && v.contains(needle);

  /// Raw, un-normalised evidence per cohort from [signals] (the map
  /// `SmartSearch.cohortSignals` emits). Higher weight = stronger/more specific
  /// signal, mirroring the server cascade's priority order.
  static Map<String, double> _evidence(Map<String, String> signals) {
    final s = signals;
    final household = s['household'];
    final stream = s['religiousStream'];
    final vibe = s['vibe'];
    final lifeStage = s['lifeStage'];
    final religious = s['sector'] == 'jewish-religious' || _truthy(s['isReligious']);
    final family = household == 'family' || _contains(vibe, 'משפח');
    final age = int.tryParse(s['age'] ?? '') ?? 0;
    final childAge = int.tryParse(s['childAge'] ?? '');

    final e = <String, double>{for (final k in kCohortKeys) k: 0.0};
    void add(String k, double w) => e[k] = (e[k] ?? 0) + w;

    // (a) intent
    if (_truthy(s['isInvestor']) || s['intent'] == 'investment') add('investor', 3.0);
    // (b) sector / community
    if (s['sector'] == 'arab') add('arab_family', 3.0);
    if (_truthy(s['isOleh']) || s['langPref'] == 'en' || s['langPref'] == 'fr') {
      add('oleh', 2.5);
    }
    if (religious) {
      final strong = family || (int.tryParse(s['numChildren'] ?? '') ?? 0) >= 4;
      if (stream == 'charedi') {
        add('charedi', strong ? 2.5 : 1.0);
      } else {
        add('dati_leumi', strong ? 2.5 : 1.0);
      }
    }
    // (c) life stage / accessibility
    if (_truthy(s['accessibilityNeed']) || age >= 65 || lifeStage == 'senior') {
      add('senior', 2.5);
    }
    // (d) mobility / family structure
    if (_truthy(s['hasChildren']) && _truthy(s['carFree'])) add('single_parent', 2.0);
    if (_truthy(s['expecting']) ||
        (_truthy(s['hasChildren']) && childAge != null && childAge < 2) ||
        (household == 'couple' && _contains(vibe, 'משפח'))) {
      add('new_parents', 2.0);
    }
    if (_truthy(s['wfh'])) {
      add('remote', (household == 'single' || lifeStage == 'young-professional') ? 1.5 : 0.7);
    }
    if (lifeStage == 'student' || household == 'student' || _contains(vibe, 'סטודנט')) {
      add('student', 2.0);
    }
    if (household == 'single' && _contains(vibe, 'תוסס')) add('young_professional', 1.5);
    // (e) coarse household fallbacks
    if (family) add('family', 1.2);
    if (household == 'couple') add('couple', 1.0);
    if (household == 'single') add('single', 0.8);

    return e;
  }

  /// A normalised probability vector over the 14 cohorts (sums to 1). Returns an
  /// all-zero map when there's no evidence (unknown person — never guesses).
  static Map<String, double> distribution(Map<String, String> signals) {
    final e = _evidence(signals);
    final total = e.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return e; // all zeros
    return {for (final entry in e.entries) entry.key: entry.value / total};
  }

  /// The single most-likely cohort (or null when there's no evidence) — matches
  /// the server's single-label output for compatibility.
  static String? topCohort(Map<String, String> signals) {
    final d = distribution(signals);
    String? best;
    var bestW = 0.0;
    for (final entry in d.entries) {
      if (entry.value > bestW) {
        bestW = entry.value;
        best = entry.key;
      }
    }
    return best;
  }
}

/// An evolving cohort belief: an EMA of per-query distributions, persisted so the
/// membership sharpens over a person's sessions instead of resetting each query.
class CohortBelief {
  CohortBelief({Map<String, double>? weights, this.observations = 0})
      : weights = weights ?? {for (final k in kCohortKeys) k: 0.0};

  final Map<String, double> weights;
  int observations;

  /// Fold a new query's signals into the belief. Early observations move it
  /// faster (cold-start), settling toward [alpha] as evidence accrues.
  void observe(Map<String, String> signals, {double alpha = 0.35}) {
    final incoming = CohortModel.distribution(signals);
    if (incoming.values.every((v) => v == 0)) return; // no evidence → no update
    // Warm-start faster while we know little about the person.
    final a = observations < 3 ? 0.6 : alpha;
    for (final k in kCohortKeys) {
      weights[k] = (weights[k] ?? 0) * (1 - a) + (incoming[k] ?? 0) * a;
    }
    _renormalise();
    observations++;
  }

  void _renormalise() {
    final total = weights.values.fold<double>(0, (x, y) => x + y);
    if (total <= 0) return;
    for (final k in weights.keys) {
      weights[k] = weights[k]! / total;
    }
  }

  /// The current best-guess cohort, or null when the belief is still empty.
  String? get top {
    String? best;
    var bestW = 0.0;
    for (final entry in weights.entries) {
      if (entry.value > bestW) {
        bestW = entry.value;
        best = entry.key;
      }
    }
    return best;
  }

  /// Top-K cohorts above [minWeight], strongest first — the "audience" a person
  /// belongs to (feeds the eventual server multi-label + look-alike targeting).
  List<String> topK(int k, {double minWeight = 0.08}) {
    final entries = weights.entries.where((e) => e.value >= minWeight).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(k).map((e) => e.key).toList();
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'observations': observations,
        // store only non-zero weights to keep it compact
        'weights': {
          for (final entry in weights.entries)
            if (entry.value > 0) entry.key: double.parse(entry.value.toStringAsFixed(4)),
        },
      };

  factory CohortBelief.fromJson(Map<String, dynamic> json) {
    final raw = json['weights'];
    final w = <String, double>{for (final k in kCohortKeys) k: 0.0};
    if (raw is Map) {
      raw.forEach((key, value) {
        final k = key.toString();
        if (w.containsKey(k)) w[k] = (value as num?)?.toDouble() ?? 0.0;
      });
    }
    return CohortBelief(
      weights: w,
      observations: (json['observations'] as num?)?.toInt() ?? 0,
    );
  }
}
