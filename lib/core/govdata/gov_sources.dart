// ═════════════════════════════════════════════════════════════════════════════
// GovSources — honest provenance for each gov-backed scorecard dimension.
//
// Every figure rendered on a property's "למה זו?" scorecard traces to a real
// Israeli public dataset (mostly CBS / הלמ״ס, plus police, Rail and Health). This
// registry maps each scoring-dimension key (the kScoringDimensions that can carry
// a gov stat) to a SHORT, accurate agency + dataset descriptor in Hebrew, so the
// transparency UI can show the user WHERE the number came from.
//
// Honesty rules:
//   • Only dimensions whose stat is genuinely gov-derived appear here.
//   • The `size` percentile is NOT gov data — it is computed from the live Rently
//     listing set — so it is labelled as such, not dressed up as an official stat.
//   • No invented URLs or publication years: the agency + dataset name only. The
//     bundled gov-data version lives in meta.json / GovData.version.
// ═════════════════════════════════════════════════════════════════════════════

/// A short, honest provenance descriptor for one scorecard dimension's figure.
class GovSource {
  const GovSource({
    required this.agency,
    required this.dataset,
    this.note,
  });

  /// The publishing body, e.g. "הלשכה המרכזית לסטטיסטיקה (למ״ס)".
  final String agency;

  /// The specific dataset behind the figure, e.g. "מדד מחירי שכר דירה למ״ר".
  final String dataset;

  /// Optional clarifier (e.g. that a figure is derived locally, not official).
  final String? note;

  /// One-line "agency — dataset" label for compact display.
  String get label => '$agency — $dataset';
}

/// Registry: scoring-dimension key → its honest data source.
class GovSources {
  const GovSources._();

  // Common agency strings (kept consistent so the UI groups cleanly).
  static const String _cbs = 'הלשכה המרכזית לסטטיסטיקה (למ״ס)';
  static const String _police = 'משטרת ישראל / למ״ס';
  static const String _rail = 'רכבת ישראל';
  static const String _education = 'למ״ס / משרד החינוך';
  static const String _health = 'משרד הבריאות / למ״ס';
  static const String _rently = 'נתוני Rently';
  static const String _osm = 'OpenStreetMap / data.gov.il';
  static const String _planning = 'נת״ע / רשות התכנון';

  /// dimKey → source descriptor. Mirrors the keys ScorecardStats can emit.
  static const Map<String, GovSource> _byDimension = {
    'value': GovSource(
      agency: _cbs,
      dataset: 'מדד מחירי שכר דירה למ״ר',
    ),
    'safety': GovSource(
      agency: _police,
      dataset: 'עבירות פליליות שנרשמו (לנפש)',
    ),
    'neighborhood': GovSource(
      agency: _cbs,
      dataset: 'המדד החברתי-כלכלי של הרשויות המקומיות',
    ),
    'transit': GovSource(
      agency: _rail,
      dataset: 'מיקומי תחנות רכבת',
    ),
    'schools': GovSource(
      agency: _education,
      dataset: 'מוסדות חינוך',
    ),
    'family': GovSource(
      agency: _cbs,
      dataset: 'נתוני אוכלוסייה לפי גיל',
    ),
    'health': GovSource(
      agency: _health,
      dataset: 'שירותי בריאות וקופות חולים',
    ),
    'convenience': GovSource(
      agency: _osm,
      dataset: 'סופרמרקטים ומרכזי קניות',
      note: 'ממופה מ-OpenStreetMap / data.gov.il',
    ),
    'low_noise': GovSource(
      agency: _osm,
      dataset: 'קרבה לצירי תנועה ראשיים ומסילות',
      note: 'פרוקסי רעש מ-OpenStreetMap (כבישים מהירים + מסילות)',
    ),
    'future_value': GovSource(
      agency: _planning,
      dataset: 'תחנות מטרו/רק״ל מתוכננות והתחדשות עירונית',
      note: 'נת״ע + רשות התכנון (פינוי-בינוי / תמ״א)',
    ),
    'employment': GovSource(
      agency: _osm,
      dataset: 'ריכוזי תעסוקה — משרדים ואזורי מסחר/תעשייה',
      note: 'צפיפות מקומות עבודה מ-OpenStreetMap (פרוקסי מרחק לעבודה)',
    ),
    // size is the live-market percentile — honest about not being an official
    // statistic.
    'size': GovSource(
      agency: _rently,
      dataset: 'התפלגות מחירי השוק',
      note: 'מחושב מתוך המודעות הפעילות, אינו נתון ממשלתי',
    ),
  };

  /// The source for a dimension key, or null when the dimension carries no
  /// gov-backed (or market-derived) figure we can attribute.
  static GovSource? forDimension(String key) => _byDimension[key];

  /// Compact "agency — dataset" label for a dimension, or null.
  static String? labelFor(String key) => _byDimension[key]?.label;
}
