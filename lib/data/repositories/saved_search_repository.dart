import 'dart:convert';

import 'package:dating_app/data/models/saved_search.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the tenant's saved searches locally.
///
/// Saved searches are a private, tenant-only convenience (so we can alert them
/// when a new matching listing appears); they don't need a backend. We reuse the
/// app's existing local store (SharedPreferences, the same one the rent ledger
/// uses) and keep the whole list under a single JSON key — a tenant has a few
/// searches, not thousands, so one read/write is plenty and keeps ordering
/// stable. Standalone, no provider dependency.
class SavedSearchRepository {
  SavedSearchRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'tenant_saved_searches';

  /// All saved searches, newest first. Empty (never throws) on any error.
  Future<List<SavedSearch>> loadAll() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <SavedSearch>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => SavedSearch.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SavedSearchRepository.loadAll failed: $e');
    }
    return <SavedSearch>[];
  }

  /// Inserts a new search at the top, or replaces an existing one with the same
  /// id. Returns the updated list.
  Future<List<SavedSearch>> save(SavedSearch search) async {
    final all = await loadAll();
    final next = [
      search,
      ...all.where((s) => s.id != search.id),
    ];
    await _persist(next);
    return next;
  }

  /// Replaces the entire list (used by toggles/reordering). Returns the list.
  Future<List<SavedSearch>> saveAll(List<SavedSearch> searches) async {
    await _persist(searches);
    return searches;
  }

  /// Removes the search with [id]. Returns the updated list.
  Future<List<SavedSearch>> delete(String id) async {
    final all = await loadAll();
    final next = all.where((s) => s.id != id).toList();
    await _persist(next);
    return next;
  }

  Future<void> _persist(List<SavedSearch> searches) async {
    final prefs = await _prefsFuture;
    await prefs.setString(
      _key,
      jsonEncode(searches.map((s) => s.toJson()).toList()),
    );
  }
}
