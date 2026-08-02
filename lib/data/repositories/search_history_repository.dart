import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tiny store of the user's recent אתי search queries (just the text), so the
/// chat can offer "previous searches" next to the new-conversation button.
/// Newest-first, deduped (case-insensitive), capped. SharedPreferences-backed —
/// mirrors [SavedSearchRepository]'s single-JSON-key pattern.
class SearchHistoryRepository {
  static const String _key = 'ati_search_history_v1';
  static const int _max = 12;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {/* corrupt → empty */}
    return [];
  }

  /// Record a query at the front. No-ops on empty/very short text so a stray
  /// "כן" doesn't clutter the list.
  Future<void> add(String query) async {
    final q = query.trim();
    if (q.length < 3) return;
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    if (list.length > _max) list.removeRange(_max, list.length);
    await prefs.setString(_key, jsonEncode(list));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
