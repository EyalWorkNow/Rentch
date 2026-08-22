import 'dart:convert';
import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;

/// One live job opening, as returned by TheirStack (a refreshing index of
/// postings aggregated from thousands of boards and company career sites).
class JobPosting {
  const JobPosting({
    required this.title,
    required this.company,
    required this.location,
    required this.link,
    this.salary = '',
    this.posted = '',
    this.remote = false,
    this.km,
  });

  final String title;
  final String company;
  final String location;
  final String link;
  final String salary;
  final String posted; // yyyy-mm-dd from the API, may be empty
  final bool remote;

  /// Distance from the listing in km (from the job's coordinates), null when
  /// the source didn't provide coordinates.
  final double? km;

  JobPosting withKm(double? km) => JobPosting(
        title: title,
        company: company,
        location: location,
        link: link,
        salary: salary,
        posted: posted,
        remote: remote,
        km: km,
      );

  static JobPosting fromTheirStack(Map<String, dynamic> j, double lat, double lon) {
    final company = j['company_object'];
    final jLat = (j['latitude'] as num?)?.toDouble();
    final jLon = (j['longitude'] as num?)?.toDouble();
    return JobPosting(
      title: (j['job_title'] ?? '').toString().trim(),
      company: (company is Map ? company['name'] ?? '' : '').toString().trim(),
      location: (j['location'] ?? j['short_location'] ?? '').toString().trim(),
      link: (j['url'] ?? j['final_url'] ?? '').toString().trim(),
      salary: (j['salary_string'] ?? '').toString().trim(),
      posted: (j['date_posted'] ?? '').toString().trim(),
      remote: j['remote'] == true,
      km: (jLat != null && jLon != null)
          ? _haversineKm(lat, lon, jLat, jLon)
          : null,
    );
  }
}

double _haversineKm(double la1, double lo1, double la2, double lo2) {
  const r = 6371.0;
  final dLa = (la2 - la1) * math.pi / 180;
  final dLo = (lo2 - lo1) * math.pi / 180;
  final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
      math.cos(la1 * math.pi / 180) *
          math.cos(la2 * math.pi / 180) *
          math.sin(dLo / 2) *
          math.sin(dLo / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Searches live openings AROUND the listing's coordinates via TheirStack's
/// POST /v1/jobs/search (Bearer key; Hebrew titles/locations verified against
/// the live API). Every TheirStack job carries lat/lon, so results are
/// filtered by TRUE distance from the listing — first within [radiusKm], and
/// only if the area is sparse widened to [wideRadiusKm] — then sorted
/// nearest-first. Billing is 1 credit PER JOB RETURNED, so limits stay small
/// and results are cached in-memory per (keywords, city) for 30 minutes.
class JobsService {
  JobsService._();
  static final JobsService instance = JobsService._();

  static const _endpoint = 'https://api.theirstack.com/v1/jobs/search';
  static const _ttl = Duration(minutes: 30);
  static const _maxAgeDays = 30; // a required-filter AND keeps results fresh
  static const radiusKm = 30.0; // "in the listing's area"
  static const wideRadiusKm = 60.0; // sparse-area widening (periphery towns)

  // Their location strings appear in Hebrew or English depending on the source
  // board, so the city pre-filter sends BOTH names. The distance filter is the
  // real gate — this just biases the returned page toward the right area.
  static const Map<String, String> _cityEn = {
    'תל אביב': 'Tel Aviv', 'תל אביב-יפו': 'Tel Aviv', 'ירושלים': 'Jerusalem',
    'חיפה': 'Haifa', 'באר שבע': 'Beer Sheva', 'ראשון לציון': 'Rishon LeZion',
    'פתח תקווה': 'Petah Tikva', 'נתניה': 'Netanya', 'אשדוד': 'Ashdod',
    'אשקלון': 'Ashkelon', 'רמת גן': 'Ramat Gan', 'גבעתיים': 'Givatayim',
    'חולון': 'Holon', 'בת ים': 'Bat Yam', 'רחובות': 'Rehovot',
    'הרצליה': 'Herzliya', 'כפר סבא': 'Kfar Saba', 'רעננה': "Ra'anana",
    'מודיעין': "Modi'in", 'בני ברק': 'Bnei Brak', 'חדרה': 'Hadera',
    'לוד': 'Lod', 'רמלה': 'Ramla', 'נצרת': 'Nazareth', 'עכו': 'Acre',
    'טבריה': 'Tiberias', 'אילת': 'Eilat', 'נהריה': 'Nahariya',
    'בית שמש': 'Beit Shemesh', 'קריית גת': 'Kiryat Gat',
    'קריית שמונה': 'Kiryat Shmona', 'עפולה': 'Afula', 'כרמיאל': 'Karmiel',
    'דימונה': 'Dimona', 'הוד השרון': 'Hod HaSharon', 'רמת השרון': 'Ramat HaSharon',
    'ראש העין': 'Rosh HaAyin', 'יבנה': 'Yavne', 'נס ציונה': 'Ness Ziona',
    'אור יהודה': 'Or Yehuda', 'קריית אונו': 'Kiryat Ono', 'גדרה': 'Gedera',
    'זכרון יעקב': 'Zikhron Yaakov', 'נתיבות': 'Netivot', 'שדרות': 'Sderot',
  };

  final Map<String, (DateTime, List<JobPosting>)> _cache = {};

  bool get isConfigured => AppConfig.hasJobsSearchConfig;

  /// Returns openings matching [keywords] within [radiusKm] of ([lat],[lon]),
  /// nearest-first, each annotated with its distance. Sparse areas widen to
  /// [wideRadiusKm]. Remote jobs count as in-area regardless of distance.
  /// Empty list on any failure (fail-soft — the UI shows its empty state).
  Future<List<JobPosting>> search({
    required String keywords,
    required String city,
    required double lat,
    required double lon,
    int limit = 10,
  }) async {
    if (!isConfigured) return const [];
    final key = '${keywords.trim()}|${city.trim()}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _ttl) {
      return hit.$2;
    }

    // Both sources fire in PARALLEL — Jooble (free, flaky IL index) never
    // delays TheirStack, and total latency is a single round-trip.
    final results = await Future.wait([
      _jooble(keywords: keywords, city: city, limit: limit),
      _theirStack(
          keywords: keywords, city: city, lat: lat, lon: lon, limit: limit),
    ]);
    final jooble = _filterByCity(results[0], city);
    var pool = results[1];

    // Only if the area came back nearly empty: one country-wide page, then the
    // distance gate below picks what's actually near.
    if (_within(pool, radiusKm).length + jooble.length < 3) {
      final wide = await _theirStack(
          keywords: keywords, city: '', lat: lat, lon: lon, limit: 20);
      final seen = pool.map((j) => j.link).toSet();
      pool = [...pool, ...wide.where((j) => seen.add(j.link))];
    }

    var near = _within(pool, radiusKm);
    if (near.isEmpty) near = _within(pool, wideRadiusKm);
    near.sort((a, b) => (a.km ?? 0).compareTo(b.km ?? 0));

    final seen = near.map((j) => j.link).toSet();
    final jobs = [...near, ...jooble.where((j) => seen.add(j.link))]
        .take(limit)
        .toList(growable: false);
    _cache[key] = (DateTime.now(), jobs);
    return jobs;
  }

  // In-radius jobs; remote jobs always qualify (commute-free by definition).
  List<JobPosting> _within(List<JobPosting> jobs, double km) => [
        for (final j in jobs)
          if (j.remote || (j.km != null && j.km! <= km)) j
      ];

  // Jooble rows have no coordinates — keep only ones whose location string
  // mentions the city (he or en), so no out-of-area rows sneak in.
  List<JobPosting> _filterByCity(List<JobPosting> jobs, String city) {
    final he = city.trim();
    if (he.isEmpty) return const [];
    final en = _cityEn[he] ?? _cityEn[he.split('-').first.trim()];
    return [
      for (final j in jobs)
        if (j.location.contains(he) ||
            (en != null && j.location.toLowerCase().contains(en.toLowerCase())))
          j
    ];
  }

  Future<List<JobPosting>> _theirStack({
    required String keywords,
    required String city,
    required double lat,
    required double lon,
    required int limit,
  }) async {
    if (AppConfig.theirStackApiKey.trim().isEmpty) return const [];
    final cityHe = city.trim();
    final en = _cityEn[cityHe] ?? _cityEn[cityHe.split('-').first.trim()];
    final body = <String, dynamic>{
      'job_country_code_or': ['IL'],
      'posted_at_max_age_days': _maxAgeDays,
      'limit': limit,
      'page': 0,
      if (keywords.trim().isNotEmpty) 'job_title_or': [keywords.trim()],
      if (cityHe.isNotEmpty)
        'job_location_pattern_or': [
          RegExp.escape(cityHe),
          if (en != null) RegExp.escape(en),
        ],
    };
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer ${AppConfig.theirStackApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        if (kDebugMode) debugPrint('JobsService: HTTP ${res.statusCode}');
        return const [];
      }
      final parsed = jsonDecode(utf8.decode(res.bodyBytes));
      final raw = (parsed is Map ? parsed['data'] : null);
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((j) =>
              JobPosting.fromTheirStack(Map<String, dynamic>.from(j), lat, lon))
          .where((j) => j.title.isNotEmpty && j.link.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('JobsService: $e');
      return const [];
    }
  }

  /// The free Jooble source — best-effort top-up, never a blocker. Only the
  /// global host: il.jooble.org hangs to connection-timeout (verified live),
  /// which used to stall every search by its full timeout.
  Future<List<JobPosting>> _jooble({
    required String keywords,
    required String city,
    required int limit,
  }) async {
    final apiKey = AppConfig.joobleApiKey.trim();
    if (apiKey.isEmpty) return const [];
    for (final host in const ['jooble.org']) {
      try {
        final res = await http
            .post(
              Uri.https(host, '/api/$apiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'keywords': keywords.trim(),
                'location': city.trim().isEmpty ? 'Israel' : city.trim(),
              }),
            )
            .timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;
        final parsed = jsonDecode(utf8.decode(res.bodyBytes));
        final raw = (parsed is Map ? parsed['jobs'] : null);
        if (raw is! List) continue;
        final jobs = raw
            .whereType<Map>()
            .map((j) => JobPosting(
                  title: (j['title'] ?? '').toString().trim(),
                  company: (j['company'] ?? '').toString().trim(),
                  location: (j['location'] ?? '').toString().trim(),
                  link: (j['link'] ?? '').toString().trim(),
                  salary: (j['salary'] ?? '').toString().trim(),
                  posted: (j['updated'] ?? '').toString().split('T').first,
                ))
            .where((j) => j.title.isNotEmpty && j.link.isNotEmpty)
            .take(limit)
            .toList(growable: false);
        if (jobs.isNotEmpty) return jobs;
      } catch (_) {/* try next host / fall through to TheirStack */}
    }
    return const [];
  }
}
