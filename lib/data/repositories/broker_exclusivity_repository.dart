import 'dart:convert';

import 'package:dating_app/data/models/broker_exclusivity.dart';
import 'package:dating_app/data/repositories/broker_cloud_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a broker's exclusivity mandates locally.
///
/// Mandates are private broker bookkeeping — a broker has a handful, not
/// thousands — so we keep the whole list under one SharedPreferences JSON key,
/// the same pattern as [SavedSearchRepository]. Standalone, no provider
/// dependency; never throws on read.
class BrokerExclusivityRepository {
  BrokerExclusivityRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'broker_exclusivity_mandates';

  /// All mandates, ending soonest first (so renewals surface at the top).
  Future<List<BrokerExclusivity>> loadAll() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <BrokerExclusivity>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map((e) => BrokerExclusivity.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        list.sort((a, b) => a.endDate.compareTo(b.endDate));
        return list;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BrokerExclusivityRepository.loadAll failed: $e');
      }
    }
    return <BrokerExclusivity>[];
  }

  /// Inserts a new mandate or replaces the one with the same id. Returns the
  /// updated (re-sorted) list.
  Future<List<BrokerExclusivity>> save(BrokerExclusivity mandate) async {
    final all = await loadAll();
    final next = [
      mandate,
      ...all.where((m) => m.id != mandate.id),
    ];
    await _persist(next);
    return loadAll();
  }

  /// Removes the mandate with [id]. Returns the updated list.
  Future<List<BrokerExclusivity>> delete(String id) async {
    final all = await loadAll();
    final next = all.where((m) => m.id != id).toList();
    await _persist(next);
    return next;
  }

  Future<void> _persist(List<BrokerExclusivity> mandates) async {
    final prefs = await _prefsFuture;
    final raw = jsonEncode(mandates.map((m) => m.toJson()).toList());
    await prefs.setString(_key, raw);
    BrokerCloudSync.instance.push(_key, raw); // cloud backup (fire-and-forget)
  }
}
