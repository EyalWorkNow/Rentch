import 'dart:convert';

import 'package:dating_app/data/models/availability_slot.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a landlord's / agent's availability slots locally.
///
/// Same local-first shape as [BrokerViewingRepository]: one JSON key in
/// SharedPreferences, fail-soft, no backend. A landlord marks a handful of free
/// windows a week, so reading/writing the whole list at once is plenty.
/// Phase-3 adds Google Calendar sync on top of this store.
class AvailabilityRepository {
  AvailabilityRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'landlord_availability_v1';

  /// All slots (unsorted — the screen sorts). Empty on any error. Also prunes
  /// slots whose time already passed so the list can't grow forever.
  Future<List<AvailabilitySlot>> loadAll() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <AvailabilitySlot>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final now = DateTime.now();
        final all = decoded
            .whereType<Map>()
            .map((e) => AvailabilitySlot.fromJson(Map<String, dynamic>.from(e)))
            // keep slots that haven't ended yet (a little grace for "today")
            .where((s) => s.end.isAfter(now.subtract(const Duration(hours: 2))))
            .toList();
        return all;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AvailabilityRepository.loadAll failed: $e');
    }
    return <AvailabilitySlot>[];
  }

  /// Inserts a slot, or replaces one with the same id. Returns the updated list.
  Future<List<AvailabilitySlot>> save(AvailabilitySlot slot) async {
    final all = await loadAll();
    final next = [slot, ...all.where((s) => s.id != slot.id)];
    await _persist(next);
    return next;
  }

  /// Removes the slot with [id]. Returns the updated list.
  Future<List<AvailabilitySlot>> delete(String id) async {
    final all = await loadAll();
    final next = all.where((s) => s.id != id).toList();
    await _persist(next);
    return next;
  }

  Future<void> _persist(List<AvailabilitySlot> slots) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(
          _key, jsonEncode(slots.map((s) => s.toJson()).toList()));
    } catch (e) {
      if (kDebugMode) debugPrint('AvailabilityRepository._persist failed: $e');
    }
  }
}
