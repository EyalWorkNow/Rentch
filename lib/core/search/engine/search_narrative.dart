// ════════════════════════════════════════════════════════════════════════════
// SEARCH NARRATIVE — "what the algorithm did", in plain Hebrew
// ════════════════════════════════════════════════════════════════════════════
//
// After the engine runs its multi-dimensional scoring, the assistant should tell
// the user, briefly and warmly, WHAT it analysed, HOW it filtered, and WHY the
// surfaced apartments fit — turning the opaque math into a one-paragraph
// explanation. Pure function over the query + scored results (no side effects).
// ════════════════════════════════════════════════════════════════════════════

import 'package:dating_app/core/search/smart_search.dart';

class SearchNarrative {
  const SearchNarrative._();

  /// A short Hebrew paragraph explaining the search the engine just performed.
  /// [scanned] = how many listings were considered; [results] = the ranked top.
  static String summarize(
    SearchQuery q,
    int scanned,
    List<ScoredProperty> results,
  ) {
    if (results.isEmpty) {
      return 'עברתי על $scanned דירות אבל לא צף משהו מספיק מדויק — '
          'בוא ננסה אזור אחר או תקציב גמיש יותר.';
    }

    // 1) what I filtered by
    final filters = <String>[];
    if (q.city != null && q.city!.trim().isNotEmpty) filters.add(q.city!);
    if (q.neighborhood != null && q.neighborhood!.trim().isNotEmpty) {
      filters.add(q.neighborhood!);
    }
    if (q.maxPrice != null) filters.add('עד ₪${_money(q.maxPrice!)}');
    if (q.minRooms != null || q.maxRooms != null) {
      filters.add('${_rooms(q)} חד׳');
    }
    if (q.propertyType != null) filters.add(q.propertyType!);
    if (q.nearTrain) filters.add('קרוב לרכבת');

    // 2) which dimensions I weighed (always-on gov-data signals + intent)
    final dims = <String>['בטיחות האזור', 'קרבה לתחבורה', 'תמורה למחיר'];
    if (q.city != null) dims.add('איכות השכונה');
    if (q.amenities.isNotEmpty) dims.add('המאפיינים שביקשת');

    // 3) what the top picks actually stood out for (from result highlights)
    final standouts = _topHighlights(results);

    final sb = StringBuffer();
    sb.write('עברתי על $scanned דירות');
    if (filters.isNotEmpty) {
      sb.write(' וסיננתי לפי ${_join(filters)}');
    }
    sb.write('. דירגתי כל אחת בציון רב-ממדי ששוקלל לפי ');
    sb.write('${_join(dims)} — על בסיס נתוני אמת ממשלתיים.');
    if (standouts.isNotEmpty) {
      sb.write(' הדירות שבחרתי בלטו במיוחד ב${_join(standouts)}.');
    }
    return sb.toString();
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  // Most frequent concrete highlight chips across the top few results (the chips
  // are stored as ScoredProperty.tags after the leading "NN% התאמה").
  static List<String> _topHighlights(List<ScoredProperty> results) {
    final counts = <String, int>{};
    for (final r in results.take(4)) {
      for (final tag in r.tags) {
        if (tag.contains('התאמה') || tag.contains('%')) continue;
        // strip emoji/markers for a cleaner phrase
        final clean = tag.replaceAll(RegExp(r'[✓✨🚉📍🏷️]'), '').trim();
        if (clean.length < 2) continue;
        counts[clean] = (counts[clean] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(3)) e.key];
  }

  static String _rooms(SearchQuery q) {
    final lo = q.minRooms;
    final hi = q.maxRooms;
    if (lo != null && hi != null && lo != hi) {
      return '${_n(lo)}-${_n(hi)}';
    }
    return _n(lo ?? hi ?? 0);
  }

  static String _n(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  static String _money(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // Hebrew-friendly list join: "א, ב ו-ג".
  static String _join(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    final head = items.sublist(0, items.length - 1).join(', ');
    return '$head ו${items.last}';
  }
}
