import 'package:dating_app/core/search/engine/feature_engineering.dart'
    show IsraelGeoIndex;

/// A resolved "לא רחוק מ-X" anchor: a NAMED place the seeker wants to live
/// near — a specific hospital, university/college, or rail station.
class NearAnchor {
  const NearAnchor({
    required this.name,
    required this.lat,
    required this.lon,
    required this.radiusKm,
    required this.kindLabel,
  });

  /// Canonical display name ("איכילוב", "אוניברסיטת תל אביב").
  final String name;
  final double lat;
  final double lon;

  /// The gate radius. "לא רחוק" defaults per kind; an explicit "עד 2 ק"מ"
  /// overrides; "במרחק הליכה" tightens to walking distance.
  final double radiusKm;

  /// "בית חולים" / "אוניברסיטה" / "תחנת רכבת" — for labels.
  final String kindLabel;
}

class _Place {
  const _Place(this.name, this.lat, this.lon, this.aliases);
  final String name;
  final double lat;
  final double lon;
  final List<String> aliases;
}

/// Resolves free text like "דירה לא רחוק מאיכילוב" / "קרוב לאוניברסיטת תל
/// אביב" / "ליד תחנת רכבת השלום" into a concrete [NearAnchor].
///
/// The bundled hospitals POI layer is an OSM scrape that MISSES the major
/// hospitals by their household names (איכילוב/שיבא/רמב"ם…), so the anchors
/// people actually search for live in a CURATED catalog here. Rail stations
/// resolve dynamically against the bundled layer (244 named stations).
class AnchorResolver {
  const AnchorResolver._();

  static const double _hospitalRadiusKm = 4.0;
  static const double _universityRadiusKm = 3.0;
  static const double _railRadiusKm = 2.0;
  static const double _walkRadiusKm = 1.2;

  // ── curated catalog: the hospitals Israelis name in searches ──────────────
  static const List<_Place> _hospitals = [
    _Place('איכילוב', 32.0809, 34.7897, ['איכילוב', 'סוראסקי']),
    _Place('שיבא תל השומר', 32.0432, 34.8420, ['שיבא', 'תל השומר']),
    _Place('רמב"ם', 32.8320, 34.9900, ['רמבם', 'רמב"ם']),
    _Place('סורוקה', 31.2589, 34.8000, ['סורוקה']),
    _Place('הדסה עין כרם', 31.7650, 35.1470, ['הדסה עין כרם']),
    _Place('הדסה הר הצופים', 31.7970, 35.2440, ['הדסה הר הצופים']),
    _Place('הדסה', 31.7650, 35.1470, ['הדסה']), // bare "הדסה" → Ein Kerem
    _Place('בילינסון', 32.0870, 34.8610, ['בילינסון', 'רבין']),
    _Place('שניידר', 32.0900, 34.8590, ['שניידר']),
    _Place('וולפסון', 32.0290, 34.7590, ['וולפסון']),
    _Place('שמיר אסף הרופא', 31.9300, 34.8260, ['אסף הרופא', 'שמיר']),
    _Place('מאיר', 32.1780, 34.9060, ['בית חולים מאיר', 'ביח מאיר']),
    _Place('לניאדו', 32.3400, 34.8570, ['לניאדו']),
    _Place('הלל יפה', 32.4420, 34.9020, ['הלל יפה']),
    _Place('ברזילי', 31.6590, 34.5590, ['ברזילי']),
    _Place('קפלן', 31.8790, 34.8020, ['קפלן']),
    _Place('העמק', 32.6180, 35.2920, ['בית חולים העמק', 'ביח העמק']),
    _Place('פוריה', 32.7420, 35.5390, ['פוריה']),
    _Place('זיו', 32.9750, 35.5020, ['בית חולים זיו', 'ביח זיו']),
    _Place('גליל מערבי', 33.0060, 35.1020, ['גליל מערבי', 'בית חולים נהריה']),
    _Place('כרמל', 32.7940, 34.9670, ['בית חולים כרמל', 'ביח כרמל']),
    _Place('בני ציון', 32.8130, 34.9910, ['בני ציון', 'רוטשילד חיפה']),
    _Place('שערי צדק', 31.7660, 35.1930, ['שערי צדק']),
    _Place('אסותא תל אביב', 32.1130, 34.8400, ['אסותא תל אביב', 'אסותא רמת החייל']),
    _Place('אסותא אשדוד', 31.7770, 34.6300, ['אסותא אשדוד']),
    _Place('מעיני הישועה', 32.0910, 34.8320, ['מעיני הישועה']),
    _Place('יוספטל', 29.5560, 34.9440, ['יוספטל']),
  ];

  static const List<_Place> _universities = [
    _Place('אוניברסיטת תל אביב', 32.1133, 34.8044,
        ['אוניברסיטת תל אביב', 'אוניברסיטת תא', 'תל אביב אוניברסיטה']),
    _Place('הטכניון', 32.7767, 35.0233, ['טכניון']),
    _Place('האוניברסיטה העברית גבעת רם', 31.7770, 35.1970,
        ['העברית גבעת רם', 'גבעת רם']),
    _Place('האוניברסיטה העברית הר הצופים', 31.7940, 35.2440,
        ['העברית הר הצופים', 'האוניברסיטה העברית']),
    _Place('אוניברסיטת בן גוריון', 31.2620, 34.8010, ['בן גוריון']),
    _Place('אוניברסיטת בר אילן', 32.0690, 34.8430, ['בר אילן']),
    _Place('אוניברסיטת חיפה', 32.7610, 35.0200, ['אוניברסיטת חיפה']),
    _Place('אוניברסיטת אריאל', 32.1030, 35.2070, ['אריאל אוניברסיטה', 'אוניברסיטת אריאל']),
    _Place('האוניברסיטה הפתוחה', 32.1810, 34.8710, ['הפתוחה', 'האוניברסיטה הפתוחה']),
    _Place('מכון ויצמן', 31.9070, 34.8100, ['ויצמן']),
    _Place('אוניברסיטת רייכמן', 32.1740, 34.8390,
        ['רייכמן', 'הבינתחומי', 'בינתחומי הרצליה']),
    _Place('מכללת שנקר', 32.0640, 34.8280, ['שנקר']),
    _Place('הקריה האקדמית אונו', 32.0560, 34.8560, ['קריה אקדמית אונו', 'מכללת אונו']),
    _Place('HIT מכון טכנולוגי חולון', 32.0150, 34.7740, ['hit', 'מכון טכנולוגי חולון']),
    _Place('המכללה למינהל', 31.9670, 34.7930, ['המכללה למינהל']),
    _Place('מכללת ספיר', 31.5100, 34.5950, ['ספיר']),
    _Place('בצלאל', 31.7900, 35.2020, ['בצלאל']),
  ];

  // Trigger phrases, longest first so "לא רחוק מ" wins over "ליד".
  static final RegExp _trigger = RegExp(
      r'(לא רחוק מ|במרחק הליכה מ|קרוב ל|בקרבת |סמוך ל|צמוד ל|ליד )');

  // "עד 2 ק"מ" / "עד 1.5 קמ" — an explicit radius override anywhere in text.
  static final RegExp _radius = RegExp(r'עד\s+(\d+(?:\.\d+)?)\s*ק["״]?מ');

  static String _norm(String s) => s
      .replaceAll('"', '')
      .replaceAll('״', '')
      .replaceAll("'", '')
      .replaceAll('־', ' ')
      .replaceAll('-', ' ')
      .trim()
      .toLowerCase();

  /// Resolve a BARE place name (no trigger phrase) — the assistant's
  /// structured `near_place` hard-constraint path.
  static NearAnchor? resolveNamed(String name) =>
      name.trim().isEmpty ? null : resolve('לא רחוק מ${name.trim()}');

  /// Resolve the first "near X" phrase in [text] to an anchor, or null when
  /// no phrase / no catalog match. Pure and deterministic (rail resolution
  /// consults the loaded geo index; unloaded → hospitals/universities only).
  static NearAnchor? resolve(String text) {
    final m = _trigger.firstMatch(text);
    if (m == null) return null;
    // The name tail: up to ~6 words after the trigger, stopping at clause
    // boundaries so "לא רחוק מאיכילוב עם מרפסת" doesn't swallow the rest.
    var tail = text.substring(m.end);
    final stop = RegExp(r'[,.!?\n]| עם | עד | ב-|\d');
    final cut = stop.firstMatch(tail);
    if (cut != null) tail = tail.substring(0, cut.start);
    final words = tail.trim().split(RegExp(r'\s+')).take(6).toList();
    if (words.isEmpty || words.first.isEmpty) return null;

    final walk = m.group(1)!.contains('הליכה');
    final explicit = _radius.firstMatch(text);
    final overrideKm =
        explicit != null ? double.tryParse(explicit.group(1)!) : null;

    double radiusFor(double def) =>
        overrideKm ?? (walk ? _walkRadiusKm : def);

    // Try progressively shorter name candidates ("אוניברסיטת תל אביב" before
    // "אוניברסיטת"), each with generic type-prefixes stripped.
    for (var n = words.length; n >= 1; n--) {
      final phrase = words.take(n).join(' ');
      final candidates = _nameCandidates(phrase);
      for (final cand in candidates) {
        if (cand.length < 3) continue;
        final hosp = _match(_hospitals, cand);
        if (hosp != null) {
          return NearAnchor(
              name: hosp.name,
              lat: hosp.lat,
              lon: hosp.lon,
              radiusKm: radiusFor(_hospitalRadiusKm),
              kindLabel: 'בית חולים');
        }
        final uni = _match(_universities, cand);
        if (uni != null) {
          return NearAnchor(
              name: uni.name,
              lat: uni.lat,
              lon: uni.lon,
              radiusKm: radiusFor(_universityRadiusKm),
              kindLabel: 'אוניברסיטה');
        }
        final rail = IsraelGeoIndex.railStationNamed(cand);
        if (rail != null) {
          return NearAnchor(
              name: 'תחנת ${rail.$1}',
              lat: rail.$2,
              lon: rail.$3,
              radiusKm: radiusFor(_railRadiusKm),
              kindLabel: 'תחנת רכבת');
        }
      }
    }
    return null;
  }

  // The phrase with/without generic type prefixes ("בית חולים איכילוב" →
  // also "איכילוב"; "אוניברסיטת תל אביב" → also "תל אביב" is NOT desired for
  // universities, so only container-words are stripped, not "אוניברסיטת").
  static List<String> _nameCandidates(String phrase) {
    final p = _norm(phrase);
    final stripped = p
        .replaceFirst(RegExp(r'^(בית החולים|בית חולים|ביה"ח|ביהח|תחנת רכבת|תחנת|רכבת)\s+'), '')
        .trim();
    return [p, if (stripped != p && stripped.isNotEmpty) stripped];
  }

  static _Place? _match(List<_Place> catalog, String cand) {
    for (final place in catalog) {
      for (final alias in place.aliases) {
        final a = _norm(alias);
        // Exact-ish: candidate equals the alias, or contains it as a whole
        // word (avoids "מאיר" matching inside random words via startsWith).
        if (cand == a || cand.contains(a) || a.contains(cand) && cand.length >= 4) {
          return place;
        }
      }
    }
    return null;
  }
}
