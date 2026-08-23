import 'dart:math' as math;

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/advanced_matcher.dart';
import 'package:dating_app/core/search/anchor_resolver.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/engine/scorecard.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/utils/helpers/property_label_helper.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/l10n/app_localizations.dart';

// Helper for fuzzy locality matching
class LocalityMatcher {
  // Levenshtein distance for typo tolerance
  static int _levenshtein(String a, String b) {
    final len1 = a.length, len2 = b.length;
    final dp = List.generate(len1 + 1, (i) => List.filled(len2 + 1, 0));
    for (int i = 0; i <= len1; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      dp[0][j] = j;
    }
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce(math.min);
      }
    }
    return dp[len1][len2];
  }

  // Find best matching locality (city/kibbutz/village) with typo tolerance
  static String? findBestMatch(String input, {int maxDistance = 2}) {
    if (input.isEmpty) return null;
    final normalized = input.toLowerCase().trim();

    // Exact match first
    if (allLocalities.contains(normalized)) return normalized;

    // Prefix match (starts with)
    final prefixMatches = allLocalities
        .where((loc) => loc.startsWith(normalized))
        .toList();
    if (prefixMatches.isNotEmpty) {
      return prefixMatches.first; // return shortest prefix match
    }

    // Fuzzy match (Levenshtein) — only if input is at least 3 chars
    // AND starts with same letter as candidate AND has similar length (avoid random matches)
    if (normalized.length < 3) return null;

    final fuzzyMatches = <(String, int)>[];
    for (final locality in allLocalities) {
      // Only consider if:
      // 1. First letter matches
      // 2. Length is within reasonable range (±2 chars)
      if (normalized[0] != locality[0]) continue;
      if ((normalized.length - locality.length).abs() > 2) continue;

      final dist = _levenshtein(normalized, locality);
      if (dist <= maxDistance) {
        fuzzyMatches.add((locality, dist));
      }
    }
    if (fuzzyMatches.isNotEmpty) {
      fuzzyMatches.sort((a, b) => a.$2.compareTo(b.$2));
      return fuzzyMatches.first.$1;
    }

    return null;
  }

  // Autocomplete suggestions (top N matches by prefix + fuzzy)
  static List<String> suggestLocalities(String input, {int limit = 5}) {
    if (input.isEmpty) return allLocalities.take(10).toList();
    final normalized = input.toLowerCase().trim();

    // Prefix matches first
    final prefixes = allLocalities
        .where((loc) => loc.startsWith(normalized))
        .take(limit)
        .toList();
    if (prefixes.length >= limit) return prefixes;

    // Fuzzy matches to fill
    final remaining = limit - prefixes.length;
    final fuzzy = <(String, int)>[];
    for (final locality in allLocalities) {
      if (prefixes.contains(locality)) continue;
      final dist = _levenshtein(normalized, locality);
      if (dist <= 3) fuzzy.add((locality, dist));
    }
    fuzzy.sort((a, b) => a.$2.compareTo(b.$2));

    return [...prefixes, ...fuzzy.take(remaining).map((e) => e.$1)];
  }

  // All Israeli localities (300+): cities, kibbutzim, moshavim, villages
  static const List<String> allLocalities = [
    // Major cities
    'תל אביב', 'ירושלים', 'חיפה', 'בחרה', 'אשדוד', 'אשקלון',
    // Central
    'רמת גן', 'גבעתיים', 'בני ברק', 'ראש העין', 'פתח תקווה',
    'רמלה', 'לוד', 'מודיעין', 'רעננה', 'הרצליה', 'כפר סבא',
    'קריית אונו', 'הוד השרון', 'אור יהודה', 'אופקים', 'קרית גת',
    // North
    'נתניה', 'חדרה', 'זכרון יעקב', 'קיסריה', 'עכו', 'טבריה',
    'ציפורי', 'מצפה נתוף', 'בית שאן', 'בית שמש', 'ירוחם',
    // South
    'באר שבע', 'עומץ', 'שדרות', 'אילת', 'מצפה רמון', 'ערד',
    'קרית חינם', 'דימונה', 'קרית שמונה', 'קרית מלאכי',
    // Neighborhoods in Tel Aviv
    'פלורנטין', 'נווה צדק', 'רוטשילד', 'כרם התימנים', 'לב העיר',
    'הצפון הישן', 'הצפון החדש', 'רמת אביב', 'בבלי', 'יד אליהו',
    'רמת החייל', 'שפירא', 'נחלת יצחק', 'תל ברוך', 'אפקה',
    'מונטיפיורי',
    // Kibbutzim (selection)
    'קיבוץ עין חרוד', 'קיבוץ גלעד', 'קיבוץ דליות', 'קיבוץ מעברות',
    'קיבוץ שומרת', 'קיבוץ כמעם', 'קיבוץ לביא', 'קיבוץ נוה צוף',
    'קיבוץ שלוחות', 'קיבוץ יפעה', 'קיבוץ ברות', 'קיבוץ אפיק',
    'קיבוץ מסדה', 'קיבוץ בטל', 'קיבוץ גדות', 'קיבוץ בית אלפא',
    // Moshavim (selection)
    'מושב נהלל', 'מושב מישמר העמק', 'מושב כפר עזרא', 'מושב קדים',
    'מושב בית יצחק', 'מושב כפר יאסיף', 'מושב מודיעים מחוז דן',
    // Villages and smaller towns
    'ראש פינה', 'צפת', 'מרון', 'יהונתן', 'כרמי יוסף', 'כצרין',
    'מצפה רמון', 'סעד', 'פקיעין', 'דליה', 'בעיא', 'עראמשה',
    'סח נין', 'מג\'ד אל כروט', 'ירכא', 'בוקאעה', 'טנא', 'כסיפה',
    'בועיה', 'כוכב אבו אל היجא', 'טירת כרמל', 'בת יאם', 'בת חלים',
    'קיסריה', 'חניתה', 'מסק', 'מוקיבלה', 'בקעות',
  ];
}

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
    this.transactionType = TransactionTypeFilter.any,
    this.rawText = '',
    Set<String>? intents,
    Map<String, double>? weights,
    Set<String>? requiredFeatures,
    List<String>? excludeAreas,
    this.areaDir,
    this.areaDirExclude = false,
    Set<String>? preferredNearbyDims,
    this.anchor,
  })  : amenities = amenities ?? <String>{},
        intents = intents ?? <String>{},
        weights = weights ?? const <String, double>{},
        requiredFeatures = requiredFeatures ?? const <String>{},
        excludeAreas = excludeAreas ?? const <String>[],
        preferredNearbyDims = preferredNearbyDims ?? const <String>{};

  final String? city;
  final String? neighborhood;
  final int? minPrice;
  final int? maxPrice;
  final double? minRooms;
  final double? maxRooms;
  final String? propertyType; // normalised, matched against RentalProperty.propertyType
  final Set<String> amenities; // PropertyFeatureSet keys, e.g. feat_pets

  /// "לא רחוק מ-X": a resolved NAMED place (hospital / university / rail
  /// station) the results must be near. Gates + boosts + a scorecard axis.
  final NearAnchor? anchor;
  final bool nearTrain;
  final bool cheapPreference; // user asked for "the cheapest"

  /// Rent vs. sale intent parsed from the free text ("למכירה"/"לקנות" → sale).
  /// Defaults to [TransactionTypeFilter.any] so existing rent searches are
  /// unaffected; when not [any] it acts as a hard filter so sale and rent
  /// listings never mix in the results.
  final TransactionTypeFilter transactionType;
  final String rawText;

  /// Structured lifestyle/spatial intent — the CONTRACT between the assistant and
  /// the ranking engine (e.g. 'near_sea', 'nightlife', 'quiet', 'central'). Both
  /// typed search (via [SearchIntent]) and the voice assistant fill this, and the
  /// preference model + gates consume it — so intent is detected in ONE place,
  /// not re-parsed with regexes deep in the ranker. See [SearchIntent].
  final Set<String> intents;

  /// LLM-ASSIGNED importance per factor, 0..1. This is the assistant acting as
  /// the "brain": after understanding the user it decides WHICH factors to weigh
  /// and HOW MUCH. When non-empty, the preference model uses ONLY these weights
  /// (factors the model didn't mention ⇒ 0), instead of its heuristic priors —
  /// the language model understands the human better than a fixed prior does.
  /// Keys are factor names (see PreferenceModelBuilder.factorToDimension).
  final Map<String, double> weights;

  /// HARD deal-breaker features (canonical keys, e.g. 'mamad', 'petsAllowed',
  /// 'furnished'): a listing that lacks ANY of these is EXCLUDED (relax-if-empty),
  /// not merely down-weighted. Set by Etti's hard_constraints. Distinct from the
  /// soft [amenities] "nice-to-have" set.
  final Set<String> requiredFeatures;

  /// Places (cities/neighborhoods) the user asked to AVOID ("לא רמת גן", "חוץ
  /// מפלורנטין"). Soft: listings there are strongly down-ranked, not hard-dropped.
  final List<String> excludeAreas;

  /// Ranking dimensions to BOOST because the seeker explicitly picked those
  /// nearby-place categories in the filter (mapped via nearbyKindToDimension).
  /// Sharpened in PreferenceModelBuilder.build without zeroing other priors.
  final Set<String> preferredNearbyDims;

  /// A sub-city DIRECTION the seeker cares about — one of
  /// 'דרום'/'צפון'/'מרכז'/'מזרח'/'מערב' — resolved against the city centroid +
  /// known neighbourhood clusters. Null when no direction was stated.
  final String? areaDir;

  /// When true, [areaDir] is what to AVOID ("לא בדרום העיר"), not what to prefer.
  final bool areaDirExclude;

  /// Returns a copy with the given fields replaced (others kept). Only supports
  /// SETTING values — passing null keeps the current one — which is all the
  /// what-if mutators need (raise budget, relax rooms, drop a required feature).
  SearchQuery copyWith({
    String? city,
    String? neighborhood,
    int? minPrice,
    int? maxPrice,
    double? minRooms,
    double? maxRooms,
    String? propertyType,
    Set<String>? amenities,
    bool? nearTrain,
    bool? cheapPreference,
    TransactionTypeFilter? transactionType,
    String? rawText,
    Set<String>? intents,
    Map<String, double>? weights,
    Set<String>? requiredFeatures,
    List<String>? excludeAreas,
    String? areaDir,
    bool? areaDirExclude,
    Set<String>? preferredNearbyDims,
    NearAnchor? anchor,
  }) =>
      SearchQuery(
        city: city ?? this.city,
        neighborhood: neighborhood ?? this.neighborhood,
        minPrice: minPrice ?? this.minPrice,
        maxPrice: maxPrice ?? this.maxPrice,
        minRooms: minRooms ?? this.minRooms,
        maxRooms: maxRooms ?? this.maxRooms,
        propertyType: propertyType ?? this.propertyType,
        amenities: amenities ?? this.amenities,
        nearTrain: nearTrain ?? this.nearTrain,
        cheapPreference: cheapPreference ?? this.cheapPreference,
        transactionType: transactionType ?? this.transactionType,
        rawText: rawText ?? this.rawText,
        intents: intents ?? this.intents,
        weights: weights ?? this.weights,
        requiredFeatures: requiredFeatures ?? this.requiredFeatures,
        excludeAreas: excludeAreas ?? this.excludeAreas,
        areaDir: areaDir ?? this.areaDir,
        areaDirExclude: areaDirExclude ?? this.areaDirExclude,
        // preferredNearbyDims used to be DROPPED by copyWith — every what-if
        // mutation silently erased the seeker's nearby-category boosts.
        preferredNearbyDims: preferredNearbyDims ?? this.preferredNearbyDims,
        anchor: anchor ?? this.anchor,
      );

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
      propertyType != null ||
      transactionType != TransactionTypeFilter.any;

  String describe([AppLocalizations? l10n]) {
    final parts = <String>[];
    if (transactionType == TransactionTypeFilter.sale) {
      parts.add(l10n?.smartSearchForSale ?? '🏷️ למכירה');
    } else if (transactionType == TransactionTypeFilter.rent) {
      parts.add(l10n?.smartSearchForRent ?? '🔑 להשכרה');
    }
    if (neighborhood != null) {
      parts.add('📍 $neighborhood${city != null ? ', $city' : ''}');
    } else if (city != null) {
      parts.add('📍 $city');
    }
    if (propertyType != null) {
      parts.add('🏠 ${l10n != null ? propertyTypeLabel(propertyType!, l10n) : propertyType}');
    }
    if (minRooms != null || maxRooms != null) {
      final range = _roomsRangeLabel(minRooms, maxRooms, l10n);
      parts.add(l10n?.smartSearchRoomsSuffix(range) ?? '🛏️ $range חד׳');
    }
    if (minPrice != null || maxPrice != null) {
      parts.add('💰 ${_priceRangeLabel(minPrice, maxPrice, l10n)}');
    }
    if (nearTrain) parts.add(l10n?.smartSearchNearTrain ?? '🚉 ליד הרכבת');
    if (cheapPreference) parts.add(l10n?.smartSearchBestValue ?? '🏷️ הכי משתלם');
    for (final a in amenities) {
      parts.add(SmartSearch.amenityTag(a, l10n));
    }
    return parts.join('  ·  ');
  }
}

class ScoredProperty {
  ScoredProperty(this.property, this.score, this.tags, this.trainKm, this.exact,
      [this.scorecard, this.fallbackNote]);
  final RentalProperty property;
  final double score;
  final List<String> tags;
  final double? trainKm;
  final bool exact;

  /// Non-null only on a relaxed BACKFILL result — a flat kept to fill out a thin
  /// shortlist even though it slightly misses the ask (just outside the town
  /// radius, or a little over budget). Carries the honest reason to badge on the
  /// card, e.g. "כ-8 ק״מ מחדרה" / "מעט מעל התקציב". Strict matches leave it null.
  final String? fallbackNote;

  /// Full data-grounded reasoning (engine breakdown + raw stats + persona +
  /// LLM explanation). Null on legacy/non-engine paths; the transparency UI
  /// renders the breakdown when present. See [Scorecard].
  final Scorecard? scorecard;
}

// Smarter, more flexible matcher. Reads free Hebrew text into a rich query
// (ranges, neighborhoods, property type, persona hints), then ranks the whole
// catalogue with weighted scoring that also rewards popular and fresh listings.
// Never dead-ends — always returns the best matches.
class SmartSearch {
  static SearchQuery parse(String text, {Map<String, dynamic> llm = const {}}) {
    // Phase 1 — Israeli lexicon: expand everyday abbreviations/slang up-front so
    // "תחב״צ" behaves exactly like "תחבורה ציבורית", "שכ״ד" like "שכר דירה", etc.
    text = expandLexicon(text);
    final t = text.toLowerCase();

    // ── rooms (range / half / studio / "+") ─────────────────────────────────
    double? minRooms;
    double? maxRooms;
    final roomRange = RegExp(r'(\d(?:\.\d)?)\s*[-־–]\s*(\d(?:\.\d)?)\s*(?:חדר|חד)')
        .firstMatch(text);
    final roomBetween =
        RegExp(r'בין\s*(\d(?:\.\d)?)\s*ל[-־]?\s*(\d(?:\.\d)?)\s*(?:חדר|חד)')
            .firstMatch(text);
    // "עד N חדרים" is an UPPER bound (max), "מעל/לפחות N חדרים" a LOWER bound —
    // otherwise a "small apartment, up to 3 rooms" request would set a MINIMUM of
    // 3 and surface the biggest units first.
    final uptoRooms = RegExp(
            r'(?:עד|מקסימום|מקס|לכל היותר)\s*(\d(?:\.\d)?)\s*(?:חדר|חדרים|חד)')
        .firstMatch(text);
    final fromRooms =
        RegExp(r'(?:לפחות|מעל)\s*(\d(?:\.\d)?)\s*(?:חדר|חדרים|חד)').firstMatch(text);
    if (uptoRooms != null) {
      maxRooms = double.tryParse(uptoRooms.group(1)!);
    } else if (fromRooms != null) {
      minRooms = double.tryParse(fromRooms.group(1)!);
    } else if (roomRange != null || roomBetween != null) {
      final m = roomRange ?? roomBetween!;
      minRooms = double.tryParse(m.group(1)!);
      maxRooms = double.tryParse(m.group(2)!);
    } else {
      final half =
          RegExp(r'(\d|אחד|שני|שתי|שלוש|שלושה|ארבע|ארבעה|חמש|חמישה)\s*וחצי')
              .firstMatch(text);
      final single = RegExp(
              r'(\d(?:\.\d)?)\s*[-+]?\s*(?:חדר|חדרים|חד|rooms?|bedrooms?)',
              caseSensitive: false)
          .firstMatch(text);
      if (half != null) {
        minRooms = (_wordToNum(half.group(1)!) ?? 0) + 0.5;
      } else if (single != null) {
        minRooms = double.tryParse(single.group(1)!);
      } else {
        // Spelled-out room counts ("שלושה חדרים", "תלת חדר") — common in formal/
        // older speech.
        final spelled = RegExp(
                r'(אחד|שני|שתי|שלוש|שלושה|תלת|ארבע|ארבעה|חמש|חמישה|שש|שישה|שבע|שבעה)\s*(?:חדר|חדרים)')
            .firstMatch(text);
        if (spelled != null) {
          minRooms = _wordToNum(spelled.group(1)!)?.toDouble();
        }
      }
      // "חדר וחצי" / "דירת חדר וחצי" = 1.5 rooms (no leading number → the digit/
      // word regexes above miss it).
      if (minRooms == null && RegExp(r'חדר\s*וחצי').hasMatch(text)) {
        minRooms = 1.5;
      }
      // "3+" → open-ended max (just a min).
      if (single != null && RegExp(r'\d\s*\+').hasMatch(text)) {
        maxRooms = null;
      }
    }
    minRooms ??= _toDouble(llm['rooms']);

    // A bare single room count ("3 חדרים", "שלושה חדרים", llm rooms=3) means ~3,
    // NOT "3 or more": without an upper bound the filter surfaces 4/5/6-room units
    // and feels like it ignored the request. Give it a tight band [n, n+0.5] so it
    // matches 3 and 3.5 but excludes 4. Ranges / "עד" / "לפחות" / "3+" keep their
    // deliberate open bound.
    final bareSingle = uptoRooms == null &&
        fromRooms == null &&
        roomRange == null &&
        roomBetween == null;
    final openEnded = RegExp(r'\d\s*\+').hasMatch(text);
    if (bareSingle && !openEnded && minRooms != null && maxRooms == null) {
      maxRooms = minRooms + 0.5;
    }

    // ── property type ───────────────────────────────────────────────────────
    String? propertyType;
    for (final entry in _propertyTypes.entries) {
      if (entry.value.any((w) => t.contains(w))) {
        propertyType = entry.key;
        break;
      }
    }
    // studio / sub-unit imply a small place: cap the top but keep NO floor, so a
    // 0.5/1-room micro-unit still matches ("from 0.5 and studio up to the max").
    if (propertyType == 'סטודיו' || propertyType == 'יחידת דיור') {
      maxRooms ??= 2;
    }

    // ── budget (range / around / max / min, with "אלף") ─────────────────────
    int? minPrice;
    int? maxPrice;
    int? amount(String s) {
      // millions (sale budgets): "2 מיליון", "2.5 מיליון", "מיליון וחצי"
      final mil = RegExp(r'(\d+(?:[.,]\d+)?)\s*מיליון').firstMatch(s);
      if (mil != null) {
        final base = double.tryParse(mil.group(1)!.replaceAll(',', '.')) ?? 0;
        return (base * 1000000).round() + (s.contains('וחצי') ? 500000 : 0);
      }
      if (s.contains('מיליון')) {
        return 1000000 + (s.contains('וחצי') ? 500000 : 0);
      }
      // shorthand: "1.5M" / "2 מ׳" (sale budgets typed tersely)
      final mShort = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:M|מ׳|מ״)').firstMatch(s);
      if (mShort != null) {
        final base = double.tryParse(mShort.group(1)!.replaceAll(',', '.')) ?? 0;
        return (base * 1000000).round();
      }
      final e = RegExp(r'(\d+)\s*(וחצי\s*)?(?:אלף|אלפים)').firstMatch(s);
      if (e != null) {
        return (int.tryParse(e.group(1)!) ?? 0) * 1000 +
            (e.group(2) != null ? 500 : 0);
      }
      // SPELLED thousands: "ששת אלפים" (6000), "חמשת אלפים" (5000), "אלף" (1000).
      final spelledK = RegExp(
              r'(שני|שתי|שלושת|תלת|ארבעת|חמשת|ששת|שבעת|שמונת|תשעת|עשרת)\s*אלפ')
          .firstMatch(s);
      if (spelledK != null) {
        final n = _wordToNum(spelledK.group(1)!);
        if (n != null) return (n * 1000).round();
      }
      if (RegExp(r'(?<![א-ת])אלף(?![א-ת])').hasMatch(s)) return 1000;
      final n = RegExp(r'\d[\d,]{2,}').firstMatch(s.replaceAll(',', ''));
      return n != null ? int.tryParse(n.group(0)!) : null;
    }

    // Capture a number + optional unit ("2 מיליון", "6 אלף", "6000") OR a
    // digit-less "מיליון"/"מיליון וחצי" (common for sale budgets). The unit must
    // stay in the group so the terminator can't cut at the space before it.
    const amt =
        r'(\d[\d.,]*\s*(?:אלף|אלפים|מיליון(?:\s*וחצי)?|M|מ׳|מ״)?|מיליון(?:\s*וחצי)?)';
    final between = RegExp('בין\\s*$amt\\s*ל[-־]?\\s*$amt').firstMatch(text);
    final around =
        RegExp('(?:בערך|סביב|כ[-־]|בסביבות)\\s*$amt').firstMatch(text);
    final upto = RegExp('(?:עד|מקסימום|מקס|לכל היותר|מתחת ל[-־]?)\\s*$amt')
        .firstMatch(text);
    final from =
        RegExp('(?:מ[-־]|לפחות|מעל|החל מ[-־]?)\\s*$amt').firstMatch(text);

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
      // bare number with a price hint. Accept the RENT band (1.5k–60k) OR a clear
      // SALE-price band (100k–30M): "2 מיליון" / "2500000" typed WITHOUT "עד" must
      // still register as a budget (and then trip the sale inference below) — the
      // old ≤60k cap silently dropped them, so an investor got neither a budget nor
      // a sale search. The 60k–100k gap stays rejected (too ambiguous to guess).
      if (maxPrice == null && minPrice == null) {
        final any = amount(text);
        if (any != null &&
            ((any >= 1500 && any <= 60000) ||
                (any >= 100000 && any <= 30000000))) {
          maxPrice = any;
        }
      }
    }
    // sanity: drop tiny values that aren't budgets (e.g. room counts)
    if (minPrice != null && minPrice < 1500) minPrice = null;
    if (maxPrice != null && maxPrice < 1500) maxPrice = null;
    maxPrice ??= _toInt(llm['price']);

    // Cheapness signal — incl. VAGUE budget phrasing with no number ("תקציב קטן/
    // מוגבל/נמוך"), which otherwise gave zero price signal and let an expensive
    // flat win for a clearly budget-limited seeker.
    final cheap = RegExp(
            r'זול|משתלם|במחיר טוב|כמה שפחות|תקציב (קטן|מוגבל|נמוך|צנוע)|'
            r'מוגבל בתקציב|כסף מוגבל|לא הרבה כסף|תקציב מוגבל|חסכוני')
        .hasMatch(text);

    // ── rent vs. sale intent ─────────────────────────────────────────────────
    // Sale phrasing wins ("למכירה"/"לקנות"/"לרכוש"). Otherwise an explicit rent
    // phrase ("להשכרה"/"לשכור"/"שכירות") pins it to rent; if neither appears we
    // leave it [any] so the existing rent-first behaviour is preserved.
    var transactionType = TransactionTypeFilter.any;
    // Investment phrasing ("להשקעה"/"תשואה") also means buying → sale.
    if (RegExp(r'למכירה|למכור|לקנות|לרכוש|רכישה|מכירה|השקע|השקי|תשוא')
        .hasMatch(text)) {
      transactionType = TransactionTypeFilter.sale;
    } else if (RegExp(r'להשכרה|לשכור|שכירות|להשכיר').hasMatch(text)) {
      transactionType = TransactionTypeFilter.rent;
    }
    transactionType =
        _parseTransactionFilter(llm['transactionType']) ?? transactionType;

    // Price-magnitude inference (no explicit rent/sale word): the AMOUNT decides.
    // You cannot BUY an apartment in Israel for < ₪100k — that number is a monthly
    // RENT. And a monthly rent is never ₪500k+ — that's a purchase price. So we
    // don't need to ask "rent or buy?" when the budget already makes it obvious.
    // Explicit MONTHLY phrasing ("בחודש"/"לחודש"/"שכ״ד") pins it to rent no matter
    // the number — "₪500,000 בחודש" is an (absurd) rent, not a purchase price.
    final monthly = RegExp(r'בחודש|לחודש|חודשי|שכ["׳’]?ד|שכר ?ה?דירה')
        .hasMatch(text);
    if (transactionType == TransactionTypeFilter.any && maxPrice != null) {
      if (monthly || maxPrice < 100000) {
        transactionType = TransactionTypeFilter.rent;
      } else if (maxPrice >= 500000) {
        transactionType = TransactionTypeFilter.sale;
      }
    }

    // ── city & neighborhood ─────────────────────────────────────────────────
    // DEICTIC "my area / near me" phrases contain substrings that are REAL towns
    // ("אזור שלי"→the town אזור, "קרוב אליי"→the settlement אלי-עד), which would be
    // searched as a random city instead of the user's actual GPS location. Strip
    // those phrases before matching a city so "my area" stays city-less → GPS flow.
    // NB: "אזור" is a real town — strip it ONLY with a deictic suffix ("אזור שלי"),
    // never bare (so "דירה באזור" still searches the town Azor).
    final cityText = text
        .replaceAll(
            RegExp(r'ה?א[יִ]?זור\s+(?:שלי|שלנו|הזה|הזאת)|'
                r'בסביבה(?:\s+(?:שלי|שלנו|הזו))?|קרוב\s*אלי+|קרוב\s*אלינו|'
                r'אצל[יי]|ליד[יי]|near me|around here|nearby|my area|close to me'),
            ' ')
        // Ktiv-male double-yod ending is the everyday full spelling of the same
        // town ("נהרייה"=נהריה, "הרצלייה"=הרצליה, "נתנייה"=נתניה, "טברייה"=טבריה).
        // Collapse it so the city resolves instead of silently dropping to null.
        .replaceAll('ייה', 'יה');

    // City: prefer LLM extraction (Gemini saw the full context);
    // fall back to keyword scan + fuzzy matching only if LLM missed it
    String? city = _str(llm['city']);
    if (city == null) {
      // FIRST: the authoritative CBS locality list (every city/moshav/kibbutz) via
      // GovData — this is how tiny places like "עין עירון" are recognised at all.
      // Falls through to the legacy hand-list only when GovData isn't loaded.
      city = GovData.instance.findLocalityInText(cityText)?.name;
    }
    if (city == null) {
      // Try exact match on full multi-word localities (e.g. "תל אביב")
      for (final locality in LocalityMatcher.allLocalities) {
        if (cityText.contains(locality)) {
          city = locality;
          break;
        }
      }
      // If no exact match, try fuzzy: collect all matches, take the last (most recent mention)
      if (city == null) {
        final words = cityText
            .split(RegExp(r'[\s,،،.!?،؛]'))
            .where((w) => w.trim().isNotEmpty)
            .toList();
        // Strip Hebrew proclitic prefixes (ב, ל, מ, כ) before fuzzy matching
        String stripPrefix(String w) {
          if (w.length > 1 && 'בלמכ'.contains(w[0])) {
            return w.substring(1);
          }
          return w;
        }

        // Scan backwards: try two-word phrase first (e.g., "תל אביים"),
        // then single word fallback.
        for (int i = words.length - 1; i >= 0; i--) {
          // Try two-word phrase first (higher priority for compound names)
          if (i > 0) {
            final phrase =
                '${stripPrefix(words[i - 1])} ${stripPrefix(words[i])}'
                    .toLowerCase()
                    .trim();
            if (phrase.length >= 3 && LocalityMatcher.allLocalities.contains(phrase)) {
              city = phrase;
              break;
            }
            // Fuzzy two-word with distance <= 2
            final phraseFuzzy = <(String, int)>[];
            for (final locality in LocalityMatcher.allLocalities) {
              if (phrase[0] != locality[0]) continue;
              if ((phrase.length - locality.length).abs() > 2) continue;
              final dist = LocalityMatcher._levenshtein(phrase, locality);
              if (dist <= 2) phraseFuzzy.add((locality, dist));
            }
            if (phraseFuzzy.isNotEmpty) {
              phraseFuzzy.sort((a, b) => a.$2.compareTo(b.$2));
              city = phraseFuzzy.first.$1;
              break;
            }
          }

          // Single word fallback (only if it's 4+ chars or doesn't look like "חדרים")
          final clean = stripPrefix(words[i]).toLowerCase().trim();
          if (clean.isEmpty || clean.length < 3) continue;
          // Common Hebrew words that fuzzy-match a short city and must NEVER be
          // read as one — e.g. "בערך" (≈) → "ערך" → fuzzy "ערד" (Arad), which
          // silently gated a whole search to an empty city. Blacklist them.
          if (_notACityWord.contains(clean)) continue;

          // Exact match
          if (LocalityMatcher.allLocalities.contains(clean)) {
            city = clean;
            break;
          }

          // Space-LESS multi-word city: "תלאביב"→"תל אביב", "כפרסבא"→"כפר סבא",
          // "פתחתקווה"→"פתח תקווה", "בארשבע"→"באר שבע". A very common typo that
          // otherwise drops the city entirely and returns a WRONG town at high
          // confidence. Match the token against known multi-word localities with
          // their space removed (exact, or ≤1 edit for a small slip).
          if (clean.length >= 4 && clean.length <= 10) {
            // Try BOTH the prefix-stripped token and the raw one: for "בתלאביב"
            // the ב is a preposition (→"תלאביב"), but for "בארשבע"/"כפרסבא" the
            // ב/כ are part of the city name — stripping them would break the match.
            final raw = words[i].toLowerCase().trim();
            bool jm(String name, String cand) {
              if (cand.length < 4) return false;
              if (!name.contains(' ') && !name.contains('-')) return false;
              final joined = name.replaceAll('-', '').replaceAll(' ', '');
              return joined == cand ||
                  (joined.isNotEmpty &&
                      (joined.length - cand.length).abs() <= 1 &&
                      joined[0] == cand[0] &&
                      LocalityMatcher._levenshtein(joined, cand) <= 1);
            }

            bool joinMatch(String name) =>
                jm(name, clean) || (raw != clean && jm(name, raw));

            String? joinHit;
            // GovData (every CBS city — covers כפר סבא / באר שבע etc.) first.
            for (final rec in GovData.instance.localities) {
              if (joinMatch(rec.name)) {
                joinHit = rec.name;
                break;
              }
            }
            // Legacy hand-list fallback (when GovData isn't loaded, e.g. tests).
            if (joinHit == null) {
              for (final locality in LocalityMatcher.allLocalities) {
                if (joinMatch(locality)) {
                  joinHit = locality;
                  break;
                }
              }
            }
            if (joinHit != null) {
              city = joinHit;
              break;
            }
          }

          // Fuzzy-match a single word of 4+ chars. THREE-char words are too
          // dangerous (edit-distance-1 turns everyday words into short cities:
          // "ערך"→"ערד") — a 3-char city needs the EXACT match above. But longer
          // words SHOULD fuzzy (common typos: "ירשלים"→"ירושלים", "חיפא"→"חיפה"),
          // so no low upper cap — the dist≤1 + first-char + ±1-length gates keep it
          // safe.
          if (clean.length >= 4 && clean.length <= 9) {
            final fuzzyMatches = <(String, int)>[];
            for (final locality in LocalityMatcher.allLocalities) {
              if (clean[0] != locality[0]) continue;
              if ((clean.length - locality.length).abs() > 1) continue;
              final dist = LocalityMatcher._levenshtein(clean, locality);
              if (dist <= 1) {
                fuzzyMatches.add((locality, dist));
              }
            }
            if (fuzzyMatches.isNotEmpty) {
              fuzzyMatches.sort((a, b) => a.$2.compareTo(b.$2));
              city = fuzzyMatches.first.$1;
              break;
            }
          }
        }
      }
    }
    String? neighborhood;
    for (final n in _neighborhoods) {
      if (text.contains(n)) {
        neighborhood = n;
        break;
      }
    }
    // A neighbourhood is NOT a city: resolve it to its parent city so the city
    // gate widens to that city (which has stock) while the neighbourhood stays a
    // soft preference. Without this, "דירה ברמת אביב" mis-gates as city="רמת אביב"
    // → zero exact stock → no results. Only override when the city is unset or was
    // itself mis-parsed as the neighbourhood name.
    if (neighborhood != null) {
      final parent = _neighborhoodCity[neighborhood];
      if (parent != null && (city == null || city == neighborhood)) {
        city = parent;
      }
    }

    // ── location NEGATION + sub-city DIRECTION ───────────────────────────────
    // "לא רמת גן" must NOT set city=רמת גן (it's an exclusion). "דרום תל אביב" /
    // "לא בצפון העיר" carry a direction. This corrects the positive city/hood and
    // fills excludeAreas / areaDir / areaDirExclude.
    final locMods = _parseLocationModifiers(text, city, neighborhood);
    city = locMods.$1;
    neighborhood = locMods.$2;
    final excludeAreas = locMods.$3;
    final areaDir = locMods.$4;
    final areaDirExclude = locMods.$5;

    // ── amenities (keywords + llm flags) ─────────────────────────────────────
    final amenities = <String>{};
    _amenityKeywords.forEach((key, words) {
      if (words.any((w) => t.contains(w.toLowerCase()))) amenities.add(key);
    });
    llm.forEach((k, v) {
      if (k.startsWith('feat_') && _truthy(v)) amenities.add(k);
    });

    final nearTrain = const [
      'רכבת', 'תחנת רכבת', 'ליד הרכבת', 'קרוב לרכבת', 'רכבת קלה',
      'train', 'railway', 'light rail', 'metro', 'תחבורה ציבורית',
      // Phase 1 lexicon: תחב״צ/רק״ל expand to the two phrases above; add the rest
      // of public transport (bus / line / stop) so "קרוב לתחב״צ" is understood.
      'אוטובוס', 'תחנת אוטובוס', 'קו אוטובוס', 'מטרו', 'תחנה מרכזית',
    ].any((w) => text.contains(w));

    // ── persona soft defaults (only when rooms not stated) ──────────────────
    if (minRooms == null && maxRooms == null) {
      // Empty-nesters DOWNSIZING ("הילדים עזבו") — the opposite of a family with
      // kids, even though the text contains "ילדים". Handle FIRST so it's not
      // mistaken for a family and floored at 3 rooms.
      final emptyNest = RegExp(r'הילדים עזבו|הילדים גדלו|אחרי שהילדים|'
              r'קן ריק|נשארנו לבד|הבית התרוקן|דירה קטנה יותר')
          .hasMatch(text);
      if (RegExp(r'שותפ').hasMatch(text)) {
        // Roommates need a bedroom EACH — a 3+ floor, which must win over the
        // student 1-2 cap below ("סטודנטים שותפים" → NOT a studio).
        minRooms = 3;
      } else if (RegExp(r'סטודנט').hasMatch(text)) {
        minRooms = 1;
        maxRooms = 2;
      } else if (emptyNest) {
        minRooms = 2;
      } else if (RegExp(r'(?<![א-ת])זוג|בני ?ה?זוג|נשואים טריים|'
              r'מצפים לילד|תינוק בדרך|בהריון|הריון ראשון')
          .hasMatch(text)) {
        // A COUPLE — even expecting their FIRST child — needs ~2 rooms (bedroom +
        // a nursery), NOT a hard 3-room floor. (\b doesn't work on Hebrew, so a
        // Hebrew-letter lookbehind gates the word.) Checked before the family
        // branch; ceiling left open so a 3-room still fits.
        minRooms = 2;
      } else if (RegExp(r'משפח|ילדים|ילד').hasMatch(text)) {
        // An established family with kids → 3+.
        minRooms = 3;
      }
    }

    // ── HARD requirements (dealbreakers → excluded, not down-ranked) ─────────
    // Some things a searcher states are non-negotiable, so we must NOT offer a
    // listing that lacks them (see RecommendationEngine.recommend's feature gate).
    final required = <String>{};
    // PETS: a dog/cat owner literally cannot take a no-pets flat — always hard.
    if (amenities.contains('feat_pets') ||
        RegExp(r'מאפשר.{0,8}חיות|אפשר.{0,12}חיות|מרשה.{0,8}חיות|ידידותי לכלב|'
                r'עם כלב|יש לי כלב|יש לי חתול|pet.?friendly|dog.?friendly')
            .hasMatch(text)) {
      required.add('petsAllowed');
    }
    // CAR: someone who explicitly says they have a car NEEDS parking — make it a
    // hard gate so only listings with parking are shown (unless they also say
    // they're car-free, in which case the negative wins).
    if (RegExp(r'יש לי רכב|יש לי אוטו|יש לי מכונית|יש לי גם רכב|אני עם רכב|'
                r'באתי עם רכב|עם הרכב|צריך חניה לרכב|יש לי ג׳יפ|i have a car|'
                r'with a car|own a car|got a car')
            .hasMatch(text) &&
        !RegExp(r'אין לי רכב|בלי רכב|ללא רכב|no car|car.?free')
            .hasMatch(text)) {
      required.add('parking');
      amenities.add('feat_parking'); // also weight it, not only gate
    }
    // Explicit "חייב/חובה/מוכרח/הכרחי/חשוב שיהיה + <feature>" → a must-have. The
    // "חשוב שיהיה / חשוב לי ש / צריך שיהיה" phrasings are strong enough to gate.
    if (RegExp(r'חייב|חובה|מוכרח|הכרחי|בהכרח|רק עם|חשוב שיהיה|חשוב לי ש|'
            r'חשוב ש|צריך שיהיה|must have|required')
        .hasMatch(text)) {
      const canon = {
        'feat_elevator': 'elevator',
        'feat_parking': 'parking',
        'feat_balcony': 'balcony',
        'feat_mamad': 'mamad',
        'feat_furnished': 'furnished',
        'feat_ac': 'ac',
        'feat_storage': 'storage',
        'feat_accessible': 'accessible',
        'feat_pets': 'petsAllowed',
      };
      for (final e in canon.entries) {
        if (amenities.contains(e.key)) required.add(e.value);
      }
    }

    return SearchQuery(
      city: city,
      neighborhood: neighborhood,
      excludeAreas: excludeAreas,
      areaDir: areaDir,
      areaDirExclude: areaDirExclude,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minRooms: minRooms,
      maxRooms: maxRooms,
      propertyType: propertyType,
      amenities: amenities,
      requiredFeatures: required,
      nearTrain: nearTrain,
      cheapPreference: cheap,
      transactionType: transactionType,
      rawText: text,
      intents: {
        ...SearchIntent.fromText(text),
        // "אזור <city>" → the user wants the city PLUS its adjacent settlements,
        // so flag the engine to widen the city gate. See _isAreaSearch.
        if (_isAreaSearch(text, city)) SearchIntent.cityArea,
      },
      // "לא רחוק מאיכילוב" / "קרוב לטכניון" / "ליד תחנת רכבת השלום" — a NAMED
      // place anchor that gates + boosts + explains the results.
      anchor: AnchorResolver.resolve(text),
    );
  }

  /// "אזור X" / "באזור X" / "בסביבות X" / "X והסביבה" → the seeker wants X PLUS
  /// its adjacent settlements. Matched against the city's FIRST word so it works
  /// even when the city resolved to a CBS name ("תל אביב - יפו") that differs from
  /// what the user typed ("אזור תל אביב"). "אזור שקט בנתניה" does NOT trigger it.
  static bool _isAreaSearch(String text, String? city) {
    if (city == null || city == 'אזור') return false;
    final parts =
        city.split(RegExp(r'[\s\-]')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return false;
    final first = parts.first;
    if (first.length < 2) return false;
    final esc = RegExp.escape(first);
    if (RegExp('(אזור|איזור|בסביבות|סביבת)\\s*$esc').hasMatch(text)) return true;
    if (RegExp('$esc.{0,18}(והסביבה|וסביבתה|והאזור|וסביבותיה)').hasMatch(text)) {
      return true;
    }
    return false;
  }

  // Location negation + sub-city direction. Returns a corrected
  // (city, neighborhood, excludeAreas, areaDir, areaDirExclude): a place mentioned
  // under a negation ("לא רמת גן") is moved OUT of the positive target and INTO
  // excludeAreas, and a direction ("דרום העיר" / "לא בצפון") is captured.
  static const _directions = {
    'דרום': 'דרום', 'צפון': 'צפון', 'מזרח': 'מזרח', 'מערב': 'מערב',
    'מרכז': 'מרכז', 'לב': 'מרכז',
  };
  // Everyday Israeli negation cues that mean "avoid this place".
  // "לא" must be the standalone word (not the prefix of "לאוניברסיטה" / "לאט" /
  // "לאור" …) — Hebrew has no \b, so guard with letter lookaround. This bug nulled
  // the city of "קרוב לאוניברסיטה בתל אביב" (the "לא" in "לאוניברסיטה").
  static final _locNeg = RegExp(
      r'(?<![א-ת])לא(?![א-ת])|(?<![א-ת])בלי(?![א-ת])|ללא|רחוק\s*מ|חוץ\s*מ|מלבד|למעט|'
      r'\bnot\b|without|avoid|except',
      caseSensitive: false);

  static (String?, String?, List<String>, String?, bool) _parseLocationModifiers(
      String text, String? city, String? neighborhood) {
    final excl = <String>[];

    // A place is negated if a negation cue sits within ~14 chars before it.
    bool negatedBefore(int idx) {
      if (idx < 0) return false;
      final from = idx - 14 < 0 ? 0 : idx - 14;
      return _locNeg.hasMatch(text.substring(from, idx));
    }

    String firstWord(String place) => place
        .split(RegExp(r'[\s\-־]'))
        .firstWhere((s) => s.isNotEmpty, orElse: () => place);

    if (city != null && negatedBefore(text.indexOf(firstWord(city)))) {
      excl.add(city);
      city = null;
    }
    if (neighborhood != null && negatedBefore(text.indexOf(neighborhood))) {
      excl.add(neighborhood);
      neighborhood = null;
    }

    // Independently scan "<negation> <place>" — catches a negated place that the
    // positive city/hood scan skipped (it stops at the first match), e.g.
    // "בתל אביב אבל לא רמת גן" (city already resolved to תל אביב).
    final negPhrase = RegExp(
        r'(?:לא|בלי|ללא|רחוק\s*מ|חוץ\s*מ|מלבד|למעט)\s+'
        r'(?:ב|ל|ליד\s+|בא[יי]?זור\s+|רוצ\w+\s+ב?|מעוניינ?\w*\s+ב?)?'
        r'([א-ת]{2,}(?:[\s\-]+[א-ת]{2,})?)',
        caseSensitive: false);
    for (final m in negPhrase.allMatches(text)) {
      final phrase = m.group(1)!.trim();
      if (_directions.containsKey(phrase.split(RegExp(r'\s+')).first)) continue;
      final loc = GovData.instance.findLocalityInText(phrase);
      if (loc != null) {
        if (!excl.contains(loc.name)) excl.add(loc.name);
        continue;
      }
      final hand = LocalityMatcher.allLocalities
          .firstWhere((l) => phrase.contains(l), orElse: () => '');
      if (hand.isNotEmpty) {
        if (!excl.contains(hand)) excl.add(hand);
        continue;
      }
      for (final n in _neighborhoods) {
        if (phrase.contains(n) && !excl.contains(n)) {
          excl.add(n);
          break;
        }
      }
    }

    // Direction: (ב/ל/מ)?<dir> followed by "העיר" or the city's first word.
    String? areaDir;
    var areaDirExclude = false;
    final cityFirst = city == null ? '' : RegExp.escape(firstWord(city));
    final anchor = cityFirst.isEmpty ? r'ה?עיר' : '(?:ה?עיר|$cityFirst)';
    final dm = RegExp(r'[בהמל]?(דרום|צפון|מזרח|מערב|מרכז|לב)\s+' + anchor)
        .firstMatch(text);
    if (dm != null) {
      areaDir = _directions[dm.group(1)];
      areaDirExclude = negatedBefore(dm.start);
    }

    return (city, neighborhood, excl, areaDir, areaDirExclude);
  }

  static TransactionTypeFilter? _parseTransactionFilter(dynamic v) {
    final s = v?.toString().trim().toLowerCase();
    if (s == null || s.isEmpty) return null;
    if (s == 'sale' || s == 'sell' || s == 'for_sale') {
      return TransactionTypeFilter.sale;
    }
    if (s == 'rent' || s == 'rental') return TransactionTypeFilter.rent;
    return null;
  }

  static List<ScoredProperty> rank(
    List<RentalProperty> props,
    SearchQuery q, {
    int limit = 10,
    TenantProfile? profile,
  }) {
    // Hard rent/sale gate first so neither ranking path can mix the two.
    var pool = applyTransactionFilter(props, q);
    // HARD budget gate — "עד 4500" means up to 4500; soft scoring alone let
    // well-over-budget listings outrank in-budget ones. Only when the budget
    // leaves nothing do we fall back to ≤15% over (surfaced as labeled
    // near-budget fallbacks downstream, never as silent matches).
    final cap = q.maxPrice;
    if (cap != null) {
      final within =
          pool.where((p) => !(p.price > 0 && p.price > cap)).toList();
      pool = within.isNotEmpty
          ? within
          : pool.where((p) => !(p.price > 0 && p.price > cap * 1.15)).toList();
    }
    // Use advanced multi-dimensional matching if query has enough signal;
    // fall back to simpler scoring if vague.
    if (q.hasEssentials && pool.isNotEmpty) {
      return rankAdvanced(pool, q, limit: limit, profile: profile);
    }
    final scored = pool.map((p) => _score(p, q)).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  // Advanced ranking. Delegates to the 4-part RecommendationEngine
  // (lib/core/search/engine/) — a hybrid cascade of hedonic value modeling,
  // Bayesian preference inference, MAUT+TOPSIS+cosine+GBM scoring, and
  // MMR/exploration re-ranking. Falls back to the legacy matcher on any error so
  // search never breaks.
  static List<ScoredProperty> rankAdvanced(
    List<RentalProperty> props,
    SearchQuery q, {
    int limit = 10,
    TenantProfile? profile,
  }) {
    final pool = applyTransactionFilter(props, q);
    if (pool.isEmpty) return [];
    try {
      final scored = RecommendationEngine.recommendAsScored(
        candidates: pool,
        query: q,
        limit: limit,
        profile: profile,
      );
      if (scored.isNotEmpty) return scored;
    } catch (_) {
      // fall through to the legacy matcher below
    }
    return _rankAdvancedLegacy(pool, q, limit: limit);
  }

  // Legacy multi-dimensional matcher, retained as a resilient fallback.
  static List<ScoredProperty> _rankAdvancedLegacy(
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
    if (!_matchesTransactionType(p, q)) return false;
    if (q.city != null && !p.city.contains(q.city!)) return false;
    if (q.maxPrice != null && p.price > q.maxPrice!) return false;
    if (q.minPrice != null && p.price < q.minPrice!) return false;
    if (q.minRooms != null && p.rooms < q.minRooms!) return false;
    if (q.maxRooms != null && p.rooms > q.maxRooms!) return false;
    return true;
  }

  static bool _hasAmenities(RentalProperty p, SearchQuery q) =>
      q.amenities.any((a) => p.featureFlags.isEnabled(a));

  // Hard rent/sale gate so a "דירה למכירה" search never surfaces rentals (and
  // vice-versa). [TransactionTypeFilter.any] matches everything.
  static bool _matchesTransactionType(RentalProperty p, SearchQuery q) {
    switch (q.transactionType) {
      case TransactionTypeFilter.any:
        return true;
      case TransactionTypeFilter.sale:
        return p.transactionType == PropertyTransactionType.sale;
      case TransactionTypeFilter.rent:
        return p.transactionType == PropertyTransactionType.rent;
    }
  }

  // Drops listings of the wrong transaction type up-front so rent and sale
  // results never blend, regardless of which ranking path runs.
  static List<RentalProperty> applyTransactionFilter(
    List<RentalProperty> props,
    SearchQuery q,
  ) {
    if (q.transactionType == TransactionTypeFilter.any) return props;
    return props.where((p) => _matchesTransactionType(p, q)).toList();
  }

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
  // ── Phase 1: Israeli everyday terms + abbreviations ─────────────────────────
  // Expanded to their canonical phrase BEFORE parsing, so a search typed in
  // real-life shorthand ("תחב״צ", "שכ״ד", "3 חד׳") is understood exactly like the
  // full words. Gershayim can be ASCII (") or Hebrew (״); a geresh apostrophe can
  // be ASCII (') or Hebrew (׳).
  static final List<List<Object>> _lexicon = [
    [RegExp('תחב["״]?צ'), ' תחבורה ציבורית '], // public transport
    [RegExp('רק["״]?ל'), ' רכבת קלה '], // light rail
    [RegExp('שכ["״]?ד'), ' שכר דירה '], // rent
    [RegExp('יח["״]?ד'), ' יחידת דיור '], // housing unit
    [RegExp('ממ["״]?ד'), ' ממ"ד '], // protected room (canonicalise)
    [RegExp('ממ["״]?ק'), ' מרחב מוגן '], // floor shelter
    [RegExp('ק["״]ק'), ' קומת קרקע '], // ground floor
    [RegExp('מ["״]ר'), ' מטר '], // square metres
    [RegExp("חד['׳](?=\\s|\$)"), ' חדרים '], // "3 חד׳" → rooms
    [RegExp('צמוד[ותה]? קרקע'), ' צמוד קרקע '],
    [RegExp('דו[- ]?משפחתי'), ' דו משפחתי '],
    [RegExp('מרפסת\\s*שמש'), ' מרפסת שמש '],
    [RegExp('כ["״]?\\s*מיידית'), ' כניסה מיידית '],
    // City short-forms / nicknames → their full CBS-resolvable names, the way
    // people actually speak ("ראשון", "רשל״צ", "פ״ת", "ר״ג"…).
    [RegExp(r'ראשל["״]?צ|רשל["״]?צ|רשלצ|ראשלצ'), ' ראשון לציון '],
    // bare "ראשון" (the city) — but NOT "יום ראשון" (Sunday), "הראשון" (the first),
    // or the already-full "ראשון לציון".
    [RegExp(r'(?<!יום )(?<!ה)ראשון(?! לציון)'), ' ראשון לציון '],
    [RegExp(r'פ["״]ת(?![א-ת])'), ' פתח תקווה '],
    [RegExp(r'ר["״]ג(?![א-ת])'), ' רמת גן '],
    [RegExp(r'ב["״]ש(?![א-ת])'), ' באר שבע '],
    [RegExp(r'ת["״]א(?![א-ת])'), ' תל אביב '],
    [RegExp(r'כ["״]ס(?![א-ת])'), ' כפר סבא '],
    [RegExp(r'כפ["״]ס(?![א-ת])'), ' כפר סבא '],
    [RegExp(r'י["״]ם(?![א-ת])'), ' ירושלים '],
    [RegExp(r'ק["״]ש(?![א-ת])'), ' קרית שמונה '],
    [RegExp(r'ק["״]ג(?![א-ת])'), ' קרית גת '],
    [RegExp(r'ק["״]מ(?![א-ת])'), ' קרית מלאכי '],
    // English city names (olim / English-speakers) → Hebrew.
    [RegExp(r'\btel[\s-]?aviv\b|\btlv\b', caseSensitive: false), ' תל אביב '],
    [RegExp(r'\bjerusalem\b', caseSensitive: false), ' ירושלים '],
    [RegExp(r'\bhaifa\b', caseSensitive: false), ' חיפה '],
    [RegExp(r'\bbeer[\s-]?sheva\b|\bbeersheba\b', caseSensitive: false),
      ' באר שבע '],
    [RegExp(r'\bnetanya\b', caseSensitive: false), ' נתניה '],
    [RegExp(r'\bherzl?iya\b|\bherzelia\b', caseSensitive: false), ' הרצליה '],
    [RegExp(r'\brishon(?:\s*le?[\s-]?zion)?\b', caseSensitive: false),
      ' ראשון לציון '],
    [RegExp(r'\bpeta[hc]\s*tik[vw]a\b', caseSensitive: false), ' פתח תקווה '],
    [RegExp(r'\bramat[\s-]?gan\b', caseSensitive: false), ' רמת גן '],
    [RegExp(r'\bgivatayim\b', caseSensitive: false), ' גבעתיים '],
    [RegExp(r'\bbat[\s-]?yam\b', caseSensitive: false), ' בת ים '],
    [RegExp(r'\bholon\b', caseSensitive: false), ' חולון '],
    [RegExp(r'\bre[hc]ovot\b', caseSensitive: false), ' רחובות '],
    [RegExp(r'\bkfar[\s-]?saba\b', caseSensitive: false), ' כפר סבא '],
    [RegExp(r'\bra.?anana\b', caseSensitive: false), ' רעננה '],
    [RegExp(r'\bmodi.?in\b', caseSensitive: false), ' מודיעין '],
    [RegExp(r'\bashdod\b', caseSensitive: false), ' אשדוד '],
    [RegExp(r'\bash[kq]elon\b', caseSensitive: false), ' אשקלון '],
    [RegExp(r'\beilat\b', caseSensitive: false), ' אילת '],
    [RegExp(r'\btiberias\b', caseSensitive: false), ' טבריה '],
    [RegExp(r'\bbnei[\s-]?brak\b', caseSensitive: false), ' בני ברק '],
  ];

  /// Rewrites Israeli abbreviations/slang to their full phrase (see [_lexicon]).
  static String expandLexicon(String text) {
    var out = text;
    for (final row in _lexicon) {
      out = out.replaceAll(row[0] as RegExp, row[1] as String);
    }
    return out;
  }

  static const Map<String, List<String>> _amenityKeywords = {
    'feat_renovated': ['משופצ', 'שיפוץ', 'חדשה', 'renovated'],
    'feat_pets': ['כלב', 'כלבה', 'חתול', 'חיית מחמד', 'חיות מחמד', 'pet', 'dog'],
    'feat_parking': ['חניה', 'חנייה', 'חניית', 'חנית', 'parking', 'מכונית', 'רכב פרטי'],
    // ponytail: feat_accessible/feat_roommates exist in the catalogue but the
    // parser never detected them — real personas (wheelchair, students) were
    // silently dropped. Keyword rows only; the MAUT engine already scores them.
    'feat_accessible': ['נגיש', 'נגישות', 'כיסא גלגלים', 'כסא גלגלים', 'נכה', 'accessible', 'wheelchair', 'disabled'],
    'feat_roommates': ['שותפים', 'שותף', 'שותפה', 'דירת שותפים', 'roommate', 'flatmate'],
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

  // Everyday Hebrew words that fuzzy-match a short city and must never be read as
  // one (post prefix-strip). "בערך"→"ערך", "ערך"~"ערד"; "שקט"~"סכת"; etc.
  static const Set<String> _notACityWord = {
    'ערך', 'בערך', 'ערכי', 'חדר', 'חדרים', 'דירה', 'דירת', 'בית', 'משהו',
    'שקט', 'שקטה', 'גדול', 'גדולה', 'קטן', 'קטנה', 'זול', 'זולה', 'יקר', 'יקרה',
    'נחמד', 'יפה', 'יפו', 'טוב', 'טובה', 'חדש', 'חדשה', 'ישן', 'מרכז', 'מרכזי',
    'קרוב', 'רחוק', 'צריך', 'רוצה', 'מחפש', 'מחפשת', 'לגור', 'עבודה', 'רכבת',
    'ילדים', 'ילד', 'משפחה', 'זוג', 'רווק', 'סטודנט', 'כלב', 'חתול', 'שנה',
  };

  // Well-known neighborhoods — narrows results within a city when mentioned.
  static const List<String> _neighborhoods = [
    'פלורנטין', 'נווה צדק', 'רוטשילד', 'כרם התימנים', 'לב העיר', 'הצפון הישן',
    'הצפון החדש', 'רמת אביב', 'בבלי', 'יד אליהו', 'רמת החייל', 'שפירא',
    'נחלת יצחק', 'תל ברוך', 'אפקה', 'מונטיפיורי', 'יפו', 'הקריה', 'נווה שאנן',
    'רחביה', 'בקעה', 'נחלאות', 'תלפיות', 'קטמון', 'גילה', 'פסגת זאב',
    'הדר', 'כרמל', 'נווה שאנן', 'ואדי ניסנס', 'רמות', 'קרית חיים',
    'רמת אביב ג', 'גבעת שמואל', 'מרכז העיר',
  ];

  // A neighbourhood belongs to a city — so naming one ("דירה ברמת אביב") can gate
  // the search to that city instead of hard-filtering to an empty "city=רמת אביב"
  // set. Only unambiguous neighbourhoods are mapped (ambiguous ones like
  // נווה שאנן/מרכז העיר, or גבעת שמואל which is its own city, are intentionally omitted).
  static const Map<String, String> _neighborhoodCity = {
    // Tel Aviv
    'פלורנטין': 'תל אביב', 'נווה צדק': 'תל אביב', 'רוטשילד': 'תל אביב',
    'כרם התימנים': 'תל אביב', 'לב העיר': 'תל אביב', 'הצפון הישן': 'תל אביב',
    'הצפון החדש': 'תל אביב', 'רמת אביב': 'תל אביב', 'רמת אביב ג': 'תל אביב',
    'בבלי': 'תל אביב', 'יד אליהו': 'תל אביב', 'רמת החייל': 'תל אביב',
    'שפירא': 'תל אביב', 'נחלת יצחק': 'תל אביב', 'תל ברוך': 'תל אביב',
    'אפקה': 'תל אביב', 'מונטיפיורי': 'תל אביב', 'יפו': 'תל אביב',
    // Jerusalem
    'רחביה': 'ירושלים', 'בקעה': 'ירושלים', 'נחלאות': 'ירושלים',
    'תלפיות': 'ירושלים', 'קטמון': 'ירושלים', 'גילה': 'ירושלים',
    'פסגת זאב': 'ירושלים', 'רמות': 'ירושלים',
    // Haifa
    'הדר': 'חיפה', 'כרמל': 'חיפה', 'ואדי ניסנס': 'חיפה', 'קרית חיים': 'חיפה',
  };

  static String amenityTag(String key, [AppLocalizations? l10n]) {
    if (l10n == null) return key.replaceFirst('feat_', '');
    switch (key) {
      case 'feat_renovated':
        return l10n.smartSearchAmenityRenovated;
      case 'feat_pets':
        return l10n.smartSearchAmenityPets;
      case 'feat_parking':
        return l10n.smartSearchAmenityParking;
      case 'feat_balcony':
        return l10n.smartSearchAmenityBalcony;
      case 'feat_elevator':
        return l10n.smartSearchAmenityElevator;
      case 'feat_furnished':
        return l10n.smartSearchAmenityFurnished;
      case 'feat_mamad':
        return l10n.smartSearchAmenityMamad;
      case 'feat_garden':
        return l10n.smartSearchAmenityGarden;
      case 'feat_air':
        return l10n.smartSearchAmenityAir;
      case 'feat_pool':
        return l10n.smartSearchAmenityPool;
      case 'feat_gym':
        return l10n.smartSearchAmenityGym;
      case 'feat_storage':
        return l10n.smartSearchAmenityStorage;
      case 'feat_sun':
        return l10n.smartSearchAmenitySun;
      case 'feat_safe':
        return l10n.smartSearchAmenitySafe;
      case 'feat_internet':
        return l10n.smartSearchAmenityInternet;
      case 'feat_laundry':
        return l10n.smartSearchAmenityLaundry;
      case 'feat_accessible':
        return l10n.smartSearchAmenityAccessible;
      case 'feat_roommates':
        return l10n.smartSearchAmenityRoommates;
      default:
        return key.replaceFirst('feat_', '');
    }
  }

  // ── cohort signals ───────────────────────────────────────────────────────────
  /// The amenity/feature keys mentioned in [text], using the SAME Hebrew lexicon
  /// as the full parse. Lets the ranking model turn a profile's free-text labels
  /// ('נגישות'/'מעלית'/'ממ"ד'/'חניה') into catalogue feature keys so a curated
  /// profile's must-haves actually influence ranking.
  static Set<String> amenityKeysIn(String text) {
    final t = text.toLowerCase();
    final out = <String>{};
    _amenityKeywords.forEach((key, words) {
      if (words.any((w) => t.contains(w.toLowerCase()))) out.add(key);
    });
    return out;
  }

  // Extract the persona/cohort signals the BACKEND 14-cohort engine already reads
  // (cohort.mjs `querySignals`: household/religiousStream/isOleh/hasChildren/
  // carFree/wfh/accessibilityNeed/lifeStage/isInvestor/sector/…). Nothing produced
  // these before, so the whole personalization taxonomy sat dormant for chat search.
  // Pure keyword scan → a {key:value} map sent verbatim as listRows params.
  static Map<String, String> cohortSignals(String rawText) {
    final t = rawText.toLowerCase();
    bool has(List<String> ws) => ws.any((w) => t.contains(w));
    final s = <String, String>{};

    // "בלי / ללא / אין ילדים" negates children — otherwise the ילד* substring
    // (also inside ילדים) mis-tags a childless couple as a family with kids.
    final noKids = RegExp(r'(?:בלי|ללא|אין|בלא)\s*ילד').hasMatch(t);

    // household (also gates charedi/dati_leumi split, which needs family context)
    if (has(['משפח', 'family']) ||
        (!noKids && has(['ילדים', 'ילד ', 'הילד', 'children', 'kids']))) {
      s['household'] = 'family';
    } else if (has(['סטודנט', 'שותפים', 'student', 'roommate'])) {
      s['household'] = 'student';
    } else if (has(['זוג', 'couple', 'בן/בת זוג'])) {
      s['household'] = 'couple';
    } else if (has(['רווק', 'רווקה', 'לבד', 'single', 'solo'])) {
      s['household'] = 'single';
    }

    // religiosity → stream (charedi vs dati_leumi have OPPOSITE school needs).
    // NB: a CITY name (בני ברק) is NOT a religiosity signal — "משפחה חילונית בבני
    // ברק" must not be tagged charedi, and "דתי לאומי בבני ברק" must stay dati_leumi.
    if (has(['חרדי', 'חרדית', 'חיידר', 'תלמוד תורה', 'haredi', 'charedi'])) {
      s['religiousStream'] = 'charedi';
      s['isReligious'] = 'true';
    } else if (has(['דתי לאומי', 'דתיה לאומית', 'סרוג', 'אולפנה', 'ישיבה תיכונית', 'dati leumi'])) {
      s['religiousStream'] = 'dati_leumi';
      s['isReligious'] = 'true';
    } else if (has(['דתי', 'דתיה', 'שומר שבת', 'בית כנסת', 'religious', 'synagogue', 'kosher'])) {
      s['isReligious'] = 'true';
    }

    // sector (Arabic listing pools / school proximity)
    if (has(['ערבי', 'ערבית', 'عرب', 'الناصرة', 'مدرسة'])) s['sector'] = 'arab';

    // oleh / language preference
    if (has(['עולה', 'עולה חדש', 'immigrant', 'oleh', 'olah', 'aliyah',
        'new to israel'])) {
      s['isOleh'] = 'true';
    }
    if (has(['english speaker', 'english speaking', 'english-speaking',
        'דובר אנגלית', 'אנגלית'])) {
      s['langPref'] = 'en';
    }
    if (has(['דובר צרפתית', 'french speaker', 'צרפתית'])) s['langPref'] = 'fr';

    // children / life-stage timing ("בלי ילדים" already negated via noKids)
    if (!noKids && has(['ילד', 'ילדים', 'kids', 'children'])) {
      s['hasChildren'] = 'true';
    }
    if (has(['בהריון', 'הריון', 'pregnant', 'expecting', 'תינוק בדרך'])) s['expecting'] = 'true';
    if (has(['תינוק', 'רך נולד', 'baby', 'newborn'])) {
      s['hasChildren'] = 'true';
      s['childAge'] = '1';
    }

    // mobility / work
    if (has(['בלי רכב', 'ללא רכב', 'אין לי רכב', 'אין רכב', 'no car', 'car-free', 'תחבורה ציבורית'])) {
      s['carFree'] = 'true';
    }
    if (has(['עובד מהבית', 'עבודה מהבית', 'מהבית', 'wfh', 'work from home', 'remote work', 'חדר עבודה'])) {
      s['wfh'] = 'true';
    }

    // accessibility → senior/accessible cohort
    if (has(['נגיש', 'נגישות', 'כיסא גלגלים', 'כסא גלגלים', 'נכה', 'wheelchair',
        'accessible', 'disabled', 'קושי בהליכה', 'מתקשה ללכת', 'הליכון', 'צולע'])) {
      s['accessibilityNeed'] = 'true';
    }

    // life stage. "מבוגר/ת" is a very common elderly self-description.
    if (has(['סטודנט', 'סטודנטית', 'student'])) s['lifeStage'] = 'student';
    if (has(['גמלאי', 'פנסיונר', 'פנסיונרית', 'קשיש', 'מבוגר', 'מבוגרת',
        'בגיל השלישי', 'גיל הפרישה', 'retired', 'senior', 'pensioner', 'elderly'])) {
      s['lifeStage'] = 'senior';
    }
    // explicit age ("בן 72" / "age 72"). Guard against a BUILDING's age
    // ("בניין בן 40 שנה") — that's the property, not the user.
    final ageM = RegExp(r'(?:בן|בת|גיל|age)\s*(\d{2,3})').firstMatch(t);
    if (ageM != null) {
      final before =
          t.substring((ageM.start - 8).clamp(0, t.length), ageM.start);
      if (!RegExp(r'בניין|בית|מבנה|דירה|נכס').hasMatch(before)) {
        s['age'] = ageM.group(1)!;
      }
    }

    // intent
    if (has(['משקיע', 'השקעה', 'תשואה', 'investor', 'investment', 'yield', 'לקנייה', 'לקנות', 'רכישה'])) {
      s['isInvestor'] = 'true';
      s['intent'] = 'investment';
    }

    // vibe (soft neighbourhood-vibrancy target the backend cohort reads)
    if (has(['תוסס', 'חיי לילה', 'nightlife', 'vibrant', 'לב העיר', 'במרכז'])) {
      s['vibe'] = 'תוסס';
    } else if (has(['שקט', 'quiet', 'רגוע', 'peaceful'])) {
      s['vibe'] = 'שקט';
    } else if (s['household'] == 'family') {
      s['vibe'] = 'משפחתי';
    } else if (s['lifeStage'] == 'student') {
      s['vibe'] = 'סטודנטיאלי';
    }
    return s;
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
      'אחד': 1, 'אחת': 1, 'שני': 2, 'שתי': 2, 'שניים': 2, 'שתיים': 2, 'שתי ': 2,
      'שלוש': 3, 'שלושה': 3, 'תלת': 3, 'שלושת': 3,
      'ארבע': 4, 'ארבעה': 4, 'ארבעת': 4,
      'חמש': 5, 'חמישה': 5, 'חמשת': 5,
      'שש': 6, 'שישה': 6, 'ששת': 6,
      'שבע': 7, 'שבעה': 7, 'שבעת': 7,
      'שמונה': 8, 'שמונת': 8,
      'תשע': 9, 'תשעה': 9, 'תשעת': 9,
      'עשר': 10, 'עשרה': 10, 'עשרת': 10,
    };
    return map[w.trim()]?.toDouble() ?? double.tryParse(w);
  }

  static bool _truthy(dynamic v) =>
      v == true || v == 1 || v == '1' || v.toString().toLowerCase() == 'true';
}

String _roomsRangeLabel(double? lo, double? hi, [AppLocalizations? l10n]) {
  String f(double r) => r % 1 == 0 ? r.toInt().toString() : r.toString();
  if (lo != null && hi != null) return lo == hi ? f(lo) : '${f(lo)}-${f(hi)}';
  if (lo != null) return '${f(lo)}+';
  return l10n?.smartSearchRangeUpTo(f(hi!)) ?? 'עד ${f(hi!)}';
}

String _priceRangeLabel(int? lo, int? hi, [AppLocalizations? l10n]) {
  String m(int v) => '₪${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (x) => '${x[1]},')}';
  if (lo != null && hi != null) return '${m(lo)}–${m(hi)}';
  if (hi != null) return l10n?.smartSearchRangeUpTo(m(hi)) ?? 'עד ${m(hi)}';
  return l10n?.smartSearchRangeFrom(m(lo!)) ?? 'מ-${m(lo!)}';
}
