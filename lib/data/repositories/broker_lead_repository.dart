import 'dart:convert';

import 'package:dating_app/data/models/broker_lead.dart';
import 'package:dating_app/data/repositories/broker_cloud_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a broker's lead pipeline locally.
///
/// A broker has tens — not thousands — of open leads, so the whole list lives
/// under one JSON key in the app's existing local store (the same
/// SharedPreferences the saved-search/rent-ledger features use). Standalone, no
/// provider dependency. Every read is fail-soft: a corrupt blob yields an empty
/// list rather than throwing into the UI.
class BrokerLeadRepository {
  BrokerLeadRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'broker_leads';

  /// All leads, newest first. Empty (never throws) on any error.
  Future<List<BrokerLead>> loadAll() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <BrokerLead>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => BrokerLead.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BrokerLeadRepository.loadAll failed: $e');
    }
    return <BrokerLead>[];
  }

  /// Inserts a new lead at the top, or replaces an existing one with the same
  /// id. Returns the updated list.
  Future<List<BrokerLead>> save(BrokerLead lead) async {
    final all = await loadAll();
    final next = [
      lead,
      ...all.where((l) => l.id != lead.id),
    ];
    await _persist(next);
    return next;
  }

  /// Removes the lead with [id]. Returns the updated list.
  Future<List<BrokerLead>> delete(String id) async {
    final all = await loadAll();
    final next = all.where((l) => l.id != id).toList();
    await _persist(next);
    return next;
  }

  Future<void> _persist(List<BrokerLead> leads) async {
    final prefs = await _prefsFuture;
    final raw = jsonEncode(leads.map((l) => l.toJson()).toList());
    await prefs.setString(_key, raw);
    BrokerCloudSync.instance.push(_key, raw); // cloud backup (fire-and-forget)
  }
}
