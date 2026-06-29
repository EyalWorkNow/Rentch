import 'dart:convert';

import 'package:dating_app/data/models/broker_viewing.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a broker's scheduled viewings locally.
///
/// Same shape as [BrokerLeadRepository]: one JSON key in the app's existing
/// SharedPreferences store, fail-soft reads, no backend. A broker schedules a
/// handful of viewings a week, so a single read/write of the whole list is
/// plenty and keeps ordering stable.
class BrokerViewingRepository {
  BrokerViewingRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'broker_viewings';

  /// All viewings (unsorted — the screen sorts by time). Empty on any error.
  Future<List<BrokerViewing>> loadAll() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <BrokerViewing>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => BrokerViewing.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BrokerViewingRepository.loadAll failed: $e');
    }
    return <BrokerViewing>[];
  }

  /// Inserts a new viewing, or replaces an existing one with the same id.
  /// Returns the updated list.
  Future<List<BrokerViewing>> save(BrokerViewing viewing) async {
    final all = await loadAll();
    final next = [
      viewing,
      ...all.where((v) => v.id != viewing.id),
    ];
    await _persist(next);
    return next;
  }

  /// Removes the viewing with [id]. Returns the updated list.
  Future<List<BrokerViewing>> delete(String id) async {
    final all = await loadAll();
    final next = all.where((v) => v.id != id).toList();
    await _persist(next);
    return next;
  }

  Future<void> _persist(List<BrokerViewing> viewings) async {
    final prefs = await _prefsFuture;
    await prefs.setString(
      _key,
      jsonEncode(viewings.map((v) => v.toJson()).toList()),
    );
  }
}
