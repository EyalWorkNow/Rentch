import 'dart:convert';

import 'package:dating_app/data/models/broker_deal.dart';
import 'package:dating_app/data/repositories/broker_cloud_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a broker's pipeline deals locally.
///
/// One SharedPreferences JSON key holds the full list — same lightweight
/// local-first pattern as [SavedSearchRepository]. Standalone, no provider
/// dependency; never throws on read.
class BrokerDealRepository {
  BrokerDealRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'broker_pipeline_deals';

  /// All deals, open ones first then by title (stable list for the dashboard).
  Future<List<BrokerDeal>> loadAll() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <BrokerDeal>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map((e) => BrokerDeal.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        list.sort((a, b) {
          if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
          return a.propertyTitle.compareTo(b.propertyTitle);
        });
        return list;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BrokerDealRepository.loadAll failed: $e');
    }
    return <BrokerDeal>[];
  }

  /// Inserts a new deal or replaces the one with the same id. Returns the
  /// updated (re-sorted) list.
  Future<List<BrokerDeal>> save(BrokerDeal deal) async {
    final all = await loadAll();
    final next = [
      deal,
      ...all.where((d) => d.id != deal.id),
    ];
    await _persist(next);
    return loadAll();
  }

  /// Removes the deal with [id]. Returns the updated list.
  Future<List<BrokerDeal>> delete(String id) async {
    final all = await loadAll();
    final next = all.where((d) => d.id != id).toList();
    await _persist(next);
    return next;
  }

  Future<void> _persist(List<BrokerDeal> deals) async {
    final prefs = await _prefsFuture;
    final raw = jsonEncode(deals.map((d) => d.toJson()).toList());
    await prefs.setString(_key, raw);
    BrokerCloudSync.instance.push(_key, raw); // cloud backup (fire-and-forget)
  }
}
