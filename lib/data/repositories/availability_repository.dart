import 'dart:async';
import 'dart:convert';

import 'package:dating_app/data/models/availability_slot.dart';
import 'package:dating_app/data/repositories/broker_cloud_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a landlord's / agent's availability slots.
///
/// LOCAL-FIRST with cloud sync: SharedPreferences stays the instant, offline
/// cache (same shape as before), and the whole list is mirrored to the
/// owner-scoped `/broker_data/viewing_slots` doc — the SAME doc the Rently
/// website's calendar tab reads/writes — so the app and the website always show
/// the same calendar. The cloud doc uses the WEBSITE's ViewingSlot field names
/// (`dateISO`/`time`/`durationMin`/`booked`); the website is the contract and
/// app-only fields ride along under keys it ignores.
class AvailabilityRepository {
  AvailabilityRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _key = 'landlord_availability_v1';

  /// Cloud doc name — MUST match the website's SLOTS_DOC (portal-api.ts).
  static const String _cloudDoc = 'viewing_slots';

  /// All slots (unsorted — the screen sorts). Empty on any error. Merges the
  /// cloud doc into the local cache first (cloud wins per id, local-only slots
  /// are kept), then prunes slots whose time already passed so the list can't
  /// grow forever.
  Future<List<AvailabilitySlot>> loadAll() async {
    await _mergeCloudIntoLocal();
    return _loadLocal();
  }

  /// Inserts a slot, or replaces one with the same id. Returns the updated list.
  Future<List<AvailabilitySlot>> save(AvailabilitySlot slot) async {
    final all = await _loadLocal();
    final next = [slot, ...all.where((s) => s.id != slot.id)];
    await _persist(next);
    return next;
  }

  /// Removes the slot with [id]. Returns the updated list.
  Future<List<AvailabilitySlot>> delete(String id) async {
    final all = await _loadLocal();
    final next = all.where((s) => s.id != id).toList();
    await _persist(next);
    return next;
  }

  // ── Local cache ────────────────────────────────────────────────────────────

  Future<List<AvailabilitySlot>> _loadLocal() async {
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
      if (kDebugMode) debugPrint('AvailabilityRepository._loadLocal failed: $e');
    }
    return <AvailabilitySlot>[];
  }

  Future<void> _persist(List<AvailabilitySlot> slots) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(
          _key, jsonEncode(slots.map((s) => s.toJson()).toList()));
    } catch (e) {
      if (kDebugMode) debugPrint('AvailabilityRepository._persist failed: $e');
    }
    // Write-through to the shared cloud doc — fire-and-forget, so a flaky
    // network never blocks the calendar (local cache already updated).
    _pushToCloud(slots);
  }

  // ── Cloud sync (shared doc with the website) ───────────────────────────────

  /// Pulls `/broker_data/viewing_slots` and merges it into the local cache.
  /// Cloud wins on a conflicting id (the doc-level updatedAt makes the cloud
  /// copy the most recent committed state); local-only slots — e.g. added while
  /// offline — are kept and pushed back up. Fail-soft: any error leaves the
  /// local cache untouched.
  Future<void> _mergeCloudIntoLocal() async {
    final raw = await BrokerCloudSync.instance.pull(_cloudDoc);
    if (raw == null || raw.isEmpty) return;
    List<AvailabilitySlot> cloud;
    try {
      final decoded = jsonDecode(raw);
      final list = (decoded is Map) ? decoded['slots'] : null;
      if (list is! List) return;
      cloud = list
          .whereType<Map>()
          .map((e) => _slotFromCloudJson(Map<String, dynamic>.from(e)))
          .whereType<AvailabilitySlot>()
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AvailabilityRepository: bad cloud doc ignored: $e');
      }
      return;
    }
    final local = await _loadLocal();
    final cloudIds = cloud.map((s) => s.id).toSet();
    final localOnly = local.where((s) => !cloudIds.contains(s.id)).toList();
    final merged = [...cloud, ...localOnly];
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(
          _key, jsonEncode(merged.map((s) => s.toJson()).toList()));
    } catch (e) {
      if (kDebugMode) debugPrint('AvailabilityRepository merge write failed: $e');
    }
    // Local had slots the cloud doesn't know about (offline adds) → sync up.
    if (localOnly.isNotEmpty) _pushToCloud(merged);
  }

  void _pushToCloud(List<AvailabilitySlot> slots) {
    final doc = jsonEncode({'slots': slots.map(_slotToCloudJson).toList()});
    // Intentionally fire-and-forget (see _persist) — push() never throws.
    unawaited(BrokerCloudSync.instance.push(_cloudDoc, doc));
  }

  // ── Mapping: app AvailabilitySlot ⇄ website ViewingSlot ────────────────────
  //
  // Website contract (portal-api.ts ViewingSlot):
  //   { id, dateISO: 'YYYY-MM-DD', time: 'HH:mm', durationMin,
  //     propertyId?, note?, tag?, booked? }
  // App-only fields (bookedByName/bookedByPhone) are stored under their own
  // keys, which the website simply ignores.

  static String _two(int n) => n.toString().padLeft(2, '0');

  Map<String, dynamic> _slotToCloudJson(AvailabilitySlot s) => {
        'id': s.id,
        'dateISO':
            '${s.start.year}-${_two(s.start.month)}-${_two(s.start.day)}',
        'time': '${_two(s.start.hour)}:${_two(s.start.minute)}',
        'durationMin': s.durationMinutes,
        if (s.propertyId.isNotEmpty) 'propertyId': s.propertyId,
        if (s.note.isNotEmpty) 'note': s.note,
        if (s.tag.isNotEmpty) 'tag': s.tag,
        if (s.status == SlotStatus.booked) 'booked': true,
        // app-only extras — unknown to (and ignored by) the website
        if (s.bookedByName.isNotEmpty) 'bookedByName': s.bookedByName,
        if (s.bookedByPhone.isNotEmpty) 'bookedByPhone': s.bookedByPhone,
      };

  AvailabilitySlot? _slotFromCloudJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final start = DateTime.tryParse(
        '${json['dateISO']?.toString() ?? ''}T${json['time']?.toString() ?? '00:00'}');
    if (start == null) return null;
    return AvailabilitySlot(
      id: id,
      start: start,
      durationMinutes: (json['durationMin'] as num?)?.toInt() ?? 30,
      propertyId: json['propertyId']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      tag: json['tag']?.toString() ?? '',
      status: json['booked'] == true ? SlotStatus.booked : SlotStatus.open,
      bookedByName: json['bookedByName']?.toString() ?? '',
      bookedByPhone: json['bookedByPhone']?.toString() ?? '',
    );
  }
}
