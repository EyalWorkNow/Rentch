import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A PRIVATE, on-device note the user attaches to a conversation — free text +
/// a colour. It is stored ONLY in local SharedPreferences and is NEVER sent to
/// the backend or the other party, so the candidate can never see it.
class MatchLabel {
  const MatchLabel({required this.text, required this.color});

  final String text;
  final int color; // ARGB int

  Map<String, dynamic> toJson() => {'t': text, 'c': color};

  factory MatchLabel.fromJson(Map<dynamic, dynamic> j) => MatchLabel(
        text: (j['t'] ?? '').toString(),
        color: j['c'] is int
            ? j['c'] as int
            : int.tryParse('${j['c']}') ?? 0xFF2563EB,
      );
}

/// Local-only store: matchId → MatchLabel. Mirrors the SavedSearchRepository
/// single-JSON-key pattern; nothing here ever leaves the device.
class MatchLabelsRepository {
  static const String _key = 'match_labels_v1';

  Future<Map<String, MatchLabel>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) =>
            MapEntry(k.toString(), MatchLabel.fromJson(v as Map)));
      }
    } catch (_) {/* corrupt → empty */}
    return {};
  }

  Future<void> set(String matchId, MatchLabel label) async {
    final all = await loadAll();
    all[matchId] = label;
    await _save(all);
  }

  Future<void> remove(String matchId) async {
    final all = await loadAll();
    if (all.remove(matchId) != null) await _save(all);
  }

  Future<void> _save(Map<String, MatchLabel> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
  }
}
