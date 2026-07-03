/// Lifestyle / religiosity knowledge used to make the search assistant actually
/// consider whether a tenant is secular / traditional / religious / haredi, and
/// match them to areas with a compatible character.
///
/// This is a curated heuristic (no external POI feed): Israeli neighbourhoods
/// and towns have well-known religious character, so we map the common ones and
/// treat everything else as "mixed" (neutral). It is deliberately data — extend
/// the maps below to sharpen matching; no code changes needed.
library;

enum Religiosity { secular, traditional, religious, haredi }

enum AreaChar { secular, mixed, religious, haredi }

class LifestyleKnowledge {
  /// Reads the tenant's stated religiosity from free Hebrew text. Returns null
  /// when nothing is said (so we don't invent a preference). Order matters:
  /// negations ("לא דתי") and the most specific terms are checked first.
  static Religiosity? detectReligiosity(String text) {
    final t = text.toLowerCase();
    // Secular first — "לא דתי" contains "דתי" and must not read as religious.
    if (_hasAny(t, const [
      'חילוני',
      'חילונית',
      'חילונים',
      'לא דתי',
      'לא-דתי',
      'לא שומר',
      'לא שומרת',
      'חופשי',
    ])) {
      return Religiosity.secular;
    }
    if (_hasAny(t, const [
      'חרדי',
      'חרדית',
      'חרדים',
      'ליטאי',
      'ליטאית',
      'חסידי',
      'חסיד',
      'חסידית',
      'אברך',
      'בני תורה',
    ])) {
      return Religiosity.haredi;
    }
    if (_hasAny(t, const [
      'דתי לאומי',
      'דתי-לאומי',
      'דתייה',
      'דתיה',
      'דתיים',
      'דתית',
      'דתי',
      'סרוג',
      'כיפה',
      'שומר שבת',
      'שומרת שבת',
      'שומרי שבת',
      'שומר מצוות',
      'שומרת מצוות',
      'שומר תורה',
      'אורתודוקס',
    ])) {
      return Religiosity.religious;
    }
    if (_hasAny(t, const ['מסורתי', 'מסורתית', 'מסורתיים', 'מסורת'])) {
      return Religiosity.traditional;
    }
    return null;
  }

  /// Character of an area, preferring the (more specific) neighbourhood over the
  /// city. Returns null when unknown → callers treat that as neutral/mixed.
  static AreaChar? areaCharacter({
    required String neighborhood,
    required String city,
  }) {
    final n = neighborhood.trim();
    if (n.isNotEmpty && _areaByName.containsKey(n)) return _areaByName[n];
    final c = city.trim();
    if (c.isNotEmpty && _areaByName.containsKey(c)) return _areaByName[c];
    // Loose contains match (e.g. "רמות אלון, ירושלים").
    for (final entry in _areaByName.entries) {
      if (n.contains(entry.key) || c.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// How well an area's character suits the tenant's religiosity, in [-1, 1].
  /// Positive = good fit (rank up), negative = poor fit (rank down).
  static double religiosityFit(Religiosity user, AreaChar area) {
    return _fit[user]![area]!;
  }

  static bool _hasAny(String t, List<String> needles) {
    for (final n in needles) {
      if (t.contains(n)) return true;
    }
    return false;
  }

  static const Map<Religiosity, Map<AreaChar, double>> _fit = {
    Religiosity.secular: {
      AreaChar.secular: 0.8,
      AreaChar.mixed: 0.2,
      AreaChar.religious: -0.3,
      AreaChar.haredi: -0.9,
    },
    Religiosity.traditional: {
      AreaChar.secular: 0.3,
      AreaChar.mixed: 0.5,
      AreaChar.religious: 0.3,
      AreaChar.haredi: -0.2,
    },
    Religiosity.religious: {
      AreaChar.secular: -0.3,
      AreaChar.mixed: 0.2,
      AreaChar.religious: 0.9,
      AreaChar.haredi: 0.3,
    },
    Religiosity.haredi: {
      AreaChar.secular: -0.9,
      AreaChar.mixed: -0.1,
      AreaChar.religious: 0.4,
      AreaChar.haredi: 1.0,
    },
  };

  // Curated area → character. Neighbourhood names take priority over cities.
  // Extend freely; unknown places fall through to "mixed" (neutral).
  static const Map<String, AreaChar> _areaByName = {
    // ── Haredi towns / neighbourhoods ──
    'בני ברק': AreaChar.haredi,
    'מודיעין עילית': AreaChar.haredi,
    'קרית ספר': AreaChar.haredi,
    'ביתר עילית': AreaChar.haredi,
    'אלעד': AreaChar.haredi,
    'עמנואל': AreaChar.haredi,
    'רכסים': AreaChar.haredi,
    'מאה שערים': AreaChar.haredi,
    'הר נוף': AreaChar.haredi,
    'רמת שלמה': AreaChar.haredi,
    'גבעת שאול': AreaChar.haredi,
    'סנהדריה': AreaChar.haredi,
    'רמות אלון': AreaChar.haredi,
    'נווה יעקב': AreaChar.haredi,
    'קרית הרצוג': AreaChar.haredi,
    'פרדס כץ': AreaChar.haredi,
    'קרית ויז\'ניץ': AreaChar.haredi,
    // ── Religious-Zionist (דתי-לאומי) ──
    'אפרת': AreaChar.religious,
    'אלון שבות': AreaChar.religious,
    'כרמי צור': AreaChar.religious,
    'קרני שומרון': AreaChar.religious,
    'בית אל': AreaChar.religious,
    'עפרה': AreaChar.religious,
    'שילה': AreaChar.religious,
    'קדומים': AreaChar.religious,
    'גוש עציון': AreaChar.religious,
    'כוכב יעקב': AreaChar.religious,
    'טלמון': AreaChar.religious,
    'עלי': AreaChar.religious,
    'רבבה': AreaChar.religious,
    'נוקדים': AreaChar.religious,
    'גבעת שמואל': AreaChar.religious,
    'קרית ארבע': AreaChar.religious,
    // ── Secular ──
    'תל אביב': AreaChar.secular,
    'תל אביב-יפו': AreaChar.secular,
    'פלורנטין': AreaChar.secular,
    'נווה צדק': AreaChar.secular,
    'רמת אביב': AreaChar.secular,
    'לב תל אביב': AreaChar.secular,
    'שינקין': AreaChar.secular,
    'הצפון הישן': AreaChar.secular,
    'גבעתיים': AreaChar.secular,
    'רמת השרון': AreaChar.secular,
    'כרמל': AreaChar.secular,
    'רמת אביב ג': AreaChar.secular,
  };
}
