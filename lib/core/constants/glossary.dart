/// Plain-Hebrew definitions of common Israeli rental terms.
///
/// Built for new immigrants and low-tech seekers who hit Hebrew rental jargon
/// in listings. Definitions are intentionally short and warm — one line each.
///
/// Lookup via [Glossary.define]; it is tolerant of minor spelling differences
/// (quotes, gershayim, whitespace, leading "ה").
class Glossary {
  const Glossary._();

  /// term → one-line plain-Hebrew definition.
  static const Map<String, String> terms = <String, String>{
    'ממ"ד':
        'חדר מוגן דירתי — חדר בטון עם דלת וחלון אטומים שמשמש מקלט בשעת חירום.',
    'בטוחות':
        'ערבויות שנותנים לבעל הדירה כדי להבטיח שתשלמו — למשל ערבון, ערב או שטר חוב.',
    'פיקדון':
        'סכום שמשאירים אצל בעל הדירה כביטחון ומקבלים בחזרה בסוף, אם הכול תקין. לפי החוק עד 3 חודשי שכירות.',
    'ערבון':
        'אותו דבר כמו פיקדון — סכום ביטחון שמוחזר לכם בסוף השכירות אם לא נגרם נזק.',
    'תיווך':
        'שירות של מתווך שמחבר בינכם לבעל הדירה. משלמים עליו רק אם נחתם חוזה דרכו.',
    'דמי תיווך':
        'התשלום למתווך — בדרך כלל חודש שכירות אחד + מע"מ, ורק אם הוא סגר לכם את העסקה.',
    'ארנונה':
        'מס חודשי לעירייה על הדירה. בדרך כלל השוכר משלם אותו, אז כדאי לבדוק כמה זה.',
    'ועד בית':
        'תשלום חודשי קטן לתחזוקת הבניין — ניקיון, מעלית, חצר. נפרד מהשכירות.',
    'ערב':
        'אדם שחותם איתכם ומתחייב לשלם לבעל הדירה אם אתם לא תוכלו. בדרך כלל קרוב משפחה.',
    'ערבות':
        'התחייבות (של אדם או של הבנק) לכסות חוב שלכם לבעל הדירה אם לא תשלמו.',
    'שטר חוב':
        'מסמך שאתם חותמים עליו ומבטיח תשלום סכום מסוים אם תפרו את החוזה. אל תחתמו בלי להבין על איזה סכום מדובר.',
    "צ'ק ביטחון":
        "צ'ק שאתם נותנים לבעל הדירה כביטחון בלבד — הוא לא אמור לפדות אותו, רק להחזיר בסוף.",
    'מיידי':
        'אפשר להיכנס לדירה כבר עכשיו, בלי להמתין.',
    'גמיש':
        'תאריך הכניסה גמיש — אפשר לתאם מתי שנוח לשני הצדדים.',
  };

  /// Returns the plain-Hebrew definition for [term], or `null` if unknown.
  ///
  /// Tolerant of minor spelling: ignores surrounding whitespace, normalises
  /// straight/curly quotes and gershayim, drops a leading "ה", and matches
  /// either side of "/" separated keys (e.g. "פיקדון/ערבון", "תיווך / דמי תיווך").
  static String? define(String term) {
    final query = _normalise(term);
    if (query.isEmpty) return null;

    for (final entry in terms.entries) {
      if (_normalise(entry.key) == query) return entry.value;
    }
    // Match a single side of a slash-separated label the caller might pass in.
    for (final entry in terms.entries) {
      for (final part in entry.key.split('/')) {
        if (_normalise(part) == query) return entry.value;
      }
    }
    return null;
  }

  /// True when [term] has a definition.
  static bool has(String term) => define(term) != null;

  static String _normalise(String value) {
    var result = value.trim();
    // Unify the many ways gershayim / quotes get typed.
    const quoteChars = <String>['"', '״', '“', '”', '″'];
    for (final q in quoteChars) {
      result = result.replaceAll(q, '"');
    }
    const apostropheChars = <String>['’', '׳', '′', '`'];
    for (final a in apostropheChars) {
      result = result.replaceAll(a, "'");
    }
    // Collapse internal whitespace.
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Drop a leading definite article "ה" so "הפיקדון" finds "פיקדון".
    if (result.length > 2 && result.startsWith('ה')) {
      final stripped = result.substring(1);
      if (terms.keys.any((k) => _bare(k) == _bare(stripped))) {
        result = stripped;
      }
    }
    return result;
  }

  static String _bare(String value) =>
      value.replaceAll(RegExp(r'[\s"״“”]'), '');
}
