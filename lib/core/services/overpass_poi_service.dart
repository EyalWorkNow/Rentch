import 'dart:convert';

import 'package:dating_app/core/search/engine/feature_engineering.dart'
    show IsraelGeoIndex, NearbyPlace;
import 'package:http/http.dart' as http;

/// Live, COMPREHENSIVE nearby-POI lookup from OpenStreetMap via the Overpass API.
///
/// The bundled gov POI datasets are partial (they miss many cafés/gyms/parks),
/// so Area Intelligence uses this to guarantee that everything within the radius
/// actually shows up. One request fetches every category; results are grouped
/// into our category keys. Fail-soft: any error → empty map (the screen still
/// shows the bundled layers).
class OverpassPoiService {
  OverpassPoiService._();
  static final OverpassPoiService instance = OverpassPoiService._();

  final http.Client _http = http.Client();

  // Public Overpass needs a real User-Agent + Accept, or it 406s.
  static const _headers = {
    'User-Agent': 'RentlyAreaIntel/1.0 (real-estate area analysis)',
    'Accept': 'application/json',
    'Content-Type': 'text/plain; charset=utf-8',
  };
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  /// Everything within [radiusM] metres, grouped by our category key
  /// (dining/gyms/parks/…). Sorted nearest-first within each category.
  Future<Map<String, List<NearbyPlace>>> nearby(double lat, double lon,
      {int radiusM = 2000}) async {
    final r = radiusM;
    final query = '[out:json][timeout:25];('
        'nwr(around:$r,$lat,$lon)[amenity~"^(cafe|restaurant|fast_food|bar|pub|ice_cream|food_court|pharmacy|school|kindergarten|clinic|doctors|hospital|dentist|cinema|theatre|arts_centre|library|community_centre|place_of_worship|bus_station|marketplace)\$"];'
        'nwr(around:$r,$lat,$lon)[leisure~"^(fitness_centre|sports_centre|park|garden|nature_reserve|playground)\$"];'
        'nwr(around:$r,$lat,$lon)[shop~"^(supermarket|convenience|greengrocer|grocery)\$"];'
        'nwr(around:$r,$lat,$lon)[tourism~"^(museum|gallery)\$"];'
        'nwr(around:$r,$lat,$lon)[railway~"^(station|tram_stop)\$"];'
        'nwr(around:$r,$lat,$lon)[public_transport=station];'
        ');out center tags 1500;';

    for (final ep in _endpoints) {
      try {
        final res = await _http
            .post(Uri.parse(ep), headers: _headers, body: query)
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is! Map || body['elements'] is! List) continue;
        return _group(body['elements'] as List, lat, lon);
      } catch (_) {
        // try the next mirror
      }
    }
    return const {};
  }

  Map<String, List<NearbyPlace>> _group(
      List elements, double lat, double lon) {
    final out = <String, List<NearbyPlace>>{};
    final seen = <String>{};
    for (final e in elements) {
      if (e is! Map) continue;
      final tags = e['tags'];
      if (tags is! Map) continue;
      final cat = _category(tags);
      if (cat == null) continue;
      double? plat = (e['lat'] as num?)?.toDouble();
      double? plon = (e['lon'] as num?)?.toDouble();
      if (plat == null || plon == null) {
        final c = e['center'];
        if (c is Map) {
          plat = (c['lat'] as num?)?.toDouble();
          plon = (c['lon'] as num?)?.toDouble();
        }
      }
      if (plat == null || plon == null) continue;
      final name = (tags['name'] ??
              tags['name:he'] ??
              tags['name:en'] ??
              tags['brand'] ??
              '')
          .toString()
          .trim();
      // Dedupe across duplicate OSM objects (node + way for the same place).
      final key = '$cat|${name.isEmpty ? '${plat.toStringAsFixed(4)},${plon.toStringAsFixed(4)}' : name}';
      if (!seen.add(key)) continue;
      final km = IsraelGeoIndex.haversineKm(lat, lon, plat, plon);
      (out[cat] ??= []).add(NearbyPlace(
        name: name,
        km: km,
        lat: plat,
        lon: plon,
        kind: cat,
      ));
    }
    for (final l in out.values) {
      l.sort((a, b) => a.km.compareTo(b.km));
    }
    return out;
  }

  static String? _category(Map t) {
    final a = t['amenity'];
    final l = t['leisure'];
    final s = t['shop'];
    final to = t['tourism'];
    final rw = t['railway'];
    final pt = t['public_transport'];
    if (a == 'cafe' ||
        a == 'restaurant' ||
        a == 'fast_food' ||
        a == 'bar' ||
        a == 'pub' ||
        a == 'ice_cream' ||
        a == 'food_court') {
      return 'dining';
    }
    if (a == 'pharmacy') return 'pharmacies';
    if (a == 'school') return 'schools';
    if (a == 'kindergarten') return 'kindergartens';
    if (a == 'clinic' || a == 'doctors' || a == 'hospital' || a == 'dentist') {
      return 'health';
    }
    if (a == 'cinema' ||
        a == 'theatre' ||
        a == 'arts_centre' ||
        a == 'library' ||
        a == 'community_centre' ||
        to == 'museum' ||
        to == 'gallery') {
      return 'culture';
    }
    if (a == 'place_of_worship') return 'worship';
    if (l == 'fitness_centre' || l == 'sports_centre' || a == 'gym') {
      return 'gyms';
    }
    if (l == 'park' || l == 'garden' || l == 'nature_reserve') {
      return 'parks';
    }
    if (l == 'playground') return 'playgrounds';
    if (s == 'supermarket' ||
        s == 'convenience' ||
        s == 'greengrocer' ||
        s == 'grocery' ||
        a == 'marketplace') {
      return 'supermarkets';
    }
    if (rw == 'station' ||
        rw == 'tram_stop' ||
        pt == 'station' ||
        a == 'bus_station') {
      return 'transit';
    }
    return null;
  }
}
