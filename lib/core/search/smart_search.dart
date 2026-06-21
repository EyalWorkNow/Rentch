import 'dart:math' as math;

import 'package:dating_app/core/search/advanced_matcher.dart';
import 'package:dating_app/data/models/rental_models.dart';

// Parsed intent from a free-text request, e.g.:
//   "סטודיו משופץ בפלורנטין עד 6000, ידידותי לכלב, קרוב לרכבת"
//   "דירת 3-4 חדרים לזוג בין 5000 ל-7000 במרכז תל אביב"
class SearchQuery {
  SearchQuery({
    this.city,
    this.neighborhood,
    this.minPrice,
    this.maxPrice,
    this.minRooms,
    this.maxRooms,
    this.propertyType,
    Set<String>? amenities,
    this.nearTrain = false,
    this.cheapPreference = false,
    this.rawText = '',
  }) : amenities = amenities ?? <String>{};

  final String? city;
  final String? neighborhood;
  final int? minPrice;
  final int? maxPrice;
  final double? minRooms;
  final double? maxRooms;
  final String? propertyType; // normalised, matched against RentalProperty.propertyType
  final Set<String> amenities; // PropertyFeatureSet keys, e.g. feat_pets
  final bool nearTrain;
  final bool cheapPreference; // user asked for "the cheapest"
  final String rawText;

  bool get isEmpty =>
      city == null &&
      neighborhood == null &&
      minPrice == null &&
      maxPrice == null &&
      minRooms == null &&
      maxRooms == null &&
      propertyType == null &&
      amenities.isEmpty &&
      !nearTrain;

  // Enough was understood on-device that we can skip the (slower) model call.
  bool get hasEssentials =>
      city != null ||
      neighborhood != null ||
      maxPrice != null ||
      minPrice != null ||
      minRooms != null ||
      propertyType != null;

  String describe() {
    final parts = <String>[];
    if (neighborhood != null) {
      parts.add('📍 $neighborhood${city != null ? ', $city' : ''}');
    } else if (city != null) {
      parts.add('📍 $city');
    }
    if (propertyType != null) parts.add('🏠 $propertyType');
    if (minRooms != null || maxRooms != null) {
      parts.add('🛏️ ${_roomsRangeLabel(minRooms, maxRooms)} חד׳');
    }
    if (minPrice != null || maxPrice != null) {
      parts.add('💰 ${_priceRangeLabel(minPrice, maxPrice)}');
    }
    if (nearTrain) parts.add('🚉 ליד הרכבת');
    if (cheapPreference) parts.add('🏷️ הכי משתלם');
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
  final bool exact;
}

// Smarter, more flexible matcher. Reads free Hebrew text into a rich query
// (ranges, neighborhoods, property type, persona hints), then ranks the whole
// catalogue with weighted scoring that also rewards popular and fresh listings.
// Never dead-ends — always returns the best matches.
class SmartSearch {
  static SearchQuery parse(String text, {Map<String, dynamic> llm = const {}}) {
    final t = text.toLowerCase();

    // ── rooms (range / half / studio / "+") ─────────────────────────────────
    double? minRooms;
    double? maxRooms;
    final roomRange = RegExp(r'(\d(?:\.\d)?)\s*[-־–]\s*(\d(?:\.\d)?)\s*(?:חדר|חד)')
        .firstMatch(text);
    final roomBetween =
        RegExp(r'בין\s*(\d(?:\.\d)?)\s*ל[-־]?\s*(\d(?:\.\d)?)\s*(?:חדר|חד)')
            .firstMatch(text);
    if (roomRange != null || roomBetween != null) {
      final m = roomRange ?? roomBetween!;
      minRooms = double.tryParse(m.group(1)!);
      maxRooms = double.tryParse(m.group(2)!);
    } else {
      final half =
          RegExp(r'(\d|אחד|שני|שתי|שלוש|שלושה|ארבע|ארבעה|חמש|חמישה)\s*וחצי')
              .firstMatch(text);
      final single =
          RegExp(r'(\d(?:\.\d)?)\s*(?:חדר|חדרים|חד)').firstMatch(text);
      if (half != null) {
        minRooms = (_wordToNum(half.group(1)!) ?? 0) + 0.5;
      } else if (single != null) {
        minRooms = double.tryParse(single.group(1)!);
      }
      // "3+" → open-ended max (just a min).
      if (single != null && RegExp(r'\d\s*\+').hasMatch(text)) {
        maxRooms = null;
      }
    }
    minRooms ??= _toDouble(llm['rooms']);

    // ── property type ───────────────────────────────────────────────────────
    String? propertyType;
    for (final entry in _propertyTypes.entries) {
      if (entry.value.any((w) => t.contains(w))) {
        propertyType = entry.key;
        break;
      }
    }
    // studio / sub-unit imply a small place
    if (propertyType == 'סטודיו' || propertyType == 'יחידת דיור') {
      minRooms ??= 1;
      maxRooms ??= 2;
    }

    // ── budget (range / around / max / min, with "אלף") ─────────────────────
    int? minPrice;
    int? maxPrice;
    int? amount(String s) {
      final e = RegExp(r'(\d+)\s*(וחצי\s*)?(?:אלף|אלפים)').firstMatch(s);
      if (e != null) {
        return (int.tryParse(e.group(1)!) ?? 0) * 1000 +
            (e.group(2) != null ? 500 : 0);
      }
      final n = RegExp(r'\d[\d,]{2,}').firstMatch(s.replaceAll(',', ''));
      return n != null ? int.tryParse(n.group(0)!) : null;
    }

    final between = RegExp(r'בין\s*(.{1,12}?)\s*ל[-־]?\s*(.{1,12}?)(?:\s|$|,)')
        .firstMatch(text);
    final around = RegExp(r'(?:בערך|סביב|כ[-־]|בסביבות)\s*(.{1,12}?)(?:\s|$|,)')
        .firstMatch(text);
    final upto = RegExp(r'(?:עד|מקסימום|מקס|לכל היותר|מתחת ל[-־]?)\s*(.{1,12}?)(?:\s|$|,)')
        .firstMatch(text);
    final from = RegExp(r'(?:מ[-־]|לפחות|מעל|החל מ[-־]?)\s*(.{1,12}?)(?:\s|$|,)')
        .firstMatch(text);

    if (between != null) {
      minPrice = amount(between.group(1)!);
      maxPrice = amount(between.group(2)!);
    } else if (around != null) {
      final a = amount(around.group(1)!);
      if (a != null && a >= 1500) {
        minPrice = (a * 0.85).round();
        maxPrice = (a * 1.15).round();
      }
    } else {
      if (upto != null) maxPrice = amount(upto.group(1)!);
      if (from != null) minPrice = amount(from.group(1)!);
      // bare number with a price hint
      if (maxPrice == null && minPrice == null) {
        final any = amount(text);
        if (any != null && any >= 1500 && any <= 60000) maxPrice = any;
      }
    }
    // sanity: drop tiny values that aren't budgets (e.g. room counts)
    if (minPrice != null && minPrice < 1500) minPrice = null;
    if (maxPrice != null && maxPrice < 1500) maxPrice = null;
    maxPrice ??= _toInt(llm['price']);

    final cheap = RegExp(r'זול|משתלם|במחיר טוב|כמה שפחות').hasMatch(text);

    // ── city & neighborhood ─────────────────────────────────────────────────
    String? city = _str(llm['city']);
    for (final c in _cities) {
      if (text.contains(c)) {
        city = c;
        break;
      }
    }
    String? neighborhood;
    for (final n in _neighborhoods) {
      if (text.contains(n)) {
        neighborhood = n;
        break;
      }
    }

    // ── amenities (keywords + llm flags) ─────────────────────────────────────
    final amenities = <String>{};
    _amenityKeywords.forEach((key, words) {
      if (words.any((w) => t.contains(w.toLowerCase()))) amenities.add(key);
    });
    llm.forEach((k, v) {
      if (k.startsWith('feat_') && _truthy(v)) amenities.add(k);
    });

    final nearTrain = const [
      'רכבת', 'תחנת רכבת', 'ליד הרכבת', 'קרוב לרכבת', 'train', 'railway'
    ].any((w) => text.contains(w));

    // ── persona soft defaults (only when rooms not stated) ──────────────────
    if (minRooms == null && maxRooms == null) {
      if (RegExp(r'סטודנט').hasMatch(text)) {
        minRooms = 1;
        maxRooms = 2;
      } else if (RegExp(r'משפח|ילד').hasMatch(text)) {
        minRooms = 3;
      } else if (RegExp(r'\bזוג\b|זוגי|בני זוג').hasMatch(text)) {
        minRooms = 2;
        maxRooms = 3;
      }
    }

    return SearchQuery(
      city: city,
      neighborhood: neighborhood,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minRooms: minRooms,
      maxRooms: maxRooms,
      propertyType: propertyType,
      amenities: amenities,
      nearTrain: nearTrain,
      cheapPreference: cheap,
      rawText: text,
    );
  }

  static List<ScoredProperty> rank(
    List<RentalProperty> props,
    SearchQuery q, {
    int limit = 10,
  }) {
    // Use advanced multi-dimensional matching if query has enough signal;
    // fall back to simpler scoring if vague.
    if (q.hasEssentials && props.isNotEmpty) {
      return rankAdvanced(props, q, limit: limit);
    }
    final scored = props.map((p) => _score(p, q)).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  // Advanced ranking using multi-dimensional user intent + property vectors.
  // Produces explainable match scores and handles complex user preferences.
  static List<ScoredProperty> rankAdvanced(
    List<RentalProperty> props,
    SearchQuery q, {
    int limit = 10,
  }) {
    if (props.isEmpty) return [];

    // Market statistics for normalization
    final medianPrice =
        props.map((p) => p.price).fold<double>(0, (a, b) => a + b) /
            props.length;
    final minRooms = props.map((p) => p.rooms).reduce(math.min);
    final maxRooms = props.map((p) => p.rooms).reduce(math.max);

    // Build user intent vector from query
    final userIntent = AdvancedMatcher.buildUserIntent(
      statedCityPreference: q.city != null,
      budgetStated: q.minPrice != null || q.maxPrice != null,
      roomsRangeStated: q.minRooms != null || q.maxRooms != null,
      minPrice: q.minPrice?.toDouble(),
      maxPrice: q.maxPrice?.toDouble(),
      amenityDemanding: q.amenities.length > 2,
      amenitiesCount: q.amenities.length,
      nearTrainRequired: q.nearTrain,
      cheapPreference: q.cheapPreference,
      urgentTone: false, // could infer from rawText
      flexibleTone: false, // could infer from rawText
    );

    // Score each property
    final matches = <({ScoredProperty scored, MatchScore detail})>[];
    for (final prop in props) {
      final propVec = AdvancedMatcher.buildPropertyVector(
        prop,
        minRoomMarket: minRooms,
        maxRoomMarket: maxRooms,
        medianPriceMarket: medianPrice,
        totalProperties: props.length,
      );

      final meetsHardConstraints = _checksConstraints(prop, q);
      final hasRequestedAmenities = _hasAmenities(prop, q);
      final transitProx = q.nearTrain && (AdvancedMatcher.nearestStationKm(prop.lat, prop.lon) ?? 10) < 2.5;

      final matchDetail = AdvancedMatcher.scoreMatch(
        userIntent,
        propVec,
        meetsHardConstraints: meetsHardConstraints,
        hasRequestedAmenities: hasRequestedAmenities,
        transitProximity: transitProx,
      );

      matches.add((
        scored: ScoredProperty(
          prop,
          matchDetail.totalScore / 100,
          [],
          AdvancedMatcher.nearestStationKm(prop.lat, prop.lon),
          meetsHardConstraints,
        ),
        detail: matchDetail,
      ));
    }

    // Sort by score (descending) and extract top N
    matches.sort((a, b) => b.detail.totalScore.compareTo(a.detail.totalScore));
    return matches.take(limit).map((m) {
      // Augment tags with explanation from advanced matcher
      final tags = [...m.scored.tags];
      if (m.detail.explanation.isNotEmpty) {
        tags.insert(0, '✨ ${m.detail.explanation}');
      }
      tags.insert(0, '${m.detail.fitPct}% fit');
      return ScoredProperty(
        m.scored.property,
        m.scored.score,
        tags,
        m.scored.trainKm,
        m.scored.exact,
      );
    }).toList();
  }

  static bool _checksConstraints(RentalProperty p, SearchQuery q) {
    if (q.city != null && !p.city.contains(q.city!)) return false;
    if (q.maxPrice != null && p.price > q.maxPrice!) return false;
    if (q.minPrice != null && p.price < q.minPrice!) return false;
    if (q.minRooms != null && p.rooms < q.minRooms!) return false;
    if (q.maxRooms != null && p.rooms > q.maxRooms!) return false;
    return true;
  }

  static bool _hasAmenities(RentalProperty p, SearchQuery q) =>
      q.amenities.any((a) => p.featureFlags.isEnabled(a));

  static ScoredProperty _score(RentalProperty p, SearchQuery q) {
    double s = 1;
    final tags = <String>[];
    // "exact" = the essentials the user stated (place / budget / size / type).
    bool exact = true;

    // location
    final hay = '${p.city} ${p.neighborhood} ${p.street}';
    if (q.neighborhood != null) {
      if (hay.contains(q.neighborhood!)) {
        s += 7;
        tags.add('📍 ${p.neighborhood.isNotEmpty ? p.neighborhood : q.neighborhood}');
      } else {
        s -= 3;
        exact = false;
      }
    }
    if (q.city != null) {
      if (hay.contains(q.city!)) {
        s += 5;
      } else {
        s -= 4;
        exact = false;
      }
    }

    // property type
    if (q.propertyType != null) {
      if (p.propertyType.contains(q.propertyType!) ||
          q.propertyType!.contains(p.propertyType)) {
        s += 3;
      } else {
        s -= 1.5;
        exact = false;
      }
    }

    // budget (min/max range)
    if (p.price > 0) {
      if (q.maxPrice != null) {
        if (p.price <= q.maxPrice!) {
          s += 3;
        } else {
          final over = (p.price - q.maxPrice!) / q.maxPrice!;
          s -= over > 0.5 ? 5 : over * 6;
          if (over > 0.1) exact = false;
        }
      }
      if (q.minPrice != null && p.price < q.minPrice!) {
        s -= 1.5; // below the floor (e.g. range) — mild
      }
      if (q.cheapPreference && q.maxPrice != null && q.maxPrice! > 0) {
        s += (1 - (p.price / q.maxPrice!)).clamp(0.0, 1.0) * 2;
      }
    }

    // rooms (min/max range)
    if (q.minRooms != null || q.maxRooms != null) {
      final lo = q.minRooms ?? 0;
      final hi = q.maxRooms ?? 99;
      if (p.rooms >= lo - 0.5 && p.rooms <= hi + 0.5) {
        s += 3;
      } else if (p.rooms < lo) {
        s -= 1.2 * (lo - p.rooms);
        exact = false;
      } else {
        s -= 0.5 * (p.rooms - hi); // a bit bigger than asked — minor
      }
    }

    // amenities — soft boosts
    for (final key in q.amenities) {
      if (p.featureFlags.isEnabled(key)) {
        s += 2;
        tags.add(amenityTag(key));
      } else {
        s -= 0.4;
      }
    }

    // train proximity — soft boost
    double? trainKm;
    if (p.lat != 0 && p.lon != 0) {
      trainKm = _nearestStationKm(p.lat, p.lon);
      if (q.nearTrain && trainKm != null) {
        if (trainKm < 1.0) {
          s += 4;
          tags.add('🚉 ~${(trainKm * 12).round()} דק׳ מהרכבת');
        } else if (trainKm < 2.5) {
          s += 2;
          tags.add('🚉 ${trainKm.toStringAsFixed(1)} ק״מ מהרכבת');
        } else {
          s -= 1;
        }
      }
    }

    // smarter tie-breakers: popularity + freshness + verified
    s += _popularityBoost(p.marketSignals);
    s += _freshnessBoost(p.createdAt);
    if (p.isVerifiedListing) s += 0.5;

    return ScoredProperty(p, s, tags, trainKm, exact);
  }

  // Small boost (0..~1.2) from real engagement — surfaces listings people act on.
  static double _popularityBoost(PropertyMarketSignals m) {
    final pop = m.views + m.likes * 3 + m.saves * 4 + m.contactRequests * 6;
    if (pop <= 0) return 0;
    return (math.log(1 + pop) / math.log(1 + 600)).clamp(0.0, 1.0) * 1.2;
  }

  // Newer listings get a gentle lift (decays over ~30 days).
  static double _freshnessBoost(DateTime? createdAt) {
    if (createdAt == null) return 0;
    final days = DateTime.now().difference(createdAt).inDays;
    if (days < 0) return 0;
    return (1 - days / 30).clamp(0.0, 1.0) * 0.8;
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
    'feat_renovated': ['משופצ', 'שיפוץ', 'חדשה', 'renovated'],
    'feat_pets': ['כלב', 'כלבה', 'חתול', 'חיית מחמד', 'חיות מחמד', 'pet', 'dog'],
    'feat_parking': ['חניה', 'חנייה', 'parking'],
    'feat_balcony': ['מרפסת', 'מרפסות', 'balcony'],
    'feat_elevator': ['מעלית', 'elevator'],
    'feat_furnished': ['מרוהט', 'ריהוט', 'מאובזר', 'furnished'],
    'feat_mamad': ['ממ"ד', 'ממד', 'ממ״ד', 'מקלט', 'mamad', 'shelter'],
    'feat_garden': ['גינה', 'גינת', 'חצר', 'garden'],
    'feat_air': ['מזגן', 'מיזוג', 'ממוזג', 'ac'],
    'feat_pool': ['בריכה', 'pool'],
    'feat_gym': ['חדר כושר', 'כושר', 'gym'],
    'feat_storage': ['מחסן', 'storage'],
    'feat_sun': ['שמש', 'מואר', 'אור'],
    'feat_safe': ['ממוגן', 'סורגים'],
    'feat_internet': ['אינטרנט', 'סיבים', 'wifi'],
    'feat_laundry': ['מכונת כביסה', 'כביסה'],
  };

  static const Map<String, List<String>> _propertyTypes = {
    'סטודיו': ['סטודיו', 'studio'],
    'יחידת דיור': ['יחידת דיור', 'יחידה'],
    'דירת גן': ['דירת גן', 'גן '],
    'פנטהאוז': ['פנטהאוז', 'פנטהאוס', 'penthouse'],
    'דופלקס': ['דופלקס', 'duplex'],
    'גג': ['דירת גג', 'גג'],
    'דירה': ['דירה', 'apartment'],
  };

  static const List<String> _cities = [
    'תל אביב', 'ירושלים', 'חיפה', 'רמת גן', 'גבעתיים', 'הרצליה', 'נתניה',
    'רעננה', 'כפר סבא', 'ראשון לציון', 'פתח תקווה', 'באר שבע', 'רחובות',
    'אשדוד', 'אשקלון', 'מודיעין', 'חולון', 'בת ים', 'רמת השרון', 'בני ברק',
    'לוד', 'רמלה', 'גבעת שמואל', 'קריית אונו', 'אור יהודה', 'הוד השרון',
  ];

  // Well-known neighborhoods — narrows results within a city when mentioned.
  static const List<String> _neighborhoods = [
    'פלורנטין', 'נווה צדק', 'רוטשילד', 'כרם התימנים', 'לב העיר', 'הצפון הישן',
    'הצפון החדש', 'רמת אביב', 'בבלי', 'יד אליהו', 'רמת החייל', 'שפירא',
    'נחלת יצחק', 'תל ברוך', 'אפקה', 'מונטיפיורי', 'הקריה', 'נווה שאנן',
    'רחביה', 'בקעה', 'נחלאות', 'תלפיות', 'קטמון', 'גילה', 'פסגת זאב',
    'הדר', 'כרמל', 'נווה שאנן', 'ואדי ניסנס', 'רמות', 'קרית חיים',
    'רמת אביב ג', 'גבעת שמואל', 'מרכז העיר',
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
      case 'feat_sun':
        return '☀️ מואר';
      case 'feat_safe':
        return '🔒 ממוגן';
      case 'feat_internet':
        return '🌐 אינטרנט';
      case 'feat_laundry':
        return '🧺 כביסה';
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

  static double? _wordToNum(String w) {
    const map = {
      'אחד': 1, 'אחת': 1, 'שני': 2, 'שתי': 2, 'שניים': 2, 'שתיים': 2,
      'שלוש': 3, 'שלושה': 3, 'ארבע': 4, 'ארבעה': 4, 'חמש': 5, 'חמישה': 5,
    };
    return map[w]?.toDouble() ?? double.tryParse(w);
  }

  static bool _truthy(dynamic v) =>
      v == true || v == 1 || v == '1' || v.toString().toLowerCase() == 'true';
}

String _roomsRangeLabel(double? lo, double? hi) {
  String f(double r) => r % 1 == 0 ? r.toInt().toString() : r.toString();
  if (lo != null && hi != null) return lo == hi ? f(lo) : '${f(lo)}-${f(hi)}';
  if (lo != null) return '${f(lo)}+';
  return 'עד ${f(hi!)}';
}

String _priceRangeLabel(int? lo, int? hi) {
  String m(int v) => '₪${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (x) => '${x[1]},')}';
  if (lo != null && hi != null) return '${m(lo)}–${m(hi)}';
  if (hi != null) return 'עד ${m(hi)}';
  return 'מ-${m(lo!)}';
}
