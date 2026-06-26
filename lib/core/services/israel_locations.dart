import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Israel cities + streets autocomplete service.
///
/// Data source: data.gov.il "רשימת רחובות בישראל" (official open gov dataset).
/// Assets are lazy-loaded once from rootBundle and cached in memory.
///
/// Hebrew-friendly matching: quotes/geresh (״ ׳ " ') are stripped, whitespace
/// collapsed, and matching is case- and nikud-insensitive. Lowercased normalized
/// keys are precomputed once on load so queries stay fast.
class IsraelLocations {
  IsraelLocations._();

  static const String _citiesAsset = 'assets/data/israel_cities.json';
  static const String _streetsAsset = 'assets/data/israel_streets.json';

  static bool _loaded = false;
  static Future<void>? _loadingFuture;

  /// Sorted list of unique settlement names (display form).
  static List<String> _cities = const [];

  /// Parallel list of normalized city keys (same index as [_cities]).
  static List<String> _cityKeys = const [];

  /// city -> list of street display names (sorted).
  static Map<String, List<String>> _streets = const {};

  /// city -> parallel list of normalized street keys.
  static final Map<String, List<String>> _streetKeys = {};

  /// Lazy-load assets, cache in memory. Idempotent and concurrency-safe.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadingFuture ??= _load();
  }

  static Future<void> _load() async {
    final citiesRaw = await rootBundle.loadString(_citiesAsset);
    final streetsRaw = await rootBundle.loadString(_streetsAsset);

    final citiesJson = json.decode(citiesRaw) as List<dynamic>;
    _cities = citiesJson.map((e) => e as String).toList(growable: false);
    _cityKeys =
        _cities.map(_normalize).toList(growable: false);

    final streetsJson = json.decode(streetsRaw) as Map<String, dynamic>;
    final streets = <String, List<String>>{};
    streetsJson.forEach((city, value) {
      final list = (value as List<dynamic>)
          .map((e) => e as String)
          .toList(growable: false);
      streets[city] = list;
    });
    _streets = streets;

    _loaded = true;
    _loadingFuture = null;
  }

  /// Normalize a Hebrew/Latin string for matching: lower-case, strip geresh /
  /// gershayim / ASCII quotes / apostrophes / hyphens, remove Hebrew nikud,
  /// and collapse whitespace.
  static String _normalize(String input) {
    final buffer = StringBuffer();
    var prevSpace = false;
    for (final rune in input.toLowerCase().runes) {
      // Hebrew nikud (cantillation/points) U+0591..U+05C7 -> drop.
      if (rune >= 0x0591 && rune <= 0x05C7) continue;
      switch (rune) {
        case 0x05F3: // ׳ geresh
        case 0x05F4: // ״ gershayim
        case 0x0022: // "
        case 0x0027: // '
        case 0x2019: // ’
        case 0x2018: // ‘
        case 0x201C: // “
        case 0x201D: // ”
          continue;
      }
      // Hyphens/dashes act as separators -> normalize to a single space so that
      // "תל-אביב" and "תל אביב" collapse to the same key.
      final isSpace = rune == 0x20 ||
          rune == 0x09 ||
          rune == 0x0A ||
          rune == 0x0D ||
          rune == 0x002D || // -
          rune == 0x2013 || // –
          rune == 0x2014; // —
      if (isSpace) {
        if (prevSpace) continue;
        buffer.writeCharCode(0x20);
        prevSpace = true;
      } else {
        buffer.writeCharCode(rune);
        prevSpace = false;
      }
    }
    return buffer.toString().trim();
  }

  /// Rank candidates: prefix matches first, then "contains" matches.
  /// An empty query returns the first [limit] items in their natural order.
  static List<String> _search(
    List<String> display,
    List<String> keys,
    String query,
    int limit,
  ) {
    final q = _normalize(query);
    if (q.isEmpty) {
      return display.length <= limit ? List.of(display) : display.sublist(0, limit);
    }
    final prefix = <String>[];
    final contains = <String>[];
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final idx = k.indexOf(q);
      if (idx == 0) {
        prefix.add(display[i]);
        if (prefix.length >= limit) break;
      } else if (idx > 0) {
        contains.add(display[i]);
      }
    }
    if (prefix.length >= limit) return prefix;
    final out = prefix;
    for (final c in contains) {
      if (out.length >= limit) break;
      out.add(c);
    }
    return out;
  }

  /// Search settlement names. Prefix matches first, then "contains".
  /// Empty query returns the first [limit] cities.
  static List<String> searchCities(String query, {int limit = 40}) {
    if (!_loaded) return const [];
    return _search(_cities, _cityKeys, query, limit);
  }

  /// Streets of [city], optionally filtered by [query] (prefix then contains).
  /// Returns empty list if the city is unknown or not yet loaded.
  static List<String> streetsOf(String city, {String query = '', int limit = 40}) {
    if (!_loaded) return const [];
    final list = _streets[city];
    if (list == null || list.isEmpty) return const [];
    final keys = _streetKeys.putIfAbsent(
      city,
      () => list.map(_normalize).toList(growable: false),
    );
    return _search(list, keys, query, limit);
  }
}
