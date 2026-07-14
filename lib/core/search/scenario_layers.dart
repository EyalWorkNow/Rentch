// ═══════════════════════════════════════════════════════════════════════════
// SCENARIO → DISPLAY-LAYER resolver.
//
// A curated spec (assets/data/search_scenarios.json, 504 rows = the full cross-
// product of life_stage × religiosity × pets × work_style × purpose) says, per
// persona, WHICH map/nearby layers to surface (core = highlighted, secondary =
// supporting) and how to WEIGHT them. This resolver:
//   1. loads the spec once,
//   2. derives the 5 structured dimensions from the existing NearbyProfile
//      (+ optional religiosity/purpose the caller already knows),
//   3. returns ordered NearbySections (spec-primary) and the layer weights.
//
// It is SPEC-PRIMARY WITH FALLBACK: when the profile resolves to a known
// scenario AND the asset is loaded, callers use this; otherwise they fall back
// to the existing heuristic (relevantNearbySections). Loading failure or an
// unmapped combo → returns null, never throws.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class ScenarioEntry {
  const ScenarioEntry(this.core, this.secondary, this.weights);
  final List<String> core; // layer names, highlighted
  final List<String> secondary; // layer names, supporting
  final Map<String, double> weights; // layer name → weight
}

class ScenarioLayers {
  ScenarioLayers._();
  static final ScenarioLayers instance = ScenarioLayers._();

  static const _asset = 'assets/data/search_scenarios.json';

  Map<String, ScenarioEntry> _map = const {};
  List<String> _base = const [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Load the spec once. Best-effort — a failure leaves the resolver inert
  /// (sectionsFor/weightsFor return null) so callers fall back cleanly.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_asset);
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _base = ((j['base'] as List?) ?? const []).map((e) => '$e').toList();
      final m = <String, ScenarioEntry>{};
      (j['map'] as Map<String, dynamic>).forEach((key, v) {
        final e = v as Map<String, dynamic>;
        m[key] = ScenarioEntry(
          ((e['c'] as List?) ?? const []).map((x) => '$x').toList(),
          ((e['s'] as List?) ?? const []).map((x) => '$x').toList(),
          ((e['w'] as Map?) ?? const {}).map(
              (k, val) => MapEntry('$k', (val as num).toDouble())),
        );
      });
      _map = m;
      _loaded = true;
    } catch (e) {
      if (kDebugMode) debugPrint('ScenarioLayers.ensureLoaded failed: $e');
    }
  }

  // ── dimension derivation ──────────────────────────────────────────────────

  /// Build the 5-dimension key from the profile. [religiosity] (from the
  /// persona: secular/traditional/religious/haredi) and [purpose] (rent/buy)
  /// override the coarse derivation when the caller knows them.
  @visibleForTesting
  String deriveKey(NearbyProfile p, {String? religiosity, String? purpose}) =>
      [
        _lifeStage(p),
        _religiosity(p, religiosity),
        _pets(p),
        _workStyle(p),
        _purpose(purpose),
      ].join('|');

  static String _lifeStage(NearbyProfile p) {
    if (p.youngChild) return 'mishpacha_tinok';
    if (p.teen) return 'mishpacha_metabgrim';
    if (p.schoolChild) return 'mishpacha_yeladim';
    if (p.family) return 'mishpacha_yeladim'; // generic family → school-age default
    if (p.senior) return 'gimlaim';
    if (p.couple) return 'zug_bli_yeladim';
    return 'ravak_ravaka'; // single / roommates / student / unknown
  }

  static String _religiosity(NearbyProfile p, String? explicit) {
    switch (explicit) {
      case 'secular':
        return 'chiloni';
      case 'traditional':
        return 'masorti';
      case 'religious':
        return 'dati';
      case 'haredi':
        return 'charedi';
    }
    if (p.observant) return 'dati';
    if (p.secular) return 'chiloni';
    return 'masorti'; // middle default when unknown
  }

  static String _pets(NearbyProfile p) {
    if (p.dog) return 'dog';
    if (p.pet) return 'cat';
    return 'none';
  }

  static String _workStyle(NearbyProfile p) {
    if (p.student) return 'student';
    if (p.wfh) return 'remote';
    return 'office';
  }

  static String _purpose(String? purpose) =>
      (purpose == 'buy') ? 'buy' : 'rent';

  // ── spec → NearbyKind (display) ───────────────────────────────────────────

  /// Layers that map to a visible nearby section. Scoring-only layers
  /// (employment/market_seed/poi_retail/crime/noise_roads/stat_area_value/
  /// stat_areas/future_infra/demographics/air_quality_stations) are absent here
  /// on purpose — they feed weightsFor, not the display.
  static const Map<String, NearbyKind> _layerToKind = {
    'transit_stops': NearbyKind.transit,
    'rail_stations': NearbyKind.transit,
    'nightlife': NearbyKind.nightlife,
    'nightlife_venues': NearbyKind.nightlife,
    'dining': NearbyKind.dining,
    'dog_parks': NearbyKind.dogParks,
    'parks': NearbyKind.parks,
    'culture': NearbyKind.culture,
    'vets': NearbyKind.vets,
    'gyms': NearbyKind.gyms,
    'pools': NearbyKind.pools,
    'parking': NearbyKind.parking,
    'supermarkets': NearbyKind.supermarkets,
    'coworking': NearbyKind.coworking,
    'schools': NearbyKind.schools,
    'schools_grid': NearbyKind.schools,
    'playgrounds': NearbyKind.playgrounds,
    'synagogues': NearbyKind.synagogues,
    'worship': NearbyKind.worship,
    'clinics': NearbyKind.clinics,
    'health': NearbyKind.clinics,
    'pharmacies': NearbyKind.pharmacies,
    'hospitals': NearbyKind.hospitals,
    'bike_share': NearbyKind.bikeShare,
  };

  /// Spec-driven ordered sections for [p], or null when unavailable (not loaded
  /// / no matching scenario) so the caller falls back to the heuristic.
  List<NearbySection>? sectionsFor(NearbyProfile p,
      {String? religiosity, String? purpose}) {
    if (!_loaded) return null;
    final entry = _map[deriveKey(p, religiosity: religiosity, purpose: purpose)];
    if (entry == null) return null;

    final out = <NearbySection>[];
    final seen = <NearbyKind>{};
    void addLayer(String name, int prio) {
      final k = _layerToKind[name];
      if (k == null || seen.contains(k)) return; // scoring-only or dup
      // A family with a pre-schooler wants kindergartens, not just "schools".
      if (k == NearbyKind.schools && p.youngChild && seen.add(NearbyKind.kindergartens)) {
        out.add(NearbySection(NearbyKind.kindergartens, priority: prio + 2));
      }
      seen.add(k);
      out.add(NearbySection(k, hmo: k == NearbyKind.clinics ? p.hmo : '', priority: prio));
    }

    // core: 90..(descending), secondary: 55.., base layers: 30.. (background).
    var prio = 90;
    for (final l in entry.core) { addLayer(l, prio); prio -= 3; }
    prio = 55;
    for (final l in entry.secondary) { addLayer(l, prio); prio -= 2; }
    prio = 32;
    for (final l in _base) { addLayer(l, prio); prio -= 1; }

    // Honour the same hard suppression as the heuristic: an explicitly secular
    // seeker never sees places of worship even if a mid-default slipped through.
    if (p.secular) {
      out.removeWhere((s) =>
          s.kind == NearbyKind.synagogues || s.kind == NearbyKind.worship);
    }
    return out.isEmpty ? null : out;
  }

  /// The per-layer weights for [p] (for the ranking score), or null.
  Map<String, double>? weightsFor(NearbyProfile p,
      {String? religiosity, String? purpose}) {
    if (!_loaded) return null;
    return _map[deriveKey(p, religiosity: religiosity, purpose: purpose)]
        ?.weights;
  }

  // ── spec → ranking dimension (scoring) ────────────────────────────────────

  /// Spec layer → a canonical scoring dimension (kScoringDimensions). Only
  /// layers that have a ranking dimension are here; pure display POIs
  /// (culture/dining/gyms/pools/vets/parking/bike_share/playgrounds) have none.
  static const Map<String, String> _layerToDim = {
    'transit_stops': 'transit',
    'rail_stations': 'transit',
    'nightlife': 'nightlife',
    'nightlife_venues': 'nightlife',
    'schools': 'schools',
    'schools_grid': 'schools',
    'parks': 'park',
    'dog_parks': 'park',
    'synagogues': 'religious_area',
    'worship': 'religious_area',
    'market_seed': 'value',
    'stat_area_value': 'value',
    'employment': 'employment',
    'coworking': 'employment',
    'crime': 'safety',
    'noise_roads': 'low_noise',
    'future_infra': 'future_value',
    'supermarkets': 'convenience',
    'poi_retail': 'convenience',
    'clinics': 'health',
    'health': 'health',
    'pharmacies': 'health',
    'hospitals': 'health',
  };

  /// Per-dimension prior-boost targets (0..1) for [p], derived from the
  /// scenario's layer weights (spec range ~0.5..5 → target mean 0.5..1.0),
  /// keeping the strongest layer per dimension. Fed to the ranker as a GENTLE
  /// low-precision prior so learned/stated evidence still dominates. Null when
  /// unavailable.
  Map<String, double>? dimensionBoostsFor(NearbyProfile p,
      {String? religiosity, String? purpose}) {
    final w = weightsFor(p, religiosity: religiosity, purpose: purpose);
    if (w == null) return null;
    final out = <String, double>{};
    w.forEach((layer, weight) {
      final dim = _layerToDim[layer];
      if (dim == null) return;
      final target = (0.5 + weight * 0.09).clamp(0.0, 1.0);
      if (target > (out[dim] ?? 0.0)) out[dim] = target;
    });
    return out.isEmpty ? null : out;
  }
}

/// Spec-primary nearby sections with heuristic fallback — the entry point call
/// sites should use instead of [orderedNearbySections] directly. Returns the
/// curated 504-scenario ordering when the profile resolves and the asset is
/// loaded; otherwise the existing heuristic ordering, unchanged.
List<NearbySection> personalizedNearbySections(NearbyProfile p,
    {bool coreOnly = false, String? religiosity, String? purpose}) {
  final spec = ScenarioLayers.instance
      .sectionsFor(p, religiosity: religiosity, purpose: purpose);
  if (spec != null) {
    final list = [...spec]..sort((a, b) => b.priority.compareTo(a.priority));
    // coreOnly (chat preview) → the highlighted core band only (secondary starts
    // at priority 55, base at 32; core is ≥72).
    return coreOnly ? list.where((s) => s.priority >= 56).toList() : list;
  }
  // Fallback to the existing heuristic, unchanged.
  return coreOnly ? relevantNearbySections(p) : orderedNearbySections(p);
}
