import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// One address/street/settlement result from GovMap, already converted to WGS84
/// (lat/lon) so the ranking + POI layers can consume it directly.
class GovMapPlace {
  const GovMapPlace({
    required this.label,
    required this.lat,
    required this.lon,
    required this.city,
    required this.kind,
  });

  final String label; // e.g. "דיזנגוף 100, תל אביב-יפו"
  final double lat, lon;
  final String city; // resolved settlement name
  final String kind; // ADDRESS | STREET | SETTLEMENT
}

/// Address search + autocomplete against GovMap — the official Israeli state
/// mapping service (govmap.gov.il). Covers every town, street and house number
/// in Israel and returns precise coordinates, so the Area-Intelligence profile
/// is built at the EXACT spot the user picked (not a city centroid).
///
/// GovMap returns Israeli TM Grid coordinates (EPSG:2039); we convert them to
/// WGS84 locally with the inverse Transverse-Mercator (the Israel 1993 → WGS84
/// datum shift is sub-metre — negligible for a nearby-POI radius).
class GovMapGeocoder {
  GovMapGeocoder._();
  static final GovMapGeocoder instance = GovMapGeocoder._();

  final http.Client _http = http.Client();

  // The DetailsByQuery "search everything" layer mask (addresses + streets +
  // settlements). Empirically stable; falls back to local suggestions on error.
  static const _lyrs = 276267;
  static const _base = 'https://es.govmap.gov.il/TldSearch/api/DetailsByQuery';

  /// Autocomplete/search. Returns settlements first, then streets, then exact
  /// addresses — the natural specificity order. Empty on any failure (the caller
  /// falls back to offline locality suggestions).
  Future<List<GovMapPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final uri = Uri.parse(
          '$_base?query=${Uri.encodeQueryComponent(q)}&lyrs=$_lyrs&gid=govmap');
      final r = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (body is! Map || body['data'] is! Map) return const [];
      final data = body['data'] as Map;
      // order is the category priority GovMap returns (SETTLEMENT/STREET/ADDRESS).
      final order = (body['order'] as List?)?.cast<String>() ??
          data.keys.cast<String>().toList();
      final out = <GovMapPlace>[];
      for (final cat in order) {
        final list = data[cat];
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map) continue;
          final x = (item['X'] as num?)?.toDouble();
          final y = (item['Y'] as num?)?.toDouble();
          final label = (item['ResultLable'] ?? '').toString().trim();
          if (x == null || y == null || label.isEmpty) continue;
          final ll = _itmToWgs84(x, y);
          out.add(GovMapPlace(
            label: label,
            lat: ll[0],
            lon: ll[1],
            city: _cityOf(label, cat.toString()),
            kind: cat.toString(),
          ));
          if (out.length >= 12) return out;
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // The settlement is the last comma-segment of the label ("רחוב, עיר"); a bare
  // SETTLEMENT result is itself the city.
  static String _cityOf(String label, String kind) {
    if (kind == 'SETTLEMENT') return label;
    final i = label.lastIndexOf(',');
    return i >= 0 ? label.substring(i + 1).trim() : label;
  }

  // ── EPSG:2039 (Israeli TM Grid, GRS80 / Israel 1993) → WGS84 lat/lon ────────
  static const double _a = 6378137.0; // GRS80 semi-major
  static const double _f = 1 / 298.257222101;
  static const double _lat0 = 0.5538696546399482; // 31.734393889° in rad
  static const double _lon0 = 0.6144212895371941; // 35.204516944° in rad
  static const double _k0 = 1.0000067;
  static const double _fe = 219529.584;
  static const double _fn = 626907.390;

  @visibleForTesting
  static List<double> itmToWgs84(double east, double north) =>
      _itmToWgs84(east, north);

  static List<double> _itmToWgs84(double east, double north) {
    final e2 = 2 * _f - _f * _f;
    final ep2 = e2 / (1 - e2);
    final x = east - _fe;
    final y = north - _fn;
    final m0 = _a *
        ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256) * _lat0 -
            (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 * e2 * e2 / 1024) *
                math.sin(2 * _lat0) +
            (15 * e2 * e2 / 256 + 45 * e2 * e2 * e2 / 1024) *
                math.sin(4 * _lat0) -
            (35 * e2 * e2 * e2 / 3072) * math.sin(6 * _lat0));
    final m = m0 + y / _k0;
    final mu = m / (_a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256));
    final e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2));
    final lat1 = mu +
        (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * math.sin(2 * mu) +
        (21 * e1 * e1 / 16 - 55 * e1 * e1 * e1 * e1 / 32) * math.sin(4 * mu) +
        (151 * e1 * e1 * e1 / 96) * math.sin(6 * mu) +
        (1097 * e1 * e1 * e1 * e1 / 512) * math.sin(8 * mu);
    final c1 = ep2 * math.cos(lat1) * math.cos(lat1);
    final t1 = math.tan(lat1) * math.tan(lat1);
    final sinLat1 = math.sin(lat1);
    final n1 = _a / math.sqrt(1 - e2 * sinLat1 * sinLat1);
    final r1 = _a * (1 - e2) / math.pow(1 - e2 * sinLat1 * sinLat1, 1.5);
    final d = x / (n1 * _k0);
    final lat = lat1 -
        (n1 * math.tan(lat1) / r1) *
            (d * d / 2 -
                (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) *
                    math.pow(d, 4) /
                    24 +
                (61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * ep2 - 3 * c1 * c1) *
                    math.pow(d, 6) /
                    720);
    final lon = _lon0 +
        (d -
                (1 + 2 * t1 + c1) * math.pow(d, 3) / 6 +
                (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) *
                    math.pow(d, 5) /
                    120) /
            math.cos(lat1);
    return [lat * 180 / math.pi, lon * 180 / math.pi];
  }
}
