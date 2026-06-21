import 'dart:math' as math;

import 'package:dating_app/data/models/rental_models.dart';

// Parsed intent from a free-text request like:
//   "דירה ליד הרכבת, משופצת, 3 חדרים, לזוג עם כלבה, בלי ילדים"
class SearchQuery {
  SearchQuery({
    this.city,
    this.maxPrice,
    this.minRooms,
    Set<String>? amenities,
    this.nearTrain = false,
    this.rawText = '',
  }) : amenities = amenities ?? <String>{};

  final String? city;
  final int? maxPrice;
  final double? minRooms;
  final Set<String> amenities; // PropertyFeatureSet keys, e.g. feat_pets
  final bool nearTrain;
  final String rawText;

  bool get isEmpty =>
      city == null &&
      maxPrice == null &&
      minRooms == null &&
      amenities.isEmpty &&
      !nearTrain;

  // Human summary of what we understood — shown back to the user for trust.
  String describe() {
    final parts = <String>[];
    if (city != null) parts.add('📍 $city');
    if (minRooms != null) parts.add('🛏️ ${_roomsLabel(minRooms!)} חד׳');
    if (maxPrice != null) parts.add('💰 עד ₪${_money(maxPrice!)}');
    if (nearTrain) parts.add('🚉 ליד הרכבת');
    for (final a in amenities) {
      parts.add(SmartSearch.amenityTag(a));
    }
    return parts.join('  ·  ');
  }
}

class ScoredProperty {
  ScoredProperty(this.property, this.score, this.tags, this.trainKm, this.exact);
  final RentalProperty property;
  final double score;
  final List<String> tags;
  final double? trainKm;
  final bool exact; // meets the hard must-haves
}

// Lenient, ranked apartment matcher. Never dead-ends: it scores the whole
// catalogue and returns the best matches, so a legitimate request that exists
// in the data always surfaces (ranked first), and a near-miss still gets the
// closest options instead of "no results".
//
// ponytail: train proximity uses a static list of major Israel Railways
// stations + Haversine — no transit API needed. Coordinates are approximate;
// swap for a real GTFS/stations feed if precision matters.
class SmartSearch {
  static SearchQuery parse(String text, {Map<String, dynamic> llm = const {}}) {
    final t = text.toLowerCase();

    // rooms — "3 חדרים" / "3 חד׳" / llm
    double? rooms = _toDouble(llm['rooms']);
    final rm = RegExp(r'(\d+(?:\.\d)?)\s*(?:חדר|חדרים|חד)').firstMatch(text);
    if (rm != null) rooms = double.tryParse(rm.group(1)!) ?? rooms;

    // budget — largest plausible rent figure, or llm
    int? price = _toInt(llm['price']);
    final nums = RegExp(r'\d[\d,]{2,}')
        .allMatches(text)
        .map((m) => int.tryParse(m.group(0)!.replaceAll(',', '')) ?? 0)
        .where((n) => n >= 1500 && n <= 60000)
        .toList();
    if (nums.isNotEmpty) price = nums.reduce(math.max);

    // city
    String? city = _str(llm['city']);
    for (final c in _cities) {
      if (text.contains(c)) {
        city = c;
        break;
      }
    }

    // amenities (Hebrew keywords + llm feat_ flags)
    final amenities = <String>{};
    _amenityKeywords.forEach((key, words) {
      if (words.any((w) => t.contains(w.toLowerCase()))) amenities.add(key);
    });
    llm.forEach((k, v) {
      if (k.startsWith('feat_') && _truthy(v)) amenities.add(k);
    });

    final nearTrain = const [
      'רכבת', 'תחנת רכבת', 'ליד הרכבת', 'קרוב לרכבת', 'train', 'railway'
    ].any((w) => text.contains(w) || t.contains(w));

    return SearchQuery(
      city: city,
      maxPrice: price,
      minRooms: rooms,
      amenities: amenities,
      nearTrain: nearTrain,
      rawText: text,
    );
  }

  static List<ScoredProperty> rank(
    List<RentalProperty> props,
    SearchQuery q, {
    int limit = 8,
  }) {
    final scored = props.map((p) => _score(p, q)).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  static ScoredProperty _score(RentalProperty p, SearchQuery q) {
    double s = 1;
    final tags = <String>[];
    bool exact = true;

    if (q.city != null) {
      final hay = '${p.city} ${p.neighborhood} ${p.street}';
      if (hay.contains(q.city!)) {
        s += 5;
      } else {
        s -= 3;
        exact = false;
      }
    }

    if (q.maxPrice != null && p.price > 0) {
      if (p.price <= q.maxPrice!) {
        s += 3;
      } else {
        final over = (p.price - q.maxPrice!) / q.maxPrice!;
        s -= over > 0.5 ? 4 : over * 6;
        if (over > 0.1) exact = false;
      }
    }

    if (q.minRooms != null) {
      final diff = p.rooms - q.minRooms!;
      if (diff >= 0 && diff <= 1) {
        s += 3;
      } else if (diff.abs() <= 0.5) {
        s += 2;
      } else {
        s -= (p.rooms < q.minRooms! ? 1.5 : 0.5) * diff.abs();
        if (p.rooms < q.minRooms!) exact = false;
      }
    }

    for (final key in q.amenities) {
      if (p.featureFlags.isEnabled(key)) {
        s += 2;
        tags.add(amenityTag(key));
      } else {
        s -= 0.7;
        exact = false;
      }
    }

    double? trainKm;
    if (p.lat != 0 && p.lon != 0) {
      trainKm = _nearestStationKm(p.lat, p.lon);
      if (q.nearTrain && trainKm != null) {
        if (trainKm < 1.0) {
          s += 5;
          tags.add('🚉 ~${(trainKm * 12).round()} דק׳ מהרכבת');
        } else if (trainKm < 2.5) {
          s += 2.5;
          tags.add('🚉 ${trainKm.toStringAsFixed(1)} ק״מ מהרכבת');
        } else {
          s -= trainKm > 5 ? 3 : 1;
          exact = false;
        }
      }
    } else if (q.nearTrain) {
      exact = false;
    }

    if (p.isVerifiedListing) s += 0.5;

    return ScoredProperty(p, s, tags, trainKm, exact);
  }

  // ── train stations (approx coords) ─────────────────────────────────────────
  static double? _nearestStationKm(double lat, double lon) {
    double? best;
    for (final st in _stations) {
      final d = _haversineKm(lat, lon, st.$2, st.$3);
      if (best == null || d < best) best = d;
    }
    return best;
  }

  static double _haversineKm(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0;
    final dLa = _rad(la2 - la1);
    final dLo = _rad(lo2 - lo1);
    final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
        math.cos(_rad(la1)) *
            math.cos(_rad(la2)) *
            math.sin(dLo / 2) *
            math.sin(dLo / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180.0;

  static const List<(String, double, double)> _stations = [
    ('תל אביב סבידור מרכז', 32.0833, 34.7991),
    ('תל אביב השלום', 32.0734, 34.7920),
    ('תל אביב ההגנה', 32.0540, 34.7940),
    ('תל אביב אוניברסיטה', 32.1140, 34.8040),
    ('הרצליה', 32.1660, 34.8340),
    ('נתניה', 32.3180, 34.8570),
    ('רעננה מערב', 32.1820, 34.8510),
    ('כפר סבא נורדאו', 32.1670, 34.9160),
    ('פתח תקווה קריית אריה', 32.1030, 34.8570),
    ('בני ברק', 32.0930, 34.8340),
    ('ראשון לציון הראשונים', 31.9620, 34.8060),
    ('רחובות', 31.9170, 34.7970),
    ('לוד', 31.9480, 34.8720),
    ('רמלה', 31.9280, 34.8640),
    ('מודיעין מרכז', 31.9010, 35.0070),
    ('בית שמש', 31.7470, 34.9880),
    ('ירושלים יצחק נבון', 31.7870, 35.2030),
    ('אשדוד עד הלום', 31.7700, 34.6610),
    ('אשקלון', 31.6520, 34.5780),
    ('באר שבע מרכז', 31.2430, 34.7980),
    ('חיפה חוף הכרמל', 32.7940, 34.9570),
    ('חיפה בת גלים', 32.8310, 34.9890),
    ('חיפה מרכז השמונה', 32.8210, 35.0000),
  ];

  // ── keyword maps ────────────────────────────────────────────────────────────
  static const Map<String, List<String>> _amenityKeywords = {
    'feat_renovated': ['משופצ', 'שיפוץ', 'renovated'],
    'feat_pets': ['כלב', 'כלבה', 'חתול', 'חיית מחמד', 'חיות מחמד', 'pet', 'dog'],
    'feat_parking': ['חניה', 'חנייה', 'parking'],
    'feat_balcony': ['מרפסת', 'balcony'],
    'feat_elevator': ['מעלית', 'elevator'],
    'feat_furnished': ['מרוהט', 'ריהוט', 'furnished'],
    'feat_mamad': ['ממ"ד', 'ממד', 'ממ״ד', 'mamad', 'shelter'],
    'feat_garden': ['גינה', 'גינת', 'garden'],
    'feat_air': ['מזגן', 'מיזוג', 'ac'],
    'feat_pool': ['בריכה', 'pool'],
    'feat_gym': ['חדר כושר', 'כושר', 'gym'],
    'feat_storage': ['מחסן', 'storage'],
    'feat_safe': ['ממוגן', 'סורגים'],
    'feat_furnished_equipped': ['מאובזר'],
  };

  static const List<String> _cities = [
    'תל אביב', 'ירושלים', 'חיפה', 'רמת גן', 'גבעתיים', 'הרצליה', 'נתניה',
    'רעננה', 'כפר סבא', 'ראשון לציון', 'פתח תקווה', 'באר שבע', 'רחובות',
    'אשדוד', 'אשקלון', 'מודיעין', 'חולון', 'בת ים', 'רמת השרון', 'בני ברק',
    'לוד', 'רמלה', 'גבעת שמואל', 'קריית אונו', 'אור יהודה', 'הוד השרון',
  ];

  static String amenityTag(String key) {
    switch (key) {
      case 'feat_renovated':
        return '✦ משופצת';
      case 'feat_pets':
        return '🐾 ידידותי לחיות';
      case 'feat_parking':
        return '🅿️ חניה';
      case 'feat_balcony':
        return '🌤️ מרפסת';
      case 'feat_elevator':
        return '🛗 מעלית';
      case 'feat_furnished':
        return '🛋️ מרוהט';
      case 'feat_mamad':
        return '🛡️ ממ״ד';
      case 'feat_garden':
        return '🌳 גינה';
      case 'feat_air':
        return '❄️ מיזוג';
      case 'feat_pool':
        return '🏊 בריכה';
      case 'feat_gym':
        return '🏋️ חדר כושר';
      case 'feat_storage':
        return '📦 מחסן';
      case 'feat_safe':
        return '🔒 ממוגן';
      default:
        return key.replaceFirst('feat_', '');
    }
  }

  // ── value helpers ────────────────────────────────────────────────────────────
  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.round();
    final s = v.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return s.isEmpty ? null : int.tryParse(s);
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return s.isEmpty ? null : double.tryParse(s);
  }

  static bool _truthy(dynamic v) =>
      v == true || v == 1 || v == '1' || v.toString().toLowerCase() == 'true';
}

String _roomsLabel(double r) =>
    r % 1 == 0 ? r.toInt().toString() : r.toString();

String _money(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
