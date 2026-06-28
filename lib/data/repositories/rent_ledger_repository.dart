import 'dart:convert';

import 'package:dating_app/data/models/rent_ledger.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-property rent ledgers locally.
///
/// Rent tracking is a private, landlord-only bookkeeping aid; it does not need a
/// backend. We reuse the app's existing local persistence (SharedPreferences,
/// the same store used by [GamificationService]) and key each ledger by its
/// propertyId. One JSON string per property keeps reads/writes cheap and
/// isolated — touching one property's ledger never rewrites another's.
class RentLedgerRepository {
  RentLedgerRepository({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _keyPrefix = 'rent_ledger_';

  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static String _keyFor(String propertyId) => '$_keyPrefix${_safe(propertyId)}';

  /// Loads the ledger for [propertyId]. Returns an empty (but valid) ledger when
  /// none has been saved yet, so callers always get a usable object.
  Future<RentLedger> load(String propertyId) async {
    if (propertyId.isEmpty) return RentLedger(propertyId: propertyId);
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_keyFor(propertyId));
    if (raw == null || raw.isEmpty) {
      return RentLedger(propertyId: propertyId);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final ledger = RentLedger.fromJson(Map<String, dynamic>.from(decoded));
        // Ensure the ledger's id always matches the key it was loaded under.
        return RentLedger(propertyId: propertyId, entries: ledger.entries);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RentLedgerRepository.load failed: $e');
    }
    return RentLedger(propertyId: propertyId);
  }

  /// Saves [ledger] under its propertyId. No-op for an empty propertyId.
  Future<void> save(RentLedger ledger) async {
    if (ledger.propertyId.isEmpty) return;
    final prefs = await _prefsFuture;
    await prefs.setString(
      _keyFor(ledger.propertyId),
      jsonEncode(ledger.toJson()),
    );
  }

  /// Removes the stored ledger for [propertyId] (e.g. when a property is deleted).
  Future<void> delete(String propertyId) async {
    if (propertyId.isEmpty) return;
    final prefs = await _prefsFuture;
    await prefs.remove(_keyFor(propertyId));
  }
}
