import 'dart:convert';

import 'package:dating_app/data/models/broker_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the broker's client book (פנקס לקוחות) locally.
///
/// A broker's client list is private and small, so it doesn't need a backend.
/// We reuse the app's existing local store (SharedPreferences) and keep the
/// whole list under a single JSON key — one read/write per change, stable
/// ordering. Mirrors [SavedSearchRepository] so the code is familiar and
/// fail-soft (never throws on a bad/empty store).
class BrokerClientRepository {
  BrokerClientRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'broker_clients';

  /// All clients, newest first. Empty (never throws) on any error.
  Future<List<BrokerClient>> loadAll() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <BrokerClient>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => BrokerClient.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BrokerClientRepository.loadAll failed: $e');
    }
    return <BrokerClient>[];
  }

  /// Inserts a new client at the top, or replaces an existing one with the same
  /// id. Returns the updated list.
  Future<List<BrokerClient>> save(BrokerClient client) async {
    final all = await loadAll();
    final next = [
      client,
      ...all.where((c) => c.id != client.id),
    ];
    await _persist(next);
    return next;
  }

  /// Removes the client with [id]. Returns the updated list.
  Future<List<BrokerClient>> delete(String id) async {
    final all = await loadAll();
    final next = all.where((c) => c.id != id).toList();
    await _persist(next);
    return next;
  }

  Future<void> _persist(List<BrokerClient> clients) async {
    final prefs = await _prefsFuture;
    await prefs.setString(
      _key,
      jsonEncode(clients.map((c) => c.toJson()).toList()),
    );
  }
}
